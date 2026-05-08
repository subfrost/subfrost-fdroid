resource "google_container_cluster" "fdroid" {
  provider = google-beta

  name     = var.cluster_name
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1
  deletion_protection      = false

  networking_mode = "VPC_NATIVE"
  network         = var.network
  subnetwork      = var.subnetwork

  ip_allocation_policy {}

  datapath_provider = "ADVANCED_DATAPATH"

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  addons_config {
    gcs_fuse_csi_driver_config {
      enabled = true
    }
    http_load_balancing {
      disabled = false
    }
  }

  release_channel {
    channel = "REGULAR"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"
}

resource "google_container_node_pool" "default" {
  provider = google-beta

  name     = "default"
  location = var.zone
  cluster  = google_container_cluster.fdroid.name

  node_count = var.node_count

  node_config {
    machine_type = var.node_machine_type
    disk_size_gb = 30
    disk_type    = "pd-balanced"
    image_type   = "COS_CONTAINERD"

    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}
