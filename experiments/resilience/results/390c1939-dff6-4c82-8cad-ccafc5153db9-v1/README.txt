Flash-sale experiment results export
====================================

Experiment: 390c1939-dff6-4c82-8cad-ccafc5153db9 (v1)
Exported:   2026-06-09T09:11:32Z

Files
-----
  manifest.json           Run metadata (uuid, version, load profile)
  experiment-config.json  Experiment goals and settings from API
  gatling-config.json     Gatling scenarios (base64-encoded in API response)
  usersteps-*.csv         Load profile used for this run
  influxdb-metrics.csv    Raw Flux export from InfluxDB bucket "gatling"
  influxdb-summary.json   Aggregated request rate / response time / error stats
  executor.log.snippet    Experiment-executor lines around metrics push
  gatling.log.snippet     Gatling simulation completion lines

View live metrics
-----------------
InfluxDB (port-forward):
  kubectl port-forward svc/influxdb -n misarch 8086:80
  Web UI: http://localhost:8086  (user admin; password from variables-misc.tf / terraform)

Grafana Explore (port-forward):
  kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
  Password: kubectl get secret -n misarch prometheus-stack-grafana \
    -o jsonpath='{.data.admin-password}' | base64 -d

Example Flux filter:
  from(bucket:"gatling")
    |> range(start: -24h)
    |> filter(fn: (r) => r.testUUID == "390c1939-dff6-4c82-8cad-ccafc5153db9" and r.testVersion == "v1")

Experiment UI: https://35.246.166.155/frontend/
