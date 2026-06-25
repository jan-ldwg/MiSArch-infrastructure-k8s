module "misarch_frontend" {
  source     = "./modules/misarch-service"
  depends_on = [terraform_data.dapr, kubernetes_deployment.keycloak]

  service_name        = local.misarch_frontend_service_name
  image               = "ghcr.io/misarch/frontend:${var.MISARCH_FRONTEND_VERSION}"
  namespace           = local.namespace
  base_configmap      = local.misarch_base_env_vars_configmap
  service_configmap   = local.misarch_frontend_env_vars_configmap
  ecs_configmap       = local.misarch_frontend_ecs_env_vars_configmap
  ecs_image           = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
  base_labels         = local.base_misarch_labels
  specific_labels     = local.misarch_frontend_specific_labels
  base_annotations    = local.base_misarch_annotations
  specific_annotations = local.misarch_frontend_specific_annotations
}
