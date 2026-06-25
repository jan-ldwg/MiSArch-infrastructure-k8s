module "misarch_gateway" {
  source                         = "./modules/misarch-service"
  depends_on                     = [terraform_data.dapr]

  service_name                  = local.misarch_gateway_service_name
  image                         = "ghcr.io/misarch/gateway:${var.MISARCH_GATEWAY_VERSION}"
  namespace                     = local.namespace
  cpu_limit                     = "2400m"
  memory_limit                  = "5Gi"
  cpu_request                   = "100m"
  memory_request                = "200Mi"
  base_configmap                = local.misarch_base_env_vars_configmap
  service_configmap             = local.misarch_gateway_env_vars_configmap
  ecs_configmap                 = local.misarch_gateway_ecs_env_vars_configmap
  ecs_image                     = "ghcr.io/misarch/experiment-config-sidecar:${var.MISARCH_EXPERIMENT_CONFIG_SIDECAR_VERSION}"
  base_labels                   = local.base_misarch_labels
  specific_labels               = local.misarch_gateway_specific_labels
  base_annotations              = local.base_misarch_annotations
  specific_annotations          = local.misarch_gateway_specific_annotations
  create_service                = true
  probe_type                    = "tcp_socket"
  readiness_initial_delay_seconds = 30
  readiness_period_seconds        = 10
}
