# subfrost-fdroid — Resume Point

## What this is

Standalone F-Droid repo for `f-droid.subfrost.io`, modeled directly on
`~/pyrosec-fdroid` (which serves `f-droid.pyrosec.is` for project-ghost).
Same architecture: a single GCS bucket (`subfrost-fdroid`) holds the entire
repo (APKs, metadata, signing keystore). The bucket is mounted via gcsfuse
locally at `/mnt/sfdroid` and via the GCS Fuse CSI driver at `/fdroid` in
the cluster pod. Bucket is locked down with CMEK, object versioning,
uniform bucket-level access, and public-access-prevention.

## Current state

### Done
- Repo scaffolded at `~/subfrost-fdroid` (this directory)
- `~/.subfrost-fdroid-env` — env file (separate from `~/.ioenv` and `~/.fdroidenv`)
- `gs://subfrost-fdroid` bucket created with CMEK, versioning, UBLA, public-access-prevention
- GSA `fdroid-bucket@night-wolves-jogging.iam.gserviceaccount.com` created with bucket IAM
- Bucket mounted locally at `/mnt/sfdroid`
- `services/fdroid/` — Dockerfile, nginx.conf, config.yml, entrypoint.sh
- `k8s/base/` — Namespace + Deployment (GCS Fuse CSI) + ServiceAccount (WI) + Service
- `k8s/flux/` — GitRepository + Kustomization for Flux
- `cloudbuild.yaml` — build, push to `subfrost-docker` Artifact Registry, rollout restart
- `scripts/` — common, setup-bucket, mount/unmount, generate-key, resign-apk, publish-apk
- `terraform/` — cluster.tf + iam.tf + variables.tf + versions.tf

### NOT done yet
1. **Provision `subfrost-fdroid-cluster`** via terraform
   ```
   cd ~/subfrost-fdroid/terraform
   terraform init
   terraform apply
   ```
2. **Re-run `scripts/setup-bucket.sh`** after cluster exists to create the
   Workload Identity binding (the WI pool only exists once the cluster does)
3. **Generate signing keystore** on the bucket
   ```
   source ~/.subfrost-fdroid-env && mount_sfdroid
   ~/subfrost-fdroid/scripts/generate-key.sh
   ```
4. **Push GitHub repo** — `subfrost/subfrost-fdroid` (private)
5. **Install Flux on subfrost-fdroid-cluster**
6. **First Cloud Build** — `source ~/.subfrost-fdroid-env && deploy_sfdroid initial`
7. **Sign + publish APKs** that need to be in the repo (currently in `/tmp/subfrost-fdroid-backup/apks/`)
8. **DNS** — change `f-droid.subfrost.io` CNAME from `subfrost.github.io`
   to the new cluster's LoadBalancer IP
9. **TLS** — cert-manager or GKE managed cert for `f-droid.subfrost.io`
10. **Tear down** old GitHub Pages workflow (`.github/workflows/`) once GCP version is verified

## Architecture

```
User (local)                                 GKE (subfrost-fdroid-cluster)
─────────────                                ─────────────────────────────
~/.subfrost-fdroid-env                       Namespace: subfrost-fdroid
mount_sfdroid                                Deployment: fdroid
  └─ gcsfuse gs://subfrost-fdroid              Pod spec:
       └─ /mnt/sfdroid                          serviceAccount: fdroid (WI)
            ├── repo/        ← APKs + index    volumes:
            ├── archive/                         - csi: gcsfuse → /fdroid
            ├── metadata/                      nginx serves:
            └── keys/                            / → landing page
                 ├── fdroid.keystore             /repo/ → /fdroid/repo/
                 └── passwords.env               /keys/ → 404

DNS: f-droid.subfrost.io → subfrost-fdroid-cluster ingress (TBD)
Flux watches subfrost/subfrost-fdroid (master) → applies k8s/base/
Cloud Build → subfrost-docker AR → rollout restart
```

## Key identifiers

| Thing | Value |
|-------|-------|
| GCP project | `night-wolves-jogging` |
| GCS bucket | `subfrost-fdroid` |
| CMEK | `us-central1/fdroid/bucket-cmek` |
| GSA | `fdroid-bucket@night-wolves-jogging.iam.gserviceaccount.com` |
| KSA | `subfrost-fdroid/fdroid` (Workload Identity → GSA) |
| Image | `us-central1-docker.pkg.dev/night-wolves-jogging/subfrost-docker/fdroid` |
| Cluster | `subfrost-fdroid-cluster` / `us-central1-a` |
| Env file | `~/.subfrost-fdroid-env` |
| GitHub | `subfrost/subfrost-fdroid` (TBD push) |
| Flux source | `GitRepository/subfrost-fdroid` in `flux-system` |
| Mount | `/mnt/sfdroid` |

## Quick start (next session)

```bash
# 1. Source env
source ~/.subfrost-fdroid-env

# 2. Provision cluster
cd ~/subfrost-fdroid/terraform
terraform init
terraform apply

# 3. After cluster exists, finalize WI binding + generate keystore
~/subfrost-fdroid/scripts/setup-bucket.sh
mount_sfdroid
~/subfrost-fdroid/scripts/generate-key.sh

# 4. Sign + publish backed-up APKs
for apk in /tmp/subfrost-fdroid-backup/apks/*.apk; do
  ~/subfrost-fdroid/scripts/resign-apk.sh "$apk"
  ~/subfrost-fdroid/scripts/publish-apk.sh "${apk%.apk}-signed.apk"
done

# 5. Install Flux on the new cluster
flux install
kubectl create secret generic flux-system -n flux-system \
  --from-literal=username=git --from-literal=password="${GITHUB_TOKEN}"
kubectl apply -f ~/subfrost-fdroid/k8s/flux/gitrepository.yaml

# 6. First image build + deploy
deploy_sfdroid initial

# 7. Cut DNS over from subfrost.github.io to the new ingress IP
```
