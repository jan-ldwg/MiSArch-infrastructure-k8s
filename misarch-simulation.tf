module "misarch_simulation" {
  source     = "./modules/misarch-service"
  depends_on = [terraform_data.dapr, kubernetes_deployment.keycloak]

  service_name        = local.misarch_simulation_service_name
  image               = "ghcr.io/misarch/simulation:${var.MISARCH_SIMULATION_VERSION}"
  namespace           = local.namespace
  base_configmap      = local.misarch_base_env_vars_configmap
  service_configmap   = local.misarch_simulation_env_vars_configmap
  ecs_configmap       = local.misarch_simulation_ecs_env_vars_configmap
  ecs_image           = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
  base_labels         = local.base_misarch_labels
  specific_labels     = local.misarch_simulation_specific_labels
  base_annotations    = local.base_misarch_annotations
  specific_annotations = local.misarch_simulation_specific_annotations
}
