variable "project_id" {
  type        = string
  description = "GCP project that owns the cluster, bucket, GSA."
  default     = "night-wolves-jogging"
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "zone" {
  type    = string
  default = "us-central1-a"
}

variable "cluster_name" {
  type    = string
  default = "subfrost-fdroid-cluster"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

variable "node_count" {
  type        = number
  default     = 1
  description = "Single-node fdroid serves a static repo from gcsfuse. Bump if QPS demands it."
}

variable "bucket_name" {
  type        = string
  default     = "subfrost-fdroid"
  description = "Existing GCS bucket holding the F-Droid repo, keys, and metadata."
}

variable "gsa_account_id" {
  type        = string
  default     = "fdroid-bucket"
  description = "Existing GSA short id (full email is <id>@<project>.iam.gserviceaccount.com)."
}

variable "ksa_namespace" {
  type    = string
  default = "subfrost-fdroid"
}

variable "ksa_name" {
  type    = string
  default = "fdroid"
}

variable "network" {
  type        = string
  default     = "default"
  description = "VPC network for the cluster."
}

variable "subnetwork" {
  type        = string
  default     = "default"
  description = "VPC subnetwork for the cluster."
}
