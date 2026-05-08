#!/bin/bash
# Create the subfrost-fdroid GCS bucket with CMEK, versioning, uniform IAM,
# and bind Workload Identity so the in-cluster KSA can read/write it.
# Idempotent: safe to re-run.
set -euo pipefail
source "$(dirname "$0")/common.sh"
source ~/.subfrost-fdroid-env

echo "[setup] project=${PROJECT_ID} bucket=${BUCKET}"

# --- KMS keyring + key for CMEK ---
if ! gcloud kms keyrings describe "${KMS_KEYRING}" --location="${REGION}" >/dev/null 2>&1; then
    gcloud kms keyrings create "${KMS_KEYRING}" --location="${REGION}"
fi
if ! gcloud kms keys describe "${KMS_KEY}" --keyring="${KMS_KEYRING}" --location="${REGION}" >/dev/null 2>&1; then
    gcloud kms keys create "${KMS_KEY}" \
        --keyring="${KMS_KEYRING}" --location="${REGION}" \
        --purpose=encryption --rotation-period=90d --next-rotation-time="+p90d"
fi
KMS_RESOURCE="projects/${PROJECT_ID}/locations/${REGION}/keyRings/${KMS_KEYRING}/cryptoKeys/${KMS_KEY}"

# --- Bucket (create without CMEK first so GCS SA gets initialized) ---
if ! gcloud storage buckets describe "gs://${BUCKET}" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://${BUCKET}" \
        --project="${PROJECT_ID}" \
        --location="${REGION}" \
        --uniform-bucket-level-access \
        --public-access-prevention
fi

# Grant GCS service agent permission to use the CMEK key
GCS_SA="$(gcloud storage service-agent --project="${PROJECT_ID}" 2>/dev/null | tr -d '\n' || true)"
if [ -n "${GCS_SA}" ]; then
    gcloud kms keys add-iam-policy-binding "${KMS_KEY}" \
        --keyring="${KMS_KEYRING}" --location="${REGION}" \
        --member="serviceAccount:${GCS_SA}" \
        --role="roles/cloudkms.cryptoKeyEncrypterDecrypter" --quiet >/dev/null
fi

# Apply CMEK + versioning
gcloud storage buckets update "gs://${BUCKET}" \
    --versioning \
    --uniform-bucket-level-access \
    --public-access-prevention \
    --default-encryption-key="${KMS_RESOURCE}"

# --- Service account for fdroid pod / local use ---
if ! gcloud iam service-accounts describe "${GSA}" >/dev/null 2>&1; then
    gcloud iam service-accounts create "${GSA%%@*}" \
        --display-name="F-Droid bucket access"
fi

# Grant bucket-level object admin to the GSA (no project-wide perms)
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
    --member="serviceAccount:${GSA}" \
    --role="roles/storage.objectAdmin" --quiet >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET}" \
    --member="serviceAccount:${GSA}" \
    --role="roles/storage.legacyBucketReader" --quiet >/dev/null

# Workload Identity binding: subfrost-fdroid/fdroid -> GSA
# Will fail if cluster (and therefore WI pool) doesn't exist yet — that's
# fine, just re-run this script after `terraform apply` brings the cluster up.
gcloud iam service-accounts add-iam-policy-binding "${GSA}" \
    --role="roles/iam.workloadIdentityUser" \
    --member="serviceAccount:${PROJECT_ID}.svc.id.goog[${KSA_NS}/${KSA_NAME}]" --quiet >/dev/null \
    || echo "[setup] WI binding skipped — cluster (WI pool) not yet provisioned. Re-run after terraform apply."

# Seed directory layout
tmp="$(mktemp -d)"
: > "${tmp}/.keep"
for prefix in repo archive metadata keys; do
    gcloud storage cp "${tmp}/.keep" "gs://${BUCKET}/${prefix}/.keep" --quiet >/dev/null || true
done
rm -rf "${tmp}"

echo "[setup] done. bucket gs://${BUCKET} ready (CMEK + versioning + UBLA)."
echo "        GSA: ${GSA}"
echo "        WI binding: ${PROJECT_ID}.svc.id.goog[${KSA_NS}/${KSA_NAME}]"
