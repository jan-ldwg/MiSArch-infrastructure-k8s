module "misarch_address" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_address_db, terraform_data.dapr]

  service = {
    name      = local.misarch_address_service_name
    image     = "ghcr.io/misarch/address:${var.MISARCH_ADDRESS_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_address_env_vars_configmap
    ecs  = local.misarch_address_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_address_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_address_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
