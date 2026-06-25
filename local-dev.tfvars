# Local development overrides (minikube / kind / Docker Desktop)
#
# Usage:
#   terraform apply -var-file=local-dev.tfvars -target=kubernetes_namespace.misarch -target=helm_release.dapr -target=helm_release.redis -target=helm_release.misarch_order_db -target=kubernetes_deployment.misarch_order

deployment_target        = "local"

ROOT_DOMAIN              = "http://localhost:8080"
storage_class_name       = "standard"
create_gcp_storage_class = false
dapr_log_level           = "error"
otel_log_level           = "error"
otel_disabled            = false
dapr_tracing_sampling_rate = "1"
otel_collector_mode       = "local"

# Override image versions to use 'main' tags (no pinned SHA digests)
MISARCH_ORDER_VERSION = "main"
