#!/bin/bash
# CI/CD Script to publish APKs to F-Droid Repository
# This script is called from the subtun-android CI pipeline after a successful build

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Configuration
SUBTUN_PROJECT="${SUBTUN_PROJECT:-/data/subtun-android}"
FDROID_PROJECT="${FDROID_PROJECT:-/data/subfrost-fdroid}"
GCP_PROJECT="${GCP_PROJECT:-subfrost}"
GCP_REGION="${GCP_REGION:-us-central1}"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-fdroid-repo}"
GCS_BUCKET="${GCS_BUCKET:-subfrost-fdroid-repo}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  build           Build the APK from subtun-android"
    echo "  publish         Build and publish APK to F-Droid repo"
    echo "  sync            Sync local repo to GCS and update Cloud Run"
    echo "  deploy          Deploy/update Cloud Run service"
    echo "  full            Full pipeline: build → publish → sync → deploy"
    echo ""
    echo "Options:"
    echo "  --release       Build release APK (default: debug)"
    echo "  --version VER   Version tag for the release"
    echo ""
    echo "Environment variables:"
    echo "  SUBTUN_PROJECT    Path to subtun-android project"
    echo "  FDROID_PROJECT    Path to subfrost-fdroid project"
    echo "  GCP_PROJECT       GCP project ID"
    echo "  GCS_BUCKET        GCS bucket for repo storage"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Build APK from subtun-android
build_apk() {
    local build_type="${1:-debug}"

    log_info "Building Subtun APK ($build_type)..."

    cd "$SUBTUN_PROJECT"

    # Source Android environment
    if [ -f ".android-env" ]; then
        source .android-env
    fi

    # Run build script
    if [ "$build_type" = "release" ]; then
        BUILD_TYPE=release ./scripts/build-android.sh
    else
        BUILD_TYPE=debug ./scripts/build-android.sh
    fi

    log_success "APK build complete"
}

# Publish APK to F-Droid repository
publish_apk() {
    local build_type="${1:-debug}"
    local version="${2:-}"

    log_info "Publishing APK to F-Droid repository..."

    cd "$SUBTUN_PROJECT"

    # Find the built APK
    local apk_dir="app/build/outputs/apk/$build_type"
    local apk_file=""

    # Prefer universal APK, then arm64
    if [ -f "$apk_dir/app-universal-${build_type}.apk" ]; then
        apk_file="$apk_dir/app-universal-${build_type}.apk"
    elif [ -f "$apk_dir/app-arm64-v8a-${build_type}.apk" ]; then
        apk_file="$apk_dir/app-arm64-v8a-${build_type}.apk"
    else
        apk_file=$(find "$apk_dir" -name "*.apk" -type f | head -1)
    fi

    if [ -z "$apk_file" ] || [ ! -f "$apk_file" ]; then
        log_error "No APK found in $apk_dir"
        exit 1
    fi

    log_info "Found APK: $apk_file"

    # Copy APK to fdroid repo
    local dest_name="io.subfrost.subtun"
    if [ -n "$version" ]; then
        dest_name="${dest_name}_${version}"
    fi
    dest_name="${dest_name}.apk"

    mkdir -p "$FDROID_PROJECT/repo"
    cp "$apk_file" "$FDROID_PROJECT/repo/$dest_name"

    log_info "Copied to: $FDROID_PROJECT/repo/$dest_name"

    # Update metadata
    create_metadata

    # Update repository index
    update_repo_index

    log_success "APK published to F-Droid repository"
}

# Create/update app metadata
create_metadata() {
    log_info "Creating app metadata..."

    mkdir -p "$FDROID_PROJECT/metadata"

    cat > "$FDROID_PROJECT/metadata/io.subfrost.subtun.yml" << 'EOF'
Categories:
  - Security
  - Internet

License: GPL-3.0-or-later
AuthorName: Subfrost
AuthorEmail: support@subfrost.io
WebSite: https://subfrost.io
SourceCode: https://github.com/subfrost/subtun-android
IssueTracker: https://github.com/subfrost/subtun-android/issues

AutoName: Subtun

Summary: Secure VPN tunnel powered by Subfrost

Description: |
  Subtun is a high-performance VPN application built on the Subfrost
  protocol. It provides secure, encrypted tunneling for your Android device.

  Features:
  * Fast and reliable VPN connection
  * Modern cryptographic protocols
  * Privacy-focused design
  * Open source and auditable

RepoType: git
Repo: https://github.com/subfrost/subtun-android

CurrentVersion: 0.1.0
CurrentVersionCode: 1

Builds: []

AutoUpdateMode: None
UpdateCheckMode: None
EOF

    log_success "Metadata created"
}

