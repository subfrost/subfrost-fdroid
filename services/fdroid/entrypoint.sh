#!/bin/bash
set -e

echo "[fdroid] starting"

FDROID_ROOT="/fdroid"
KEYS_DIR="${FDROID_ROOT}/keys"
REPO_DIR="${FDROID_ROOT}/repo"
ARCHIVE_DIR="${FDROID_ROOT}/archive"
METADATA_DIR="${FDROID_ROOT}/metadata"

mkdir -p "${REPO_DIR}" "${ARCHIVE_DIR}" "${METADATA_DIR}" /var/www/fdroid/api

# Seed metadata from image if the bucket metadata/ is empty
if [ -z "$(ls -A "${METADATA_DIR}" 2>/dev/null)" ]; then
    cp -n /etc/fdroid/metadata/*.yml "${METADATA_DIR}/" 2>/dev/null || true
fi

# fdroidserver expects config.yml in cwd; provide it from image config
cp /etc/fdroid/config.yml "${FDROID_ROOT}/config.yml"

# Load passwords from bucket-mounted env file
if [ -f "${KEYS_DIR}/passwords.env" ]; then
    # shellcheck disable=SC1090
    set -a; . "${KEYS_DIR}/passwords.env"; set +a
fi
export FDROID_KEY_STORE_PASS="${FDROID_KEYSTORE_PASSWORD:-${FDROID_KEY_STORE_PASS:-}}"
export FDROID_KEY_PASS="${FDROID_KEY_PASSWORD:-${FDROID_KEY_PASS:-}}"

if [ -f "${KEYS_DIR}/fdroid.keystore" ]; then
    if keytool -list -keystore "${KEYS_DIR}/fdroid.keystore" -storepass "${FDROID_KEY_STORE_PASS}" >/dev/null 2>&1; then
        echo "[fdroid] keystore OK"
    else
        echo "[fdroid] WARN: keystore validation failed"
    fi
else
    echo "[fdroid] WARN: no keystore at ${KEYS_DIR}/fdroid.keystore — serving read-only"
fi

# Icons
mkdir -p "${REPO_DIR}/icons"
for dpi in 120 160 240 320 480 640; do
    mkdir -p "${REPO_DIR}/icons-${dpi}"
done

# Run fdroid update only if there are APKs and the existing index is stale.
if [ -f "${KEYS_DIR}/fdroid.keystore" ] && ls "${REPO_DIR}"/*.apk 1>/dev/null 2>&1; then
    INDEX="${REPO_DIR}/index-v1.json"
    NEWEST_APK_TS=$(find "${REPO_DIR}" -maxdepth 1 -name '*.apk' -printf '%T@\n' 2>/dev/null | sort -n | tail -1 | cut -d. -f1)
    INDEX_TS=$( [ -f "${INDEX}" ] && stat -c %Y "${INDEX}" || echo 0 )
    if [ "${INDEX_TS}" -ge "${NEWEST_APK_TS:-0}" ]; then
        echo "[fdroid] index up-to-date (ts=${INDEX_TS} >= newest apk ts=${NEWEST_APK_TS}), skipping update"
    else
        cd "${FDROID_ROOT}"
        echo "[fdroid] running fdroid update (index ts=${INDEX_TS} < newest apk ts=${NEWEST_APK_TS})"
        fdroid update --create-metadata --verbose 2>&1 || echo "[fdroid] update failed (continuing to serve)"
    fi
fi

# Always restore the real repo icon AFTER fdroid update — fdroidserver
# clobbers repo/icons/icon.png with a 370x370 placeholder during the
# index-build pass, so we put our SUBFROST logo back unconditionally.
if [ -f /var/www/fdroid/assets/icon.png ]; then
    cp -f /var/www/fdroid/assets/icon.png "${REPO_DIR}/icons/icon.png" 2>/dev/null || true
fi

if [ -f "${REPO_DIR}/index-v1.json" ]; then
    cp "${REPO_DIR}/index-v1.json" /var/www/fdroid/api/index.json
elif [ ! -f /var/www/fdroid/api/index.json ]; then
    echo '{"repo":{"name":"SUBFROST","description":"Official F-Droid repository for SUBFROST.","timestamp":0},"apps":[]}' > /var/www/fdroid/api/index.json
fi

exec nginx -g 'daemon off;'
