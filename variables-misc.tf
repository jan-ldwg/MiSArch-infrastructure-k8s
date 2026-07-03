variable "KUBERNETES_CONFIG_PATH" {
  sensitive = true
  type      = string
  default   = "~/.kube/config"
}

variable "KUBERNETES_NAMESPACE" {
  type    = string
  default = "misarch"
}

variable "MISARCH_DB_USER" {
  type    = string
  default = "misarch"
}

variable "MISARCH_DB_DATABASE" {
  type    = string
  default = "misarch"
}

variable "KEYCLOAK_DB_USER" {
  type    = string
  default = "postgres"
}

variable "KEYCLOAK_DB_DATABASE" {
  type    = string
  default = "keycloak"
}

variable "INFLUXDB_USER" {
  type    = string
  default = "admin"
}

variable "INFLUXDB_PASSWORD" {
  type    = string
  default = "admin123"
}

variable "INFLUXDB_ORG" {
  type    = string
  default = "misarch"
}

variable "INFLUXDB_BUCKET" {
  type    = string
  default = "gatling"
}

variable "MISARCH_SIMULATION_PAYMENTS_PER_MINUTE" {
  type    = number
  default = 10000000
}

variable "MISARCH_SIMULATION_SHIPMENTS_PER_MINUTE" {
  type    = number
  default = 10000000
}

variable "MISARCH_SIMULATION_PROCESSING_TIME_SECONDS" {
  type    = number
  default = 5
}

variable "MONGODB_RESOURCE_PRESET" {
  type        = string
  description = "Sets a resource limit for MongoDBs. Values are as described in https://github.com/bitnami/charts/blob/4b89068b8267e4b115c676064d092a05813953cc/bitnami/common/templates/_resources.tpl#L16-L43. Default is 'micro', Helm Chart default was 'small'."
  default     = "micro"
}

variable "RABBITMQ_ERLANG_COOKIE" {
  type    = string
  default = "RABBITMQ_MISARCH_ERLANG_COOKIE"
}

variable "cluster_bucket_id" {
  type        = string
  description = "Bucket with the credentials to the cluster (GCP only)"
  default     = ""
}

variable "cluster_bucket_prefix" {
  type        = string
  description = "Prefix for the credentials in the bucket (GCP only)"
  default     = ""
}

variable "deployment_target" {
  type        = string
  description = "Deployment target: 'gcp' or 'local'"
  default     = "gcp"

  validation {
    condition     = contains(["gcp", "local"], var.deployment_target)
    error_message = "deployment_target must be 'gcp' or 'local'."
  }
}

variable "storage_class_name" {
  type        = string
  description = "Kubernetes StorageClass name for persistent volumes"
  default     = "hdd"
}

variable "storage_class_name_ssd" {
  type        = string
  description = "Kubernetes StorageClass name for persistent volumes with high performance"
  default     = "ssd"
}

variable "create_gcp_storage_class" {
  type        = bool
  description = "Create the GCP-specific 'hdd' StorageClass (pd-standard)"
  default     = true
}

variable "dapr_log_level" {
  type        = string
  description = "Dapr sidecar log level (debug, info, warn, error)"
  default     = "debug"
}

variable "otel_log_level" {
  type        = string
  description = "OpenTelemetry log level"
  default     = "info"
}

variable "otel_disabled" {
  type        = bool
  description = "Disable OpenTelemetry export (local development)"
  default     = false
}

variable "otel_collector_mode" {
  type        = string
  description = "OTEL collector deployment mode: 'gcp' (full Prometheus stack) or 'local' (debug exporter, no cluster RBAC)"
  default     = "gcp"

  validation {
    condition     = contains(["gcp", "local"], var.otel_collector_mode)
    error_message = "otel_collector_mode must be 'gcp' or 'local'."
  }
}

locals {
  dapr_general_config_name = "dapr-config"
}
