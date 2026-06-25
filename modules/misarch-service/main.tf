resource "kubernetes_service" "this" {
  count = var.create_service ? 1 : 0

  metadata {
    name      = var.service_name
    namespace = var.namespace
    labels    = merge(var.base_labels, var.specific_labels)
  }

  spec {
    selector = { app = var.service_name }
    port {
      name        = "http"
      port        = var.service_port
      target_port = var.service_target_port
    }
  }
}

resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.service_name
    labels    = merge(var.base_labels, var.specific_labels)
    namespace = var.namespace
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { app = var.service_name }
    }

    template {
      metadata {
        labels      = merge(var.base_labels, var.specific_labels)
        annotations = merge(var.base_annotations, var.specific_annotations)
      }

      spec {
        container {
          name              = var.service_name
          image             = var.image
          image_pull_policy = "Always"

          resources {
            limits   = { cpu = var.cpu_limit, memory = var.memory_limit }
            requests = { cpu = var.cpu_request, memory = var.memory_request }
          }

          env_from {
            config_map_ref { name = var.base_configmap }
          }
          env_from {
            config_map_ref { name = var.service_configmap }
          }

          dynamic "startup_probe" {
            for_each = var.has_startup_probe ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.probe_type == "http_get" ? [1] : []
                content {
                  path = var.probe_path
                  port = var.probe_port
                }
              }
              dynamic "tcp_socket" {
                for_each = var.probe_type == "tcp_socket" ? [1] : []
                content {
                  port = var.probe_port
                }
              }
              initial_delay_seconds = 0
              period_seconds        = var.startup_period_seconds
              failure_threshold     = var.startup_failure_threshold
              success_threshold     = 1
              timeout_seconds       = var.probe_timeout_seconds
            }
          }

          dynamic "liveness_probe" {
            for_each = var.has_liveness_probe ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.probe_type == "http_get" ? [1] : []
                content {
                  path = coalesce(var.liveness_probe_path, var.probe_path)
                  port = var.probe_port
                }
              }
              dynamic "tcp_socket" {
                for_each = var.probe_type == "tcp_socket" ? [1] : []
                content {
                  port = var.probe_port
                }
              }
              initial_delay_seconds = var.liveness_initial_delay_seconds
              period_seconds        = var.liveness_period_seconds
              failure_threshold     = var.probe_failure_threshold
              success_threshold     = var.probe_success_threshold
              timeout_seconds       = var.probe_timeout_seconds
            }
          }

          dynamic "readiness_probe" {
            for_each = var.has_readiness_probe ? [1] : []
            content {
              dynamic "http_get" {
                for_each = var.probe_type == "http_get" ? [1] : []
                content {
                  path = var.probe_path
                  port = var.probe_port
                }
              }
              dynamic "tcp_socket" {
                for_each = var.probe_type == "tcp_socket" ? [1] : []
                content {
                  port = var.probe_port
                }
              }
              initial_delay_seconds = var.readiness_initial_delay_seconds
              period_seconds        = var.readiness_period_seconds
              failure_threshold     = var.probe_failure_threshold
              success_threshold     = var.probe_success_threshold
              timeout_seconds       = var.probe_timeout_seconds
            }
          }
        }

        dynamic "container" {
          for_each = var.has_ecs_sidecar ? [1] : []
          content {
            name              = "misarch-ecs"
            image             = var.ecs_image
            image_pull_policy = "Always"

            resources {
              limits   = { cpu = var.ecs_cpu_limit, memory = var.ecs_memory_limit }
              requests = { cpu = var.ecs_cpu_request, memory = var.ecs_memory_request }
            }

            env_from {
              config_map_ref { name = var.ecs_configmap }
            }
          }
        }
      }
    }
  }
}

output "deployment" {
  value = kubernetes_deployment.this
}

output "service" {
  value = var.create_service ? kubernetes_service.this[0] : null
}
