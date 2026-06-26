module "misarch_shipment" {
  source     = "./modules/misarch-service"
  depends_on = [helm_release.misarch_shipment_db, terraform_data.dapr]

  service = {
    name      = local.misarch_shipment_service_name
    image     = "ghcr.io/misarch/shipment:${var.MISARCH_SHIPMENT_VERSION}"
    namespace = local.namespace
  }
  config = {
    base = local.misarch_base_env_vars_configmap
    env  = local.misarch_shipment_env_vars_configmap
    ecs  = local.misarch_shipment_ecs_env_vars_configmap
  }
  metadata = {
    labels      = merge(local.base_misarch_labels, local.misarch_shipment_specific_labels)
    annotations = merge(local.base_misarch_annotations, local.misarch_shipment_specific_annotations)
  }
  ecs_image = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
}
