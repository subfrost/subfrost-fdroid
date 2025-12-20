#!/bin/bash
# F-Droid Repository Update Script
# Called by CI/CD to add new APKs and update the repository index

set -e

FDROID_DIR="${FDROID_DIR:-/var/www/fdroid}"
REPO_DIR="$FDROID_DIR/repo"
METADATA_DIR="$FDROID_DIR/metadata"

usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  add <apk_path>     Add an APK to the repository"
    echo "  update             Update repository index"
    echo "  fingerprint        Show repository fingerprint"
    echo "  list               List all APKs in repository"
    echo "  remove <package>   Remove an app from repository"
    echo ""
    echo "Environment variables:"
    echo "  FDROID_DIR         Repository directory (default: /var/www/fdroid)"
    echo "  FDROID_KEYSTORE_PASS  Keystore password"
    echo "  FDROID_KEY_PASS       Key password"
}

add_apk() {
    local apk_path="$1"

    if [ ! -f "$apk_path" ]; then
        echo "Error: APK file not found: $apk_path"
        exit 1
    fi

    echo "Adding APK: $apk_path"

    # Copy APK to repo directory
    cp "$apk_path" "$REPO_DIR/"

    echo "APK added successfully. Run 'update' to refresh the repository index."
}

update_repo() {
    echo "Updating F-Droid repository index..."

    cd "$FDROID_DIR"

    # Create metadata from APKs if not exists
    fdroid update --create-metadata --allow-disabled-algorithms

    echo ""
    echo "Repository updated successfully!"
    echo ""
    echo "APKs in repository:"
    ls -la "$REPO_DIR"/*.apk 2>/dev/null || echo "  No APKs found"
}

show_fingerprint() {
    local keystore="$FDROID_DIR/keystore/fdroid.keystore"
    local pass="${FDROID_KEYSTORE_PASS:-changeme}"

    if [ ! -f "$keystore" ]; then
        echo "Error: Keystore not found at $keystore"
        exit 1
    fi

    echo "Repository Fingerprint:"
    keytool -list -v -keystore "$keystore" -alias fdroid -storepass "$pass" 2>/dev/null \
        | grep -A1 "SHA256:" | head -2
}

list_apks() {
    echo "APKs in repository ($REPO_DIR):"
    echo ""

    if ls "$REPO_DIR"/*.apk 1>/dev/null 2>&1; then
        for apk in "$REPO_DIR"/*.apk; do
            basename "$apk"
        done
    else
        echo "  No APKs found"
    fi
}

remove_app() {
    local package="$1"

    echo "Removing package: $package"

    # Remove APKs matching package name
    rm -f "$REPO_DIR"/${package}*.apk

    # Remove metadata
    rm -f "$METADATA_DIR"/${package}.yml

    echo "Package removed. Run 'update' to refresh the repository index."
}

# Main command handler
case "${1:-}" in
    add)
        shift
        add_apk "$@"
        ;;
    update)
        update_repo
        ;;
    fingerprint)
        show_fingerprint
        ;;
    list)
        list_apks
        ;;
    remove)
        shift
        remove_app "$@"
        ;;
    *)
        usage
        exit 1
        ;;
esac
