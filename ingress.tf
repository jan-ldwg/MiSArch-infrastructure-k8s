resource "kubernetes_ingress_v1" "misarch" {
  depends_on = [kubernetes_secret.misarch_ingress_tls]

  metadata {
    name        = local.ingress_name
    namespace   = local.namespace
    annotations = merge(local.base_misarch_annotations, local.misarch_ingress_annotations)
  }

  spec {
    tls {
      secret_name = "misarch-ingress-tls"
    }

    default_backend {
      service {
        name = local.misarch_frontend_service_name
        port {
          number = local.frontend_port
        }
      }
    }

    rule {
      http {
        path {
          backend {
            service {
              name = local.misarch_frontend_service_name
              port {
                number = local.frontend_port
              }
            }
          }
          path      = "/"
          path_type = "Prefix"
        }
        path {
          backend {
            service {
              name = local.misarch_experiment_executor_frontend_service_name
              port {
                number = 80
              }
            }
          }
          path      = "/frontend"
          path_type = "Prefix"
        }
        path {
          backend {
            service {
              name = local.misarch_experiment_executor_service_name
              port {
                number = 8888
              }
            }
          }
          path      = "/experiment"
          path_type = "Prefix"
        }
      }
    }
  }
}

resource "kubernetes_service" "misarch_frontend_service" {
  metadata {
    name      = local.misarch_frontend_service_name
    namespace = local.namespace
    labels    = merge(local.base_misarch_labels, local.misarch_frontend_specific_labels)
  }

  spec {
    selector = {
      app = local.misarch_frontend_service_name
    }

    port {
      protocol    = "TCP"
      port        = local.frontend_port
      target_port = local.frontend_port
    }

    type = "ClusterIP"
  }
}

