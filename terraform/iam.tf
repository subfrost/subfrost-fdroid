data "google_service_account" "fdroid_bucket" {
  account_id = var.gsa_account_id
  project    = var.project_id
}

data "google_storage_bucket" "fdroid" {
  name = var.bucket_name
}

resource "google_storage_bucket_iam_member" "gsa_object_admin" {
  bucket = data.google_storage_bucket.fdroid.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${data.google_service_account.fdroid_bucket.email}"
}

resource "google_storage_bucket_iam_member" "gsa_legacy_reader" {
  bucket = data.google_storage_bucket.fdroid.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${data.google_service_account.fdroid_bucket.email}"
}

resource "google_service_account_iam_member" "ksa_workload_identity" {
  service_account_id = data.google_service_account.fdroid_bucket.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[${var.ksa_namespace}/${var.ksa_name}]"

  depends_on = [google_container_cluster.fdroid]
}
