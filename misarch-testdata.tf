## One-shot seeder Job, ported from the docker-compose `testdata` service.
## Creates the `gatling` keycloak user in the Misarch realm and populates the
## store catalog via the GraphQL gateway. Without this, a fresh deployment
## has no users and no products.
##
## The container waits 4 minutes (INIT_IDLE) for the rest of the stack to
## come up before it talks to keycloak/gateway, so depends_on only needs to
## cover the resources it directly contacts.

resource "kubernetes_job" "misarch_testdata" {
  depends_on = [
    kubernetes_deployment.keycloak,
    kubernetes_deployment.misarch_gateway,
  ]

  metadata {
    name      = "misarch-testdata"
    namespace = local.namespace
  }

  spec {
    backoff_limit = 5

    template {
      metadata {
        labels = local.base_misarch_labels
      }

      spec {
        restart_policy = "OnFailure"

        container {
          name              = "testdata"
          image             = var.MISARCH_TESTDATA_VERSION
          image_pull_policy = "Always"

          env {
            name  = "GRAPHQL_ENDPOINT"
            value = "http://${local.misarch_gateway_service_name}:8080/graphql"
          }
          env {
            name  = "KEYCLOAK_URL"
            value = "http://${local.keycloak_service_name}:80/keycloak"
          }
          env {
            name  = "REALM"
            value = "Misarch"
          }
          env {
            name = "ADMIN_USER"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminUser"
              }
            }
          }
          env {
            name = "ADMIN_PASS"
            value_from {
              secret_key_ref {
                name = kubernetes_secret.keycloak_auth.metadata[0].name
                key  = "adminPassword"
              }
            }
          }
          env {
            name  = "ADMIN_CLIENT_ID"
            value = "admin-cli"
          }
          env {
            name  = "CLIENT_ID"
            value = "frontend"
          }
          env {
            name  = "GATLING_USERNAME"
            value = "gatling"
          }
          env {
            name  = "GATLING_PASSWORD"
            value = "123"
          }
          env {
            name  = "GRANT_TYPE"
            value = "password"
          }
          env {
            name  = "INIT_IDLE"
            value = "true"
          }
        }
      }
    }
  }

  wait_for_completion = false
}
