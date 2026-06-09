resource "helm_release" "prometheus_grafana_stack" {
  name       = "prometheus-stack"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  namespace  = local.namespace

  values = [
    <<-EOF
  prometheus:
    prometheusSpec:
      additionalScrapeConfigs:
        - job_name: 'otel-collector'
          scrape_interval: 5s
          static_configs:
            - targets: ['${local.otel_collector_prometheus_url}']

  grafana:
    enabled: true
    sidecar:
      dashboards:
        enabled: true
        label: grafana_dashboard
        labelValue: "1"
        folderAnnotation: grafana_folder
        provider:
          # Required when using grafana_folder annotation; otherwise JSON files
          # land in /tmp/dashboards/<folder>/ but Grafana ignores subdirectories.
          foldersFromFilesStructure: true
          allowUiUpdates: true
    datasources:
      datasources.yaml:
        apiVersion: 1
        datasources:
          - name: InfluxDB
            uid: influxdb_uid
            type: influxdb
            access: proxy
            url: http://${local.influxdb_url}
            jsonData:
              version: Flux
              organization: ${var.INFLUXDB_ORG}
              defaultBucket: ${var.INFLUXDB_BUCKET}
              httpMode: POST
            secureJsonData:
              token: "${random_password.influxdb_admin_token.result}"

  EOF
  ]
}

data "kubernetes_secret" "grafana_admin" {
  depends_on = [helm_release.prometheus_grafana_stack]

  metadata {
    name      = "prometheus-stack-grafana"
    namespace = local.namespace
  }
}