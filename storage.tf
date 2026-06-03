// All persistent volumes use HDD (pd-standard) instead of the cluster default
// (standard-rwo -> pd-balanced, which is SSD-backed). GCP enforces a strict SSD
// quota (SSD_TOTAL_GB); the many small DB volumes in this stack would otherwise
// exhaust it. pd-standard counts against the regular (HDD) disk quota instead.
//
// Uses WaitForFirstConsumer so the disk is created in the same zone the pod is
// scheduled to (important on regional clusters).
resource "kubernetes_storage_class" "hdd" {
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

locals {
  storage_class_name = kubernetes_storage_class.hdd.metadata[0].name
}
