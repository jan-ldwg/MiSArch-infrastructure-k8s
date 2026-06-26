module "misarch_simulation" {
  source     = "./modules/misarch-service"
  depends_on = [terraform_data.dapr, kubernetes_deployment.keycloak]

  service = {
    name      = local.misarch_simulation_service_name
    image     = "ghcr.io/misarch/simulation:${var.MISARCH_SIMULATION_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_simulation_env_vars_configmap
    ecs  = local.misarch_simulation_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_simulation_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_simulation_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
