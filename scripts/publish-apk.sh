#!/bin/bash
# Drop a (signed) APK into the repo and regenerate the F-Droid index.
# Usage: publish-apk.sh <signed.apk>
set -euo pipefail
source "$(dirname "$0")/common.sh"

mountpoint -q "${MOUNT}" || die "bucket not mounted at ${MOUNT}"

APK="${1:-}"
[ -f "${APK}" ] || die "usage: $0 <signed.apk>"

KEYSTORE="${MOUNT}/keys/fdroid.keystore"
# shellcheck disable=SC1091
. "${MOUNT}/keys/passwords.env"

apksigner verify "${APK}" || die "apk signature invalid"

# Resolve canonical name `<package>_<versionCode>.apk` from APK badging
# BEFORE we copy it into repo/. F-Droid's Android client constructs the
# download URL from this convention; if we leave gradle's default
# `app-release.apk` in place the client 404s on install.
AAPT_BIN="$(command -v aapt2 || command -v aapt || true)"
CANONICAL_NAME=""
if [ -n "${AAPT_BIN}" ]; then
    BADGING_OUT="$("${AAPT_BIN}" dump badging "${APK}" 2>/dev/null || true)"
    PKG_PRE=$(printf '%s\n' "${BADGING_OUT}" | sed -nE "s/^package: name='([^']+)'.*/\1/p" | head -n1)
    VCODE_PRE=$(printf '%s\n' "${BADGING_OUT}" | sed -nE "s/.*versionCode='([^']+)'.*/\1/p" | head -n1)
    if [ -n "${PKG_PRE}" ] && [ -n "${VCODE_PRE}" ]; then
        CANONICAL_NAME="${PKG_PRE}_${VCODE_PRE}.apk"
    fi
fi

if [ -n "${CANONICAL_NAME}" ]; then
    cp "${APK}" "${MOUNT}/repo/${CANONICAL_NAME}"
    echo "[publish] copied as ${CANONICAL_NAME}"
else
    echo "[publish] WARN: aapt missing or APK didn't yield package/versionCode; using original filename" >&2
    cp "${APK}" "${MOUNT}/repo/"
fi

# Auto-bump CurrentVersion / CurrentVersionCode in metadata so the
# F-Droid client's "Suggested" version always tracks the latest APK.
if [ -n "${AAPT_BIN}" ]; then
    DUMP=$("${AAPT_BIN}" dump badging "${APK}" 2>/dev/null || true)
    PKG=$(printf '%s\n' "${DUMP}" | sed -nE "s/^package: name='([^']+)'.*/\1/p" | head -n1)
    VNAME=$(printf '%s\n' "${DUMP}" | sed -nE "s/.*versionName='([^']+)'.*/\1/p" | head -n1)
    VCODE=$(printf '%s\n' "${DUMP}" | sed -nE "s/.*versionCode='([^']+)'.*/\1/p" | head -n1)
    META="${MOUNT}/metadata/${PKG}.yml"
    if [ -n "${PKG}" ] && [ -n "${VNAME}" ] && [ -n "${VCODE}" ] && [ -f "${META}" ]; then
        if grep -q '^CurrentVersion:' "${META}"; then
            sed -i "s|^CurrentVersion:.*|CurrentVersion: '${VNAME}'|" "${META}"
        else
            printf '\nCurrentVersion: %s\n' "'${VNAME}'" >> "${META}"
        fi
        if grep -q '^CurrentVersionCode:' "${META}"; then
            sed -i "s|^CurrentVersionCode:.*|CurrentVersionCode: ${VCODE}|" "${META}"
        else
            printf 'CurrentVersionCode: %s\n' "${VCODE}" >> "${META}"
        fi
        echo "[publish] metadata bump ${PKG} → ${VNAME} (${VCODE})"
    else
        echo "[publish] WARN: could not bump metadata (pkg=${PKG} vname=${VNAME} vcode=${VCODE} meta=${META})" >&2
    fi
else
    echo "[publish] WARN: aapt/aapt2 not on PATH; skipping metadata auto-bump" >&2
fi

cd "${MOUNT}"
# Minimal config for fdroid update. Passwords MUST be embedded directly here
# — the `env:VARNAME` indirection that fdroidserver documents doesn't get
# resolved on this version of the toolchain. Backed up to config.yml.bak.
[ -f config.yml ] && cp -f config.yml config.yml.bak
cat > config.yml <<EOF
repo_url: https://f-droid.subfrost.io/repo
repo_name: SUBFROST
repo_description: Official F-Droid repository for SUBFROST.
archive_url: https://f-droid.subfrost.io/archive
archive_name: SUBFROST Archive
archive_older: 3
keystore: ${KEYSTORE}
repo_keyalias: ${FDROID_KEY_ALIAS:-${KEY_ALIAS}}
keystorepass: ${FDROID_KEYSTORE_PASSWORD}
keypass: ${FDROID_KEY_PASSWORD}
keydname: CN=Subfrost, O=Subfrost
apksigner: /usr/bin/apksigner
EOF

# Restore the original config on exit even if fdroid update blows up.
trap '[ -f config.yml.bak ] && mv -f config.yml.bak config.yml' EXIT

fdroid update --create-metadata
echo "[publish] $(basename "${APK}") -> gs://${BUCKET}/repo/"
