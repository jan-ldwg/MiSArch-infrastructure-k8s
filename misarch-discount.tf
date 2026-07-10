resource "kubernetes_deployment" "misarch_discount" {
  depends_on = [helm_release.misarch_discount_db, terraform_data.dapr]
  metadata {

    name      = local.misarch_discount_service_name
    labels    = merge(local.base_misarch_labels, local.misarch_discount_specific_labels)
    namespace = local.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.misarch_discount_service_name
      }
    }

    template {
      metadata {
        labels      = merge(local.base_misarch_labels, local.misarch_discount_specific_labels)
        annotations = merge(local.base_misarch_annotations, local.misarch_discount_specific_annotations)
      }

      spec {

        container {
          image             = "${var.MISARCH_DISCOUNT_VERSION}"
          image_pull_policy = "Always"

          name = local.misarch_discount_service_name

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
              name = local.misarch_discount_env_vars_configmap
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
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 5
            failure_threshold     = 3
            timeout_seconds       = 3
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 10
            failure_threshold     = 3
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
              name = local.misarch_discount_ecs_env_vars_configmap
            }
          }
        }
      }
    }
  }
}
