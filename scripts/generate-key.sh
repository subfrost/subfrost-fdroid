#!/bin/bash
# Generate an F-Droid signing keystore directly on the mounted bucket.
# REFUSES to overwrite an existing keystore — back it up and delete it manually
# if you truly want to rotate (rotating invalidates all previously-signed APKs).
set -euo pipefail
source "$(dirname "$0")/common.sh"

mountpoint -q "${MOUNT}" || die "bucket not mounted at ${MOUNT}. Run scripts/mount-fdroid.sh first."

KEYS_DIR="${MOUNT}/keys"
KEYSTORE="${KEYS_DIR}/fdroid.keystore"
PASSWORDS="${KEYS_DIR}/passwords.env"

mkdir -p "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

if [ -f "${KEYSTORE}" ]; then
    die "keystore already exists at ${KEYSTORE}. Refusing to overwrite. (Versioning keeps history but rotating breaks client updates.)"
fi

STOREPASS="$(openssl rand -base64 36 | tr -d '/+=\n' | head -c 40)"
KEYPASS="${STOREPASS}"

keytool -genkey -v \
    -keystore "${KEYSTORE}" \
    -alias "${KEY_ALIAS}" \
    -keyalg RSA -keysize 4096 -validity 10000 \
    -storepass "${STOREPASS}" -keypass "${KEYPASS}" \
    -dname "CN=Subfrost F-Droid, O=Subfrost, L=Internet, C=US"

umask 077
cat > "${PASSWORDS}" <<EOF
FDROID_KEYSTORE_PASSWORD=${STOREPASS}
FDROID_KEY_PASSWORD=${KEYPASS}
FDROID_KEY_ALIAS=${KEY_ALIAS}
EOF
chmod 600 "${PASSWORDS}" "${KEYSTORE}"

echo "[key] keystore: ${KEYSTORE}"
echo "[key] passwords: ${PASSWORDS}"
echo "[key] fingerprint:"
keytool -list -v -keystore "${KEYSTORE}" -storepass "${STOREPASS}" -alias "${KEY_ALIAS}" | grep -E "SHA256|Valid"
