module "misarch_inventory" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_inventory_db, terraform_data.dapr]

  service = {
    name      = local.misarch_inventory_service_name
    image     = "ghcr.io/misarch/inventory:${var.MISARCH_INVENTORY_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_inventory_env_vars_configmap
    ecs  = local.misarch_inventory_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_inventory_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_inventory_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
