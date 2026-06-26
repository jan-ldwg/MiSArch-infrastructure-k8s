module "misarch_shoppingcart" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_shoppingcart_db, terraform_data.dapr]

  service = {
    name      = local.misarch_shoppingcart_service_name
    image     = "ghcr.io/misarch/shoppingcart:${var.MISARCH_SHOPPINGCART_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_shoppingcart_env_vars_configmap
    ecs  = local.misarch_shoppingcart_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_shoppingcart_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_shoppingcart_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
