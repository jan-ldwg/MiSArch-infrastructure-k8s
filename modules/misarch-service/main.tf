resource "kubernetes_deployment" "this" {
  metadata {
    name      = var.service.name
    labels    = var.metadata.labels
    namespace = var.service.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = { app = var.service.name }
    }

    template {
      metadata {
        labels      = var.metadata.labels
        annotations = var.metadata.annotations
      }

      spec {
        container {
          name              = var.service.name
          image             = var.service.image
          image_pull_policy = "Always"

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
            config_map_ref { name = var.config.base }
          }
          env_from {
            config_map_ref { name = var.config.env }
          }

          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 0
            period_seconds        = 10
            failure_threshold     = 15
            success_threshold     = 1
            timeout_seconds       = 5
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            failure_threshold     = 3
            success_threshold     = 1
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
            success_threshold     = 1
            timeout_seconds       = 5
          }
        }

        container {
          name              = "misarch-ecs"
          image             = var.ecs_image
          image_pull_policy = "Always"

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
            config_map_ref { name = var.config.ecs }
          }
        }
      }
    }
  }
}
