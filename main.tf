terraform {
  required_providers {
    kubectl = {
      # alekc/kubectl is the maintained fork of gavinbunney/kubectl. The original is unmaintained now.
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
  }
}

provider "kubernetes" {
  config_path = var.KUBERNETES_CONFIG_PATH
}

provider "helm" {
  kubernetes = {
    config_path = var.KUBERNETES_CONFIG_PATH
  }
}

provider "kubectl" {
  config_path       = var.KUBERNETES_CONFIG_PATH
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

