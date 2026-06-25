variable "service_name" {
  type = string
}

variable "image" {
  type = string
}

variable "namespace" {
  type = string
}

variable "replicas" {
  type    = number
  default = 1
}

variable "cpu_limit" {
  type    = string
  default = "500m"
}

variable "memory_limit" {
  type    = string
  default = "1200Mi"
}

variable "cpu_request" {
  type    = string
  default = "100m"
}

variable "memory_request" {
  type    = string
  default = "400Mi"
}

variable "base_configmap" {
  type = string
}

variable "service_configmap" {
  type = string
}

variable "ecs_configmap" {
  type = string
}

variable "ecs_image" {
  type = string
}

variable "ecs_cpu_limit" {
  type    = string
  default = "2000m"
}

variable "ecs_memory_limit" {
  type    = string
  default = "2Gi"
}

variable "ecs_cpu_request" {
  type    = string
  default = "10m"
}

variable "ecs_memory_request" {
  type    = string
  default = "50Mi"
}

variable "has_ecs_sidecar" {
  type    = bool
  default = true
}

variable "base_labels" {
  type = map(string)
}

variable "specific_labels" {
  type = map(string)
}

variable "base_annotations" {
  type = map(string)
}

variable "specific_annotations" {
  type = map(string)
}

variable "create_service" {
  type    = bool
  default = false
}

variable "service_port" {
  type    = number
  default = 8080
}

variable "service_target_port" {
  type    = number
  default = 8080
}

variable "has_startup_probe" {
  type    = bool
  default = true
}

variable "has_liveness_probe" {
  type    = bool
  default = true
}

variable "has_readiness_probe" {
  type    = bool
  default = true
}

variable "probe_type" {
  type    = string
  default = "http_get"

  validation {
    condition     = contains(["http_get", "tcp_socket"], var.probe_type)
    error_message = "probe_type must be \"http_get\" or \"tcp_socket\"."
  }
}

variable "probe_port" {
  type    = number
  default = 8080
}

variable "probe_path" {
  type    = string
  default = "/health"
}

variable "liveness_probe_path" {
  type    = string
  default = null
}

variable "liveness_initial_delay_seconds" {
  type    = number
  default = 10
}

variable "liveness_period_seconds" {
  type    = number
  default = 10
}

variable "readiness_initial_delay_seconds" {
  type    = number
  default = 10
}

variable "readiness_period_seconds" {
  type    = number
  default = 5
}

variable "probe_failure_threshold" {
  type    = number
  default = 3
}

variable "probe_success_threshold" {
  type    = number
  default = 1
}

variable "probe_timeout_seconds" {
  type    = number
  default = 5
}

variable "startup_period_seconds" {
  type    = number
  default = 10
}

variable "startup_failure_threshold" {
  type    = number
  default = 15
}
