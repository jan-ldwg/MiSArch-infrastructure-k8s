module "misarch_frontend" {
  source     = "./modules/misarch-service"
  depends_on = [terraform_data.dapr, kubernetes_deployment.keycloak]

  service = {
    name      = local.misarch_frontend_service_name
    image     = "ghcr.io/misarch/frontend:${var.MISARCH_FRONTEND_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_frontend_env_vars_configmap
    ecs  = local.misarch_frontend_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_frontend_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_frontend_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
