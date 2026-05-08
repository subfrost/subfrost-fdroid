#!/bin/bash
# Shared config for subfrost-fdroid scripts. Source this from other scripts.

export BUCKET="${BUCKET:-subfrost-fdroid}"
export MOUNT="${MOUNT:-/mnt/sfdroid}"
export PROJECT_ID="${PROJECT_ID:-night-wolves-jogging}"
export REGION="${REGION:-us-central1}"
export GSA="${GSA:-fdroid-bucket@${PROJECT_ID}.iam.gserviceaccount.com}"
export KSA_NS="${KSA_NS:-subfrost-fdroid}"
export KSA_NAME="${KSA_NAME:-fdroid}"
export KEY_ALIAS="${KEY_ALIAS:-fdroid}"
export KMS_KEYRING="${KMS_KEYRING:-fdroid}"
export KMS_KEY="${KMS_KEY:-bucket-cmek}"

die() { echo "error: $*" >&2; exit 1; }
