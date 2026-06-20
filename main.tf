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

# credentials to interact with google cloud
data "google_client_config" "default" {}

# read the parameters from the infra stack
data "terraform_remote_state" "cluster" {
  backend = "gcs"
  config = {
    bucket = var.cluster_bucket_id
    prefix = var.cluster_bucket_prefix
  }

}

provider "google" {
  project = data.terraform_remote_state.cluster.outputs.project_id
  region  = data.terraform_remote_state.cluster.outputs.region
}

provider "kubernetes" {
  host = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode(
    data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
  )
  token = data.google_client_config.default.access_token

}

provider "helm" {
  kubernetes = {
    host = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
    cluster_ca_certificate = base64decode(
      data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
    )
    token = data.google_client_config.default.access_token
  }
}

provider "kubectl" {
  host = "https://${data.terraform_remote_state.cluster.outputs.cluster_endpoint}"
  cluster_ca_certificate = base64decode(
    data.terraform_remote_state.cluster.outputs.cluster_ca_certificate
  )
  token             = data.google_client_config.default.access_token
  apply_retry_count = 15 // There are some problems with (Dapr's) CRDs, so we need to retry requests for a bit
}

resource "kubernetes_namespace" "misarch" {
  metadata {
    name = var.KUBERNETES_NAMESPACE
  }
}

locals {
  namespace = kubernetes_namespace.misarch.metadata[0].name
}

