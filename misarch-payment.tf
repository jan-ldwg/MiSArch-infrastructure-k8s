module "misarch_payment" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_payment_db, terraform_data.dapr]

  service_name        = local.misarch_payment_service_name
  image               = "ghcr.io/misarch/payment:${var.MISARCH_PAYMENT_VERSION}"
  namespace           = local.namespace
  base_configmap      = local.misarch_base_env_vars_configmap
  service_configmap   = local.misarch_payment_env_vars_configmap
  ecs_configmap       = local.misarch_payment_ecs_env_vars_configmap
  ecs_image           = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
  base_labels         = local.base_misarch_labels
  specific_labels     = local.misarch_payment_specific_labels
  base_annotations    = local.base_misarch_annotations
  specific_annotations = local.misarch_payment_specific_annotations
}
