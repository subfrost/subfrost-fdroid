# Terraform configuration for Subfrost F-Droid infrastructure on GCP
# Usage:
#   cd terraform
#   terraform init
#   terraform apply

terraform {
  required_version = ">= 1.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Uncomment to use GCS backend for state
  # backend "gcs" {
  #   bucket = "subfrost-terraform-state"
  #   prefix = "fdroid"
  # }
}

# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "subfrost"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "domain" {
  description = "Custom domain for F-Droid repository"
  type        = string
  default     = "f-droid.subfrost.io"
}

# Provider
provider "google" {
  project = var.project_id
  region  = var.region
}

# Enable required APIs
resource "google_project_service" "apis" {
  for_each = toset([
    "run.googleapis.com",
    "cloudbuild.googleapis.com",
    "containerregistry.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# GCS bucket for repository backup/CDN
resource "google_storage_bucket" "fdroid_repo" {
  name          = "${var.project_id}-fdroid-repo"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  depends_on = [google_project_service.apis]
}

# Make bucket public
resource "google_storage_bucket_iam_member" "public_access" {
  bucket = google_storage_bucket.fdroid_repo.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Secret for keystore password
resource "google_secret_manager_secret" "keystore_pass" {
  secret_id = "fdroid-keystore-pass"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

resource "google_secret_manager_secret" "key_pass" {
  secret_id = "fdroid-key-pass"

  replication {
    auto {}
  }

  depends_on = [google_project_service.apis]
}

# Cloud Run service
resource "google_cloud_run_v2_service" "fdroid" {
  name     = "fdroid-repo"
  location = var.region

  template {
    containers {
      image = "gcr.io/${var.project_id}/fdroid-repo:latest"

      ports {
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
        }
      }

      env {
        name  = "FDROID_REPO_URL"
        value = "https://${var.domain}/fdroid/repo"
      }

      env {
        name = "FDROID_KEYSTORE_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.keystore_pass.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "FDROID_KEY_PASS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.key_pass.secret_id
            version = "latest"
          }
        }
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [google_project_service.apis]
}

# Allow unauthenticated access
resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.fdroid.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Domain mapping (requires verified domain)
resource "google_cloud_run_domain_mapping" "fdroid" {
  count    = var.domain != "" ? 1 : 0
  name     = var.domain
  location = var.region

  metadata {
    namespace = var.project_id
  }

  spec {
    route_name = google_cloud_run_v2_service.fdroid.name
  }

  depends_on = [google_cloud_run_v2_service.fdroid]
}

# Outputs
output "cloud_run_url" {
  description = "Cloud Run service URL"
  value       = google_cloud_run_v2_service.fdroid.uri
}

output "bucket_url" {
  description = "GCS bucket URL for static hosting"
  value       = "https://storage.googleapis.com/${google_storage_bucket.fdroid_repo.name}"
}

output "custom_domain" {
  description = "Custom domain for F-Droid repository"
  value       = var.domain
}
