resource "kubernetes_deployment" "jaeger" {
  depends_on = [kubernetes_namespace.misarch]
  metadata {
    name      = local.jaeger_service_name
    namespace = local.namespace
    labels    = local.jaeger_labels
  }
  spec {
    replicas = 1

    selector {
      match_labels = { app = local.jaeger_service_name }
    }

    template {
      metadata {
        labels = local.jaeger_labels
      }
      spec {
        container {
          name  = local.jaeger_service_name
          image = "jaegertracing/all-in-one:${var.JAEGER_VERSION}"
          args  = ["--memory.max-traces=10000"]

          port {
            container_port = 14250
            name           = "grpc"
          }
          port {
            container_port = 14269
            name           = "health"
          }
          port {
            container_port = 16686
            name           = "ui"
          }

          resources {
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 14269
            }
            initial_delay_seconds = 5
            period_seconds        = 5
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 14269
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service" "jaeger" {
  depends_on = [kubernetes_deployment.jaeger]
  metadata {
    name      = local.jaeger_service_name
    namespace = local.namespace
  }
  spec {
    selector = { app = local.jaeger_service_name }
    port {
      name        = "grpc"
      port        = 14250
      target_port = 14250
    }
    port {
      name        = "ui"
      port        = 16686
      target_port = 16686
    }
  }
}