# Update F-Droid repository index
update_repo_index() {
    log_info "Updating F-Droid repository index..."

    cd "$FDROID_PROJECT"

    # Check if config.py exists, create if not
    if [ ! -f "config.py" ]; then
        cat > "config.py" << 'PYEOF'
#!/usr/bin/env python3
import os

repo_url = os.environ.get('FDROID_REPO_URL', 'https://f-droid.subfrost.io/fdroid/repo')
repo_name = 'Subfrost F-Droid Repository'
repo_description = 'Official F-Droid repository for Subfrost applications.'

keystore = 'keystore/fdroid.keystore'
keystorepass = os.environ.get('FDROID_KEYSTORE_PASS', 'changeme')
keypass = os.environ.get('FDROID_KEY_PASS', 'changeme')
keydname = 'CN=Subfrost, OU=F-Droid Repository, O=Subfrost, L=Internet, C=XX'
repo_keyalias = 'fdroid'
allow_disabled_algorithms = True
archive_older = 0
PYEOF
    fi

    # Initialize if needed
    if [ ! -d "keystore" ]; then
        log_info "Initializing keystore..."
        mkdir -p keystore
        fdroid init || true
    fi

    # Update repository
    fdroid update --create-metadata --allow-disabled-algorithms

    log_success "Repository index updated"
}

# Sync to GCS
sync_to_gcs() {
    log_info "Syncing repository to GCS..."

    # Sync repo directory to GCS
    gsutil -m rsync -r -d "$FDROID_PROJECT/repo" "gs://$GCS_BUCKET/fdroid/repo"

    # Copy index.html to bucket root
    if [ -f "$FDROID_PROJECT/index.html" ]; then
        gsutil cp "$FDROID_PROJECT/index.html" "gs://$GCS_BUCKET/"
    fi

    log_success "Repository synced to gs://$GCS_BUCKET"
}

# Deploy to Cloud Run
deploy_cloud_run() {
    log_info "Deploying to Cloud Run..."

    cd "$FDROID_PROJECT"

    # Build container image
    local image="gcr.io/$GCP_PROJECT/$CLOUD_RUN_SERVICE:latest"

    log_info "Building container image: $image"
    gcloud builds submit --tag "$image" .

    # Deploy to Cloud Run
    log_info "Deploying to Cloud Run: $CLOUD_RUN_SERVICE"
    gcloud run deploy "$CLOUD_RUN_SERVICE" \
        --image "$image" \
        --platform managed \
        --region "$GCP_REGION" \
        --allow-unauthenticated \
        --port 8080 \
        --memory 256Mi \
        --cpu 1 \
        --min-instances 0 \
        --max-instances 3 \
        --set-env-vars "FDROID_REPO_URL=https://f-droid.subfrost.io/fdroid/repo"

    log_success "Deployed to Cloud Run"

    # Get service URL
    local url=$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
        --platform managed \
        --region "$GCP_REGION" \
        --format 'value(status.url)')

    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  F-Droid Repository deployed successfully!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo ""
    echo "  Cloud Run URL: $url"
    echo "  Custom Domain: https://f-droid.subfrost.io"
    echo ""
}

# Full pipeline
full_pipeline() {
    local build_type="${1:-release}"
    local version="${2:-}"

    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Subfrost F-Droid Full Deployment Pipeline${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
    echo ""

    build_apk "$build_type"
    publish_apk "$build_type" "$version"
    sync_to_gcs
    deploy_cloud_run

    echo ""
    log_success "Full pipeline completed!"
}

# Parse arguments
BUILD_TYPE="debug"
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --release)
            BUILD_TYPE="release"
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        build)
            build_apk "$BUILD_TYPE"
            exit 0
            ;;
        publish)
            publish_apk "$BUILD_TYPE" "$VERSION"
            exit 0
            ;;
        sync)
            sync_to_gcs
            exit 0
            ;;
        deploy)
            deploy_cloud_run
            exit 0
            ;;
        full)
            full_pipeline "$BUILD_TYPE" "$VERSION"
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown command: $1"
            usage
            exit 1
            ;;
    esac
done

# Default to showing usage
usage
