resource "google_container_cluster" "misarch" {
  name     = var.cluster_name
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  # Required: enables VPC-native networking with default IP ranges.
  ip_allocation_policy {}

  # Required so 'terraform destroy' can remove the cluster without
  # a separate console click. The provider default is true.
  deletion_protection = false
}

resource "google_container_node_pool" "misarch_nodes" {
  name               = "default-pool"
  cluster            = google_container_cluster.misarch.name
  location           = var.zone
  initial_node_count = 3

  autoscaling {
    min_node_count = 3
    max_node_count = 6
  }

  node_config {
    machine_type = var.machine_type
    disk_size_gb = var.disk_size_gb
    disk_type    = "pd-standard"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]
  }
}
