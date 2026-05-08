#!/bin/bash
# Re-sign an APK with the fdroid keystore on the mounted bucket.
# Usage: resign-apk.sh <input.apk> [output.apk]
set -euo pipefail
source "$(dirname "$0")/common.sh"

mountpoint -q "${MOUNT}" || die "bucket not mounted at ${MOUNT}"

IN="${1:-}"; OUT="${2:-}"
[ -n "${IN}" ] || die "usage: $0 <input.apk> [output.apk]"
[ -f "${IN}" ] || die "input not found: ${IN}"

KEYSTORE="${MOUNT}/keys/fdroid.keystore"
# shellcheck disable=SC1091
. "${MOUNT}/keys/passwords.env"

TMP="$(mktemp -d)"; trap 'rm -rf "${TMP}"' EXIT
ALIGNED="${TMP}/aligned.apk"
SIGNED="${OUT:-${IN%.apk}-signed.apk}"

# Strip prior signatures only — NOT all of META-INF.
# `META-INF/*` would also delete `META-INF/services/*` (ServiceLoader
# providers — kotlinx.coroutines.android needs these for Dispatchers.Main)
# and `META-INF/*.kotlin_module` (Kotlin reflection metadata).
( cd "${TMP}" && cp "${IN}" ./in.apk && \
    zip -dq ./in.apk \
        'META-INF/MANIFEST.MF' \
        'META-INF/*.SF' \
        'META-INF/*.RSA' \
        'META-INF/*.DSA' \
        'META-INF/*.EC' \
        || true )
zipalign -f -p 4 "${TMP}/in.apk" "${ALIGNED}"

apksigner sign \
    --ks "${KEYSTORE}" \
    --ks-key-alias "${FDROID_KEY_ALIAS:-${KEY_ALIAS}}" \
    --ks-pass "pass:${FDROID_KEYSTORE_PASSWORD}" \
    --key-pass "pass:${FDROID_KEY_PASSWORD}" \
    --out "${SIGNED}" \
    "${ALIGNED}"

apksigner verify --print-certs "${SIGNED}" >/dev/null
echo "[resign] ${IN} -> ${SIGNED}"
