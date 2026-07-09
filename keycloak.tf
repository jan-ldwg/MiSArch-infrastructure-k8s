resource "kubernetes_service" "keycloak" {
  metadata {
    name      = local.keycloak_service_name
    namespace = local.namespace
    labels = merge(local.base_misarch_labels, local.misarch_keycloak_specific_labels)
  }

  spec {
    selector = {
      app = local.keycloak_service_name
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment" "keycloak" {
  depends_on = [helm_release.misarch_keycloak_db, terraform_data.dapr]
  metadata {

    name      = local.keycloak_service_name
    labels    = merge(local.base_misarch_labels, local.misarch_keycloak_specific_labels)
    namespace = local.namespace
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = local.keycloak_service_name
      }
    }

    template {
      metadata {
        labels      = merge(local.base_misarch_labels, local.misarch_keycloak_specific_labels)
        annotations = merge(local.base_misarch_annotations, local.keycloak_specific_annotations)
      }

      spec {

        container {
          image             = var.MISARCH_KEYCLOAK_VERSION
          image_pull_policy = "Always"

          name = local.keycloak_service_name

          resources {
            limits = {
              cpu    = "2000m"
              memory = "2400Mi"
            }
            requests = {
              cpu    = "300m"
              memory = "500Mi"
            }
          }

          startup_probe {
            http_get {
              path = "/keycloak/health/started"
              port = 8080
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 60
          }

          readiness_probe {
            http_get {
              path = "/keycloak/health/ready"
              port = 8080
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 3
          }

          liveness_probe {
            http_get {
              path = "/keycloak/health/live"
              port = 8080
            }
            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 3
          }

          env_from {
            config_map_ref {
              name = local.misarch_base_env_vars_configmap
            }
          }
          env_from {
            config_map_ref {
              name = local.keycloak_env_vars_configmap
            }
          }

          # Bootstrap admin credentials. Keycloak only creates the user on a
          # fresh DB; if you change these later, run `kc.sh bootstrap-admin
          # user` inside the pod or wipe the keycloak-db PVC.
          env {
            name = "KC_BOOTSTRAP_ADMIN_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminUser"
              }
            }
          }
          env {
            name = "KC_BOOTSTRAP_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminPassword"
              }
            }
          }
          # Legacy env-var names for Keycloak <26; harmless on 26+ (ignored).
          env {
            name = "KEYCLOAK_ADMIN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminUser"
              }
            }
          }
          env {
            name = "KEYCLOAK_ADMIN_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminPassword"
              }
            }
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
              name = local.keycloak_ecs_env_vars_configmap
            }
          }
        }
      }
    }
  }
}

resource "kubernetes_secret" "keycloak_auth" {
  metadata {
    name      = "keycloak-auth"
    namespace = var.KUBERNETES_NAMESPACE
  }
  data = {
    adminUser     = "admin"
    adminPassword = var.KEYCLOAK_ADMIN_PASSWORD
  }
}

resource "kubernetes_config_map" "keycloak_metrics" {
  metadata {
    name      = "keycloak-metrics"
    namespace = var.KUBERNETES_NAMESPACE
  }
  data = {
    enabled = "true"
  }
}