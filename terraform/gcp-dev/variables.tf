variable "project_id" {
  type        = string
  description = "GCP project ID (gcloud config get-value project)."
}

variable "region" {
  type        = string
  description = "GCP region for the GKE cluster and regional resources."
  default     = "europe-west3"
}

variable "cluster_name" {
  type        = string
  description = "Name of the GKE cluster."
  default     = "misarch-cluster"
}

variable "cluster_deletion_protection" {
  type        = bool
  description = "When true, the GKE cluster cannot be destroyed via Terraform. Disabled for dev."
  default     = false
}

variable "network_name" {
  type    = string
  default = "misarch-dev-vpc"
}

variable "subnet_name" {
  type    = string
  default = "misarch-dev-subnet"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.0.0/20"
}

variable "pods_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "services_cidr" {
  type    = string
  default = "10.2.0.0/20"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-4"
}

variable "node_disk_size_gb" {
  type    = number
  default = 30
}

variable "node_disk_type" {
  type    = string
  default = "pd-standard"
}

variable "node_min_count" {
  type    = number
  default = 2
}

variable "node_max_count" {
  type    = number
  default = 6
}

variable "state_bucket_name" {
  type        = string
  description = "GCS bucket name for Terraform remote state."
  default     = ""
}

variable "ingress_nginx_chart_version" {
  type    = string
  default = "4.11.8"
}

locals {
  state_bucket_name = var.state_bucket_name != "" ? var.state_bucket_name : "${var.project_id}-terraform-state"
  labels = {
    environment = "dev"
    managed_by  = "terraform"
    project     = "misarch"
  }
}
