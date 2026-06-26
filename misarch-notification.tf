module "misarch_notification" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_notification_db, terraform_data.dapr]

  service = {
    name      = local.misarch_notification_service_name
    image     = "ghcr.io/misarch/notification:${var.MISARCH_NOTIFICATION_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_notification_env_vars_configmap
    ecs  = local.misarch_notification_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_notification_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_notification_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
