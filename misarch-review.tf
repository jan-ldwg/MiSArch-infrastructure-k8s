resource "kubernetes_deployment" "misarch_review" {
  depends_on = [helm_release.misarch_review_db, terraform_data.dapr]
  metadata {

    name      = local.misarch_review_service_name
    labels    = merge(local.base_misarch_labels, local.misarch_review_specific_labels)
    namespace = local.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.misarch_review_service_name
      }
    }

    template {
      metadata {
        labels      = merge(local.base_misarch_labels, local.misarch_review_specific_labels)
        annotations = merge(local.base_misarch_annotations, local.misarch_review_specific_annotations)
      }

      spec {

        container {
          image             = "ghcr.io/misarch/review:${var.MISARCH_REVIEW_VERSION}"
          image_pull_policy = "Always"

          name = local.misarch_review_service_name


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
              name = local.misarch_review_env_vars_configmap
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
              name = local.misarch_review_ecs_env_vars_configmap
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

resource "kubernetes_horizontal_pod_autoscaler_v2" "review-hpa" {
  metadata {
    name      = "review-hpa"
    namespace = local.namespace
    labels = {
      managed-by = "terraform"
    }
  }
  spec {
    scale_target_ref {
      api_version = "apps/v1"
      kind        = "Deployment"
      name        = kubernetes_deployment.misarch_review.metadata[0].name
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
  }
}
