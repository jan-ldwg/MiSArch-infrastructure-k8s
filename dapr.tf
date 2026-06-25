resource "helm_release" "redis" {
  depends_on = [kubernetes_namespace.misarch]
  name       = "redis"
  repository = "oci://registry-1.docker.io/bitnamicharts"
  chart      = "redis"
  namespace  = local.namespace

  values = [
    local.bitnami_legacy_redis_image_overrides,
    <<-EOF
  global:
    storageClass: "${local.storage_class_name}"
  auth:
    password: "${random_password.redis.result}"
  # Readiness re-enabled with fast timing (Redis binds port 6379 quickly even during RDB load).
  # Liveness has a 300s initial delay to survive RDB loading from HDD.
  master:
    readinessProbe:
      enabled: true
      initialDelaySeconds: 0
      periodSeconds: 5
      failureThreshold: 3
    livenessProbe:
      enabled: true
      initialDelaySeconds: 300
      periodSeconds: 10
      failureThreshold: 3
    extraFlags:
      - "--appendonly no"
      - "--save 900 1"
      - "--save 300 10"
      - "--save 60 10000"
    persistence:
      enabled: true
    terminationGracePeriodSeconds: 30

  replica:
    replicaCount: 0

  metrics:
    enabled: true
  EOF
  ]
}

resource "helm_release" "dapr" {
  depends_on = [helm_release.redis]
  name       = "dapr"
  repository = "https://dapr.github.io/helm-charts"
  chart      = "dapr"
  namespace  = local.namespace
}

resource "kubectl_manifest" "dapr_state_config" {
  depends_on = [helm_release.dapr]
  yaml_body  = <<-EOF
  apiVersion:  "dapr.io/v1alpha1"
  kind: "Component"
  metadata:
    name: "statestore"
    namespace: ${local.namespace}

  spec:
    type: "state.redis"
    version: "v1"

    metadata:
      - name: "redisHost"
        value: "redis-master:6379"
      - name: "redisPassword"
        value: ${random_password.redis.result}
      - name: "dialTimeout"
        value: "30s"
      - name: "readTimeout"
        value: "15s"
      - name: "writeTimeout"
        value: "15s"
      - name: "maxRetries"
        value: "5"
      - name: "maxRetryBackoff"
        value: "5"
  EOF
}

resource "kubectl_manifest" "dapr_pubsub_config" {
  depends_on = [helm_release.dapr]
  yaml_body  = <<-EOF
  apiVersion:  "dapr.io/v1alpha1"
  kind: "Component"
  metadata:
    name: "pubsub"
    namespace: ${local.namespace}

  spec:
    type: "pubsub.redis"
    version: "v1"

    metadata:
      - name: "redisHost"
        value: "redis-master:6379"
      - name: "redisPassword"
        value: ${random_password.redis.result}
      - name: "dialTimeout"
        value: "30s"
      - name: "maxRetries"
        value: "5"
      - name: "maxRetryBackoff"
        value: "5"
      - name: "publishRetryInterval"
        value: "1s"
  EOF
}

resource "kubectl_manifest" "dapr_pubsub_config_experiment_config" {
  depends_on = [helm_release.dapr]
  yaml_body  = <<-EOF
  apiVersion:  "dapr.io/v1alpha1"
  kind: "Component"
  metadata:
    name: "experiment-config-pubsub"
    namespace: ${local.namespace}

  spec:
    type: "pubsub.redis"
    version: "v1"

    metadata:
      - name: "redisHost"
        value: "redis-master:6379"
      - name: "redisPassword"
        value: ${random_password.redis.result}
      - name: "dialTimeout"
        value: "30s"
      - name: "maxRetries"
        value: "5"
      - name: "maxRetryBackoff"
        value: "5"
      - name: "publishRetryInterval"
        value: "1s"
  EOF
}

resource "kubectl_manifest" "dapr_config" {
  depends_on = [helm_release.dapr]
  yaml_body  = <<-EOF
    apiVersion: dapr.io/v1alpha1
    kind: Configuration
    metadata:
      name: "${local.dapr_general_config_name}"
      namespace: "${local.namespace}"
    spec:
      tracing:
        samplingRate: "${var.dapr_tracing_sampling_rate}"
        otel:
          endpointAddress: ${local.otel_collector_url}
          protocol: grpc
          isSecure: false
      metrics:
        enabled: true
  EOF
}

// Pseudo resource so that all services can simply depend on this resource instead of the whole list ↓
resource "terraform_data" "dapr" {
  depends_on = [helm_release.dapr, kubectl_manifest.dapr_config, kubectl_manifest.dapr_pubsub_config_experiment_config,
    kubectl_manifest.dapr_pubsub_config, kubectl_manifest.dapr_state_config]
}
