resource "kubernetes_service" "misarch_shipment" {
  metadata {
    name      = local.misarch_shipment_service_name
    namespace = local.namespace
    labels    = merge(local.base_misarch_labels, local.misarch_shipment_specific_labels)
  }

  spec {
    selector = { app = local.misarch_shipment_service_name }
    port {
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment" "misarch_shipment" {
  depends_on = [helm_release.misarch_shipment_db, helm_release.dapr]
  metadata {

    name      = local.misarch_shipment_service_name
    labels    = merge(local.base_misarch_labels, local.misarch_shipment_specific_labels)
    namespace = local.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.misarch_shipment_service_name
      }
    }

    template {
      metadata {
        labels      = merge(local.base_misarch_labels, local.misarch_shipment_specific_labels)
        annotations = merge(local.base_misarch_annotations, local.misarch_shipment_specific_annotations)
      }

      spec {

        container {
          image             = "ghcr.io/misarch/shipment:${var.MISARCH_SHIPMENT_VERSION}"
          image_pull_policy = "Always"

          name = local.misarch_shipment_service_name

          resources {
            limits = {
              cpu    = "500m"
              memory = "1200Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "400Mi"
            }
          }

          env_from {
            config_map_ref {
              name = local.misarch_base_env_vars_configmap
            }
          }
          env_from {
            config_map_ref {
              name = local.misarch_shipment_env_vars_configmap
            }
          }
          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 18
            timeout_seconds       = 5
          }
        }

        container {
          image             = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
          image_pull_policy = "Always"

          name = local.misarch_ecs_service_name

          resources {
            limits = {
              cpu    = "2000m"
              memory = "2Gi"
            }
            requests = {
              cpu    = "10m"
              memory = "50Mi"
            }
          }

          env_from {
            config_map_ref {
              name = local.misarch_shipment_ecs_env_vars_configmap
            }
          }
        }
      }
    }
  }
  lifecycle {
    ignore_changes = [spec[0].replicas]
  }
}

resource "kubernetes_horizontal_pod_autoscaler_v2" "shipment-hpa" {
  metadata {
    name      = "shipment-hpa"
    namespace = local.namespace
    labels = {
      managed-by = "terraform"
    }
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.misarch_shipment.metadata[0].name
    }
    min_replicas = 1
    max_replicas = 5
    metric {
      type = "Resource"
      resource {
        name = "cpu"
        target {
          type                = "Utilization"
          average_utilization = 70
        }
      }
    }
    behavior {
      scale_up {
        stabilization_window_seconds = 60
        select_policy = "Max"
        policy {
          type           = "Pods"
          value          = 1
          period_seconds = 60
        }
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
      scale_down {
        stabilization_window_seconds = 300
        select_policy = "Max"
        policy {
          type           = "Percent"
          value          = 50
          period_seconds = 60
        }
      }
    }
  }
}
