output "cluster_name" {
  value = google_container_cluster.fdroid.name
}

output "cluster_endpoint" {
  value     = google_container_cluster.fdroid.endpoint
  sensitive = true
}

output "cluster_location" {
  value = google_container_cluster.fdroid.location
}

output "gsa_email" {
  value = data.google_service_account.fdroid_bucket.email
}

output "bucket_name" {
  value = data.google_storage_bucket.fdroid.name
}
