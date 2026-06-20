terraform {
  backend "gcs" {
    bucket = "misarch-terraform-state"
    prefix = "misarch/cluster"
  }
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
