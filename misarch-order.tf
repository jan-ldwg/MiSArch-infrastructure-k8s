module "misarch_order" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_order_db, terraform_data.dapr]

  service = {
    name      = local.misarch_order_service_name
    image     = "ghcr.io/misarch/order:${var.MISARCH_ORDER_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_order_env_vars_configmap
    ecs  = local.misarch_order_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_order_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_order_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
