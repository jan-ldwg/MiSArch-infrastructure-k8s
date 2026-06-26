module "misarch_wishlist" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_wishlist_db, terraform_data.dapr]

  service = {
    name      = local.misarch_wishlist_service_name
    image     = "ghcr.io/misarch/wishlist:${var.MISARCH_WISHLIST_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_wishlist_env_vars_configmap
    ecs  = local.misarch_wishlist_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_wishlist_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_wishlist_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
