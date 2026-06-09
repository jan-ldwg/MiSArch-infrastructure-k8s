resource "kubernetes_config_map" "grafana_dashboards" {
  depends_on = [helm_release.prometheus_grafana_stack]

  metadata {
    name      = "misarch-grafana-dashboards"
    namespace = local.namespace
    labels = {
      grafana_dashboard = "1"
    }
    annotations = {
      grafana_folder = "MiSArch"
    }
  }

  data = {
    "misarch-ops-prometheus.json"       = file("${path.module}/grafana/dashboards/misarch-ops-prometheus.json")
    "misarch-experiments-influxdb.json" = file("${path.module}/grafana/dashboards/misarch-experiments-influxdb.json")
  }
}
