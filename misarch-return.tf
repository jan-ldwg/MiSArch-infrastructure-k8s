module "misarch_return" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_return_db, terraform_data.dapr]

  service_name        = local.misarch_return_service_name
  image               = "ghcr.io/misarch/return:${var.MISARCH_RETURN_VERSION}"
  namespace           = local.namespace
  base_configmap      = local.misarch_base_env_vars_configmap
  service_configmap   = local.misarch_return_env_vars_configmap
  ecs_configmap       = local.misarch_return_ecs_env_vars_configmap
  ecs_image           = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
  base_labels         = local.base_misarch_labels
  specific_labels     = local.misarch_return_specific_labels
  base_annotations    = local.base_misarch_annotations
  specific_annotations = local.misarch_return_specific_annotations
}
