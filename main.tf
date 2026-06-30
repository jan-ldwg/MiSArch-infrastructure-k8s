terraform {
  required_providers {
    kubectl = {
      # alekc/kubectl is the maintained fork of gavinbunney/kubectl. The original is unmaintained now.
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

# ── GCP-only: remote state and authentication ──────────────────────────
# These data sources are only read when deployment_target = "gcp".
# On local minikube, their count is zero and they are skipped entirely.


# credentials to interact with google cloud
data "google_client_config" "default" {
  count = var.deployment_target == "gcp" ? 1 : 0
}

# read the parameters from the infra stack
data "terraform_remote_state" "cluster" {
  count   = var.deployment_target == "gcp" ? 1 : 0
  backend = "gcs"
  config = {
    bucket = var.cluster_bucket_id
    prefix = var.cluster_bucket_prefix
  }

}

provider "google" {
  project = try(data.terraform_remote_state.cluster[0].outputs.project_id, null)
  region  = try(data.terraform_remote_state.cluster[0].outputs.region, null)
}

# ── Kubernetes providers: works on both GCP and local ──────────────────
# On GCP:  uses the cluster endpoint, CA certificate from remote state and
#          the access token from google_client_config.
# On local: uses kubeconfig; "minikube" context is used.
provider "kubernetes" {
  host                   = var.deployment_target == "gcp" ? "https://${data.terraform_remote_state.cluster[0].outputs.cluster_endpoint}" : null
  cluster_ca_certificate = var.deployment_target == "gcp" ? base64decode(data.terraform_remote_state.cluster[0].outputs.cluster_ca_certificate) : null
  token                  = var.deployment_target == "gcp" ? data.google_client_config.default[0].access_token : null
  config_path            = var.deployment_target == "local" ? var.KUBERNETES_CONFIG_PATH : null
  config_context         = var.deployment_target == "local" ? "minikube" : null
}


provider "helm" {
  kubernetes = {
    host                   = var.deployment_target == "gcp" ? "https://${data.terraform_remote_state.cluster[0].outputs.cluster_endpoint}" : null
    cluster_ca_certificate = var.deployment_target == "gcp" ? base64decode(data.terraform_remote_state.cluster[0].outputs.cluster_ca_certificate) : null
    token                  = var.deployment_target == "gcp" ? data.google_client_config.default[0].access_token : null
    config_path            = var.deployment_target == "local" ? var.KUBERNETES_CONFIG_PATH : null
    config_context         = var.deployment_target == "local" ? "minikube" : null
  }
}

provider "kubectl" {
  host                   = var.deployment_target == "gcp" ? "https://${data.terraform_remote_state.cluster[0].outputs.cluster_endpoint}" : null
  cluster_ca_certificate = var.deployment_target == "gcp" ? base64decode(data.terraform_remote_state.cluster[0].outputs.cluster_ca_certificate) : null
  token                  = var.deployment_target == "gcp" ? data.google_client_config.default[0].access_token : null
  config_path            = var.deployment_target == "local" ? var.KUBERNETES_CONFIG_PATH : null
  config_context         = var.deployment_target == "local" ? "minikube" : null
  apply_retry_count      = 15 // There are some problems with (Dapr's) CRDs, so we need to retry requests for a bit
}

resource "kubernetes_namespace" "misarch" {
  metadata {
    name = var.KUBERNETES_NAMESPACE
  }
}

locals {
  namespace = kubernetes_namespace.misarch.metadata[0].name
}

