module "misarch_user" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_user_db, terraform_data.dapr]

  service = {
    name      = local.misarch_user_service_name
    image     = "ghcr.io/misarch/user:${var.MISARCH_USER_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_user_env_vars_configmap
    ecs  = local.misarch_user_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_user_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_user_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
