#!/bin/bash
set -euo pipefail
source "$(dirname "$0")/common.sh"
mountpoint -q "${MOUNT}" || { echo "[unmount] not mounted"; exit 0; }
fusermount -u "${MOUNT}" || sudo umount "${MOUNT}"
echo "[unmount] ${MOUNT}"
