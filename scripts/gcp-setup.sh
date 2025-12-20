#!/bin/bash
# GCP Infrastructure Setup for F-Droid Repository
# Run this once to set up all required GCP resources

set -e

# Configuration
GCP_PROJECT="${GCP_PROJECT:-subfrost}"
GCP_REGION="${GCP_REGION:-us-central1}"
CLOUD_RUN_SERVICE="${CLOUD_RUN_SERVICE:-fdroid-repo}"
GCS_BUCKET="${GCS_BUCKET:-subfrost-fdroid-repo}"
DOMAIN="${DOMAIN:-f-droid.subfrost.io}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Subfrost F-Droid GCP Infrastructure Setup${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

# Check gcloud is installed and authenticated
if ! command -v gcloud &> /dev/null; then
    log_error "gcloud CLI not installed. Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Set project
log_info "Setting GCP project to: $GCP_PROJECT"
gcloud config set project "$GCP_PROJECT"

# Enable required APIs
log_info "Enabling required GCP APIs..."
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    containerregistry.googleapis.com \
    storage.googleapis.com \
    domains.googleapis.com \
    dns.googleapis.com \
    secretmanager.googleapis.com

log_success "APIs enabled"

# Create GCS bucket for repo storage (optional, for static hosting backup)
log_info "Creating GCS bucket: $GCS_BUCKET"
if gsutil ls "gs://$GCS_BUCKET" 2>/dev/null; then
    log_warn "Bucket already exists"
else
    gsutil mb -l "$GCP_REGION" "gs://$GCS_BUCKET"
    gsutil iam ch allUsers:objectViewer "gs://$GCS_BUCKET"
    gsutil web set -m index.html -e 404.html "gs://$GCS_BUCKET"
    log_success "Bucket created and configured for public access"
fi

# Create secrets for keystore passwords
log_info "Setting up Secret Manager secrets..."

# Generate passwords if not set
KEYSTORE_PASS="${FDROID_KEYSTORE_PASS:-$(openssl rand -base64 32)}"
KEY_PASS="${FDROID_KEY_PASS:-$KEYSTORE_PASS}"

# Create secrets
if ! gcloud secrets describe fdroid-keystore-pass &>/dev/null; then
    echo -n "$KEYSTORE_PASS" | gcloud secrets create fdroid-keystore-pass --data-file=-
    log_success "Created secret: fdroid-keystore-pass"
else
    log_warn "Secret fdroid-keystore-pass already exists"
fi

if ! gcloud secrets describe fdroid-key-pass &>/dev/null; then
    echo -n "$KEY_PASS" | gcloud secrets create fdroid-key-pass --data-file=-
    log_success "Created secret: fdroid-key-pass"
else
    log_warn "Secret fdroid-key-pass already exists"
fi

# Grant Cloud Run access to secrets
log_info "Configuring IAM permissions..."
PROJECT_NUMBER=$(gcloud projects describe "$GCP_PROJECT" --format='value(projectNumber)')

gcloud secrets add-iam-policy-binding fdroid-keystore-pass \
    --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

gcloud secrets add-iam-policy-binding fdroid-key-pass \
    --member="serviceAccount:$PROJECT_NUMBER-compute@developer.gserviceaccount.com" \
    --role="roles/secretmanager.secretAccessor" \
    --quiet

log_success "IAM permissions configured"

# Set up Cloud Build trigger (optional)
log_info "Note: Set up Cloud Build trigger manually in console for:"
echo "  - Repository: subfrost/subfrost-fdroid"
echo "  - Branch: main"
echo "  - Config: cloudbuild.yaml"
echo ""

# Create DNS zone if using Cloud DNS
log_info "Note: DNS configuration required:"
echo "  Create an A record pointing $DOMAIN to Cloud Run"
echo "  Or use domain mapping in Cloud Run console"
echo ""

# Map custom domain to Cloud Run
log_info "To map custom domain, run:"
echo "  gcloud run domain-mappings create --service=$CLOUD_RUN_SERVICE --domain=$DOMAIN --region=$GCP_REGION"
echo ""

# Display summary
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
echo ""
echo "Resources created:"
echo "  - GCS Bucket: gs://$GCS_BUCKET"
echo "  - Secrets: fdroid-keystore-pass, fdroid-key-pass"
echo ""
echo "Next steps:"
echo "  1. Build and deploy: ./scripts/ci-publish.sh full --release"
echo "  2. Map custom domain in Cloud Run console"
echo "  3. Set up Cloud Build trigger for automated deployments"
echo ""

# Save config locally
cat > ".gcp-config" << EOF
GCP_PROJECT=$GCP_PROJECT
GCP_REGION=$GCP_REGION
CLOUD_RUN_SERVICE=$CLOUD_RUN_SERVICE
GCS_BUCKET=$GCS_BUCKET
DOMAIN=$DOMAIN
EOF

log_success "Configuration saved to .gcp-config"
