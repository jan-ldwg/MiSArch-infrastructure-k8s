variable "project_id" {
  description = "GCP project ID - the unique identifier of your project"
  type        = string
  # No default: must be set explicitly, otherwise Terraform will prompt.
}

variable "bucket_id" {
  description = "The bucket to save the terraform state to"
  type        = string
}

variable "bucket_prefix" {
  description = "The prefix used for the terraform state in the bucket"
  type        = string
}

variable "region" {
  description = "GCP region for the provider (used for region-scoped APIs)"
  type        = string
  default     = "europe-west3"
}

variable "cluster_name" {
  description = "Name of the GCP cluster"
  type        = string
  default     = "misarch-cluster"
}

variable "zone" {
  description = "GCP zone for the cluster"
  type        = string
  default     = "europe-west3-a"
}

variable "machine_type" {
  description = "VM type for the cluster"
  type        = string
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  description = "Boot disk size per node in GB"
  type        = number
  default     = 30
}
