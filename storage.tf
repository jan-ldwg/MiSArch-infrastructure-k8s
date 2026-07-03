// All persistent volumes use HDD (pd-standard) instead of the cluster default
// (standard-rwo -> pd-balanced, which is SSD-backed). GCP enforces a strict SSD
// quota (SSD_TOTAL_GB); the many small DB volumes in this stack would otherwise
// exhaust it. pd-standard counts against the regular (HDD) disk quota instead.
//
// Uses WaitForFirstConsumer so the disk is created in the same zone the pod is
// scheduled to (important on regional clusters).
//
// Conditionally created: set `create_gcp_storage_class = true` for GKE deployments,
// otherwise the default StorageClass from `var.storage_class_name` is used (for
// minikube/kind/Docker Desktop local development).
resource "kubernetes_storage_class" "hdd" {
  count = var.create_gcp_storage_class ? 1 : 0
  metadata {
    name = "hdd"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "pd-standard"
  }
}

resource "kubernetes_storage_class" "ssd" {
  count = var.create_gcp_storage_class ? 1 : 0
  metadata {
    name = "ssd"
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type = "pd-balanced"
  }
}

locals {
  storage_class_name     = var.storage_class_name
  storage_class_name_ssd = var.storage_class_name_ssd
}
