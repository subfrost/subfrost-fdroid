#!/bin/bash
# gcsfuse-mount the subfrost-fdroid bucket at /mnt/sfdroid.
# Uses the service-account key referenced by ~/.subfrost-fdroid-env.
set -euo pipefail
source "$(dirname "$0")/common.sh"
source ~/.subfrost-fdroid-env

command -v gcsfuse >/dev/null 2>&1 || die "gcsfuse not installed. See https://github.com/GoogleCloudPlatform/gcsfuse"

if mountpoint -q "${MOUNT}"; then
    echo "[mount] already mounted at ${MOUNT}"
    exit 0
fi

sudo mkdir -p "${MOUNT}"
sudo chown "$(id -u):$(id -g)" "${MOUNT}"

gcsfuse \
    --implicit-dirs \
    --file-mode=640 \
    --dir-mode=750 \
    --billing-project="${PROJECT_ID}" \
    --key-file="${SERVICE_ACCOUNT_KEY}" \
    "${BUCKET}" "${MOUNT}"

echo "[mount] ${BUCKET} -> ${MOUNT}"
ls -la "${MOUNT}"
