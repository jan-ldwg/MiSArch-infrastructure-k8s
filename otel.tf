resource "helm_release" "otel-collector" {
  name       = local.otel_collector_service_name
  repository = "https://open-telemetry.github.io/opentelemetry-helm-charts"
  chart      = "opentelemetry-collector"
  namespace  = local.namespace

  values = [
    var.otel_collector_mode == "gcp" ? <<-EOF
    mode: "deployment"
    image:
      repository: "otel/opentelemetry-collector"
      tag: ${var.OTEL_COLLECTOR_VERSION}
    service:
      enabled: true
      type: ClusterIP
    ports:
      metrics:
        enabled: true
        containerPort: 8889
        servicePort: 8889
        protocol: TCP
    config:
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: "$${MY_POD_IP}:4317"
            http:
              endpoint: "$${MY_POD_IP}:4318"

        prometheus:
          config:
            scrape_configs:
              - job_name: 'dapr-metrics'
                scrape_interval: 5s
                kubernetes_sd_configs:
                  - role: pod
                relabel_configs:
                  - source_labels: [__meta_kubernetes_pod_label_app]
                    action: keep
                    regex: keycloak|misarch-(address|catalog|discount|gateway|inventory|invoice|media|notification|order|payment|return|review|shipment|shoppingcart|simulation|tax|user|wishlist)

      exporters:
        prometheus:
          endpoint: "0.0.0.0:8889"
        otlp/jaeger:
          endpoint: "${local.jaeger_collector_url}"
          tls:
            insecure: true

      service:
        pipelines:
          metrics:
            receivers: [otlp, prometheus]
            exporters: [prometheus]
          traces:
            receivers: [otlp]
            exporters: [otlp/jaeger]
        telemetry:
          logs:
            level: "error"
    EOF
    : <<-EOF
    mode: "deployment"
    image:
      repository: "otel/opentelemetry-collector"
      tag: ${var.OTEL_COLLECTOR_VERSION}
    service:
      enabled: true
      type: ClusterIP
    ports:
      metrics:
        enabled: false
    config:
      receivers:
        otlp:
          protocols:
            http:
              endpoint: "0.0.0.0:4318"
      exporters:
        debug:
          verbosity: detailed
        otlp/jaeger:
          endpoint: "${local.jaeger_collector_url}"
          tls:
            insecure: true
      service:
        pipelines:
          metrics:
            receivers: [otlp]
            exporters: [debug]
          traces:
            receivers: [otlp]
            exporters: [otlp/jaeger, debug]
          logs:
            receivers: [otlp]
            exporters: [debug]
        telemetry:
          logs:
            level: "debug"
    EOF
  ]
}

# Cluster-level RBAC for Prometheus service discovery — only needed in GCP mode
resource "kubernetes_cluster_role" "otel_collector_prom_sd" {
  count = var.otel_collector_mode == "gcp" ? 1 : 0
  metadata {
    name = "otel-collector-prometheus-sd"
  }

  rule {
    api_groups = [""]
    resources  = ["pods"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "otel_collector_prom_sd" {
  count = var.otel_collector_mode == "gcp" ? 1 : 0
  metadata {
    name = "otel-collector-prometheus-sd"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_collector_prom_sd[0].metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = "otel-collector-opentelemetry-collector"
    namespace = local.namespace
  }
}
