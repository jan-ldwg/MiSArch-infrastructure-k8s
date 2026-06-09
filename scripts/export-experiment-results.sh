#!/usr/bin/env bash
# Export experiment configs, InfluxDB metrics, and log snippets to a local results directory.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPERIMENT_DIR="${EXPERIMENT_DIR:-${ROOT_DIR}/experiments/flash-sale}"
EXPERIMENT_PROFILE="${EXPERIMENT_PROFILE:-}"
NAMESPACE="${NAMESPACE:-misarch}"

TEST_UUID="${TEST_UUID:-}"
TEST_VERSION="${TEST_VERSION:-v1}"
OUTPUT_DIR="${OUTPUT_DIR:-}"
BASE_URL="${EXPERIMENT_BASE_URL:-}"
CURL_INSECURE="${CURL_INSECURE:-true}"
PEAK_USERS="${PEAK_USERS:-}"
BASELINE_USERS="${BASELINE_USERS:-50}"
INFLUX_ORG="${INFLUX_ORG:-misarch}"
INFLUX_BUCKET="${INFLUX_BUCKET:-gatling}"
INFLUX_LOCAL_PORT="${INFLUX_LOCAL_PORT:-18086}"
LOG_SNIPPET_LINES="${LOG_SNIPPET_LINES:-80}"
KUBECTL_TIMEOUT="${KUBECTL_TIMEOUT:-15s}"
CURL_MAX_TIME="${CURL_MAX_TIME:-30}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

k() {
  kubectl --request-timeout="$KUBECTL_TIMEOUT" "$@"
}

cluster_reachable() {
  k cluster-info >/dev/null 2>&1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd curl
require_cmd jq
require_cmd python3
require_cmd kubectl

[[ -n "$TEST_UUID" ]] || die "Set TEST_UUID (e.g. f539bdee-22cc-4ef2-91ba-602e72e4de5f)"

resolve_base_url() {
  if [[ -n "$BASE_URL" ]]; then
    echo "$BASE_URL"
    return
  fi
  local ip
  ip=$(k get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$ip" ]] || die "Set EXPERIMENT_BASE_URL or ensure ingress EXTERNAL-IP is available"
  echo "https://${ip}/experiment"
}

curl_api() {
  local method="$1"
  local path="$2"
  shift 2
  local curl_args=(-sS --connect-timeout 10 --max-time "$CURL_MAX_TIME" -X "$method")
  if [[ "$CURL_INSECURE" == "true" ]]; then
    curl_args+=(-k)
  fi
  curl "${curl_args[@]}" "${BASE_URL}${path}" "$@"
}

resolve_influx_token() {
  local token=""
  if [[ -d "${ROOT_DIR}/.terraform" ]] || [[ -f "${ROOT_DIR}/terraform.tfstate" ]]; then
    token=$(cd "$ROOT_DIR" && terraform output -raw influxdb_admin_token 2>/dev/null || true)
  fi
  if [[ -z "$token" ]]; then
    token=$(k get secret influxdb-admin-token -n "$NAMESPACE" \
      -o jsonpath='{.data.DOCKER_INFLUXDB_INIT_ADMIN_TOKEN}' 2>/dev/null | base64 -d || true)
  fi
  [[ -n "$token" ]] || die "Could not resolve InfluxDB token (terraform output or influxdb-admin-token secret)"
  printf '%s' "$token"
}

influx_service_port() {
  local port
  port=$(k get svc influxdb -n "$NAMESPACE" \
    -o jsonpath='{.spec.ports[?(@.name=="http")].port}' 2>/dev/null || true)
  if [[ -z "$port" ]]; then
    port=$(k get svc influxdb -n "$NAMESPACE" \
      -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || true)
  fi
  echo "${port:-8086}"
}

export_influx_metrics() {
  local out_csv="$1"
  local token pf_pid svc_port flux_query
  token="$(resolve_influx_token)"
  svc_port="$(influx_service_port)"

  flux_query=$(cat <<EOF
from(bucket:"${INFLUX_BUCKET}")
  |> range(start: -7d)
  |> filter(fn: (r) => r.testUUID == "${TEST_UUID}" and r.testVersion == "${TEST_VERSION}")
EOF
)

  k port-forward "svc/influxdb" -n "$NAMESPACE" "${INFLUX_LOCAL_PORT}:${svc_port}" >/dev/null 2>&1 &
  pf_pid=$!
  trap 'kill "$pf_pid" 2>/dev/null || true' RETURN

  local deadline=$((SECONDS + 30))
  local ready=false
  while (( SECONDS < deadline )); do
    if curl -sS --connect-timeout 2 --max-time 5 -o /dev/null \
      "http://127.0.0.1:${INFLUX_LOCAL_PORT}/health" 2>/dev/null; then
      ready=true
      break
    fi
    if ! kill -0 "$pf_pid" 2>/dev/null; then
      die "InfluxDB port-forward exited before becoming ready"
    fi
    sleep 1
  done
  [[ "$ready" == true ]] || die "InfluxDB port-forward did not become ready within 30s"

  curl -sS --connect-timeout 10 --max-time 120 \
    -X POST "http://127.0.0.1:${INFLUX_LOCAL_PORT}/api/v2/query?org=${INFLUX_ORG}" \
    -H "Authorization: Token ${token}" \
    -H "Accept: application/csv" \
    -H "Content-type: application/vnd.flux" \
    --data-binary "$flux_query" >"$out_csv" || die "InfluxDB Flux query failed"

  kill "$pf_pid" 2>/dev/null || true
  wait "$pf_pid" 2>/dev/null || true
  trap - RETURN
}

decode_gatling_usersteps() {
  local gatling_json="$1"
  local out_dir="$2"
  python3 - "$gatling_json" "$out_dir" <<'PY'
import base64
import json
import sys
from pathlib import Path

gatling_path = Path(sys.argv[1])
out_dir = Path(sys.argv[2])
data = json.loads(gatling_path.read_text())

for item in data:
    name = item.get("fileName", "scenario")
    encoded = item.get("encodedUserStepsFileContent")
    if not encoded:
        continue
    csv_text = base64.b64decode(encoded).decode("utf-8", errors="replace")
    out_file = out_dir / f"usersteps-{name.replace('flashSale', '').lower()}.csv"
    if "buy" in name.lower():
        out_file = out_dir / "usersteps-buy.csv"
    elif "browse" in name.lower():
        out_file = out_dir / "usersteps-browse.csv"
    out_file.write_text(csv_text)
PY
}

write_influx_summary() {
  local metrics_csv="$1"
  local summary_json="$2"
  python3 - "$metrics_csv" "$summary_json" <<'PY'
import csv
import json
import sys
from collections import defaultdict
from pathlib import Path

metrics_path = Path(sys.argv[1])
summary_path = Path(sys.argv[2])

if not metrics_path.exists() or metrics_path.stat().st_size == 0:
    summary_path.write_text(json.dumps({"error": "empty metrics export"}, indent=2))
    sys.exit(0)

text = metrics_path.read_text(errors="replace")
if text.lstrip().startswith("#"):
    # Influx CSV annotations — find first data row after headers
    lines = text.splitlines()
else:
    lines = text.splitlines()

rows = []
reader = csv.reader(lines)
headers = None
for row in reader:
    if not row:
        continue
    if row[0].startswith("#"):
        if row[0] in ("# datatype", "# default"):
            continue
        if len(row) > 1 and row[1]:
            headers = row[1:]
        continue
    if headers is None and row[0] in ("", "result") and "_time" in row:
        headers = row
        continue
    if headers and len(row) >= len(headers):
        rows.append(dict(zip(headers, row)))

if not rows:
    summary_path.write_text(json.dumps({"error": "no parsed metric rows", "raw_bytes": metrics_path.stat().st_size}, indent=2))
    sys.exit(0)

by_measurement = defaultdict(list)
for row in rows:
    field = row.get("_field") or row.get("field") or ""
    measurement = row.get("_measurement") or row.get("measurement") or ""
    value = row.get("_value") or row.get("value")
    flavor = row.get("flavor") or ""
    try:
        num = float(value)
    except (TypeError, ValueError):
        continue
    key = field if field and field != "value" else measurement
    if not key:
        continue
    if flavor:
        key = f"{key}:{flavor}"
    by_measurement[key].append(num)

def stats(values):
    if not values:
        return {}
    s = sorted(values)
    n = len(s)
    p95_idx = min(n - 1, int(n * 0.95))
    return {
        "count": n,
        "min": s[0],
        "max": s[-1],
        "mean": sum(s) / n,
        "p95": s[p95_idx],
    }

summary = {"measurements": {}, "highlights": {}}
for key, values in sorted(by_measurement.items()):
    summary["measurements"][key] = stats(values)

highlights = summary["highlights"]
field_map = {
    "meanNumberOfRequestsPerSecondOk": "peak_rps_ok",
    "meanNumberOfRequestsPerSecondKo": "peak_rps_ko",
    "meanResponseTime": "mean_response_time_ms",
    "meanResponseTimeOk": "mean_response_time_ok_ms",
    "meanResponseTimeKo": "mean_response_time_ko_ms",
    "numberOfRequestsOk": "total_requests_ok",
    "numberOfRequestsKo": "total_requests_ko",
}
for k, st in summary["measurements"].items():
    for suffix, label in field_map.items():
        if k == suffix or k.startswith(suffix + "_"):
            highlights[label] = st.get("max", st.get("mean"))
            break

ok_rps = highlights.get("peak_rps_ok", 0) or 0
ko_rps = highlights.get("peak_rps_ko", 0) or 0
if ok_rps or ko_rps:
    highlights["error_ratio_rps"] = ko_rps / (ok_rps + ko_rps) if (ok_rps + ko_rps) else 0.0

ok_total = highlights.get("total_requests_ok", 0) or 0
ko_total = highlights.get("total_requests_ko", 0) or 0
if ok_total or ko_total:
    highlights["error_ratio_requests"] = ko_total / (ok_total + ko_total) if (ok_total + ko_total) else 0.0

summary_path.write_text(json.dumps(summary, indent=2))
PY
}

extract_log_snippet() {
  local deployment="$1"
  local pattern="$2"
  local out_file="$3"
  {
    echo "# deployment: ${deployment}"
    echo "# pattern: ${pattern}"
    echo "# extracted: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo
    k logs -n "$NAMESPACE" "deploy/${deployment}" 2>/dev/null \
      | grep -E "${pattern}" | tail -n "$LOG_SNIPPET_LINES" || true
  } >"$out_file"
}

write_readme() {
  local out_dir="$1"
  cat >"${out_dir}/README.txt" <<EOF
Flash-sale experiment results export
====================================

Experiment: ${TEST_UUID} (${TEST_VERSION})
Exported:   $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Files
-----
  manifest.json           Run metadata (uuid, version, load profile)
  experiment-config.json  Experiment goals and settings from API
  gatling-config.json     Gatling scenarios (base64-encoded in API response)
  usersteps-*.csv         Load profile used for this run
  influxdb-metrics.csv    Raw Flux export from InfluxDB bucket "${INFLUX_BUCKET}"
  influxdb-summary.json   Aggregated request rate / response time / error stats
  executor.log.snippet    Experiment-executor lines around metrics push
  gatling.log.snippet     Gatling simulation completion lines

View live metrics
-----------------
InfluxDB (port-forward):
  kubectl port-forward svc/influxdb -n ${NAMESPACE} 8086:$(influx_service_port)
  Web UI: http://localhost:8086  (user admin; password from variables-misc.tf / terraform)

Grafana Explore (port-forward):
  kubectl port-forward svc/prometheus-stack-grafana -n ${NAMESPACE} 3000:80
  Password: kubectl get secret -n ${NAMESPACE} prometheus-stack-grafana \\
    -o jsonpath='{.data.admin-password}' | base64 -d

Example Flux filter:
  from(bucket:"${INFLUX_BUCKET}")
    |> range(start: -24h)
    |> filter(fn: (r) => r.testUUID == "${TEST_UUID}" and r.testVersion == "${TEST_VERSION}")

Experiment UI: ${BASE_URL%/experiment}/frontend/
EOF
}

main() {
  BASE_URL="$(resolve_base_url)"
  local run_dir="${OUTPUT_DIR:-${EXPERIMENT_DIR}/results/${TEST_UUID}-${TEST_VERSION}}"
  mkdir -p "$run_dir"

  log "Exporting ${TEST_UUID} (${TEST_VERSION}) to ${run_dir}"
  log "Experiment API: ${BASE_URL}"

  if curl_api GET "/${TEST_UUID}/${TEST_VERSION}/config" >"${run_dir}/experiment-config.json" 2>/dev/null; then
    :
  else
    warn "Could not fetch experiment config from API — writing placeholder."
    echo '{"error": "API unreachable — re-run export when cluster/ingress is available"}' \
      >"${run_dir}/experiment-config.json"
  fi

  if curl_api GET "/${TEST_UUID}/${TEST_VERSION}/gatlingConfig" >"${run_dir}/gatling-config.json" 2>/dev/null; then
    decode_gatling_usersteps "${run_dir}/gatling-config.json" "$run_dir" || true
  else
    warn "Could not fetch Gatling config from API — writing placeholder."
    echo '[]' >"${run_dir}/gatling-config.json"
  fi

  curl_api GET "/${TEST_UUID}/${TEST_VERSION}/misarchExperimentConfig" \
    >"${run_dir}/misarch-experiment-config.json" 2>/dev/null \
    || echo '[]' >"${run_dir}/misarch-experiment-config.json"
  curl_api GET "/${TEST_UUID}/${TEST_VERSION}/chaosToolkitConfig" \
    >"${run_dir}/chaos-toolkit-config.json" 2>/dev/null \
    || echo '{}' >"${run_dir}/chaos-toolkit-config.json"

  if [[ -f "${EXPERIMENT_DIR}/usersteps-buy.csv" ]]; then
    cp "${EXPERIMENT_DIR}/usersteps-buy.csv" "${run_dir}/usersteps-buy.csv"
  fi
  if [[ -f "${EXPERIMENT_DIR}/usersteps-browse.csv" ]]; then
    cp "${EXPERIMENT_DIR}/usersteps-browse.csv" "${run_dir}/usersteps-browse.csv"
  fi

  if [[ -z "$PEAK_USERS" && -f "${run_dir}/usersteps-buy.csv" ]]; then
    PEAK_USERS=$(python3 -c '
import csv, sys
from pathlib import Path
rows = list(csv.DictReader(Path(sys.argv[1]).read_text().splitlines()))
vals = [int(r["usersteps"]) for r in rows if r.get("usersteps")]
print(max(vals) if vals else "")
' "${run_dir}/usersteps-buy.csv")
  fi

  python3 <<PY >"${run_dir}/manifest.json"
import json
from datetime import datetime, timezone

manifest = {
    "testUUID": "${TEST_UUID}",
    "testVersion": "${TEST_VERSION}",
    "resilienceProfile": "${EXPERIMENT_PROFILE}" or None,
    "baselineUsersPerSecond": int("${BASELINE_USERS}" or 0) or None,
    "peakUsersPerSecond": int("${PEAK_USERS}" or 0) or None,
    "exportedAt": datetime.now(timezone.utc).isoformat(),
    "experimentApi": "${BASE_URL}",
    "influxOrg": "${INFLUX_ORG}",
    "influxBucket": "${INFLUX_BUCKET}",
}
print(json.dumps(manifest, indent=2))
PY

  log "Querying InfluxDB (port-forward)..."
  if cluster_reachable; then
    export_influx_metrics "${run_dir}/influxdb-metrics.csv"
    write_influx_summary "${run_dir}/influxdb-metrics.csv" "${run_dir}/influxdb-summary.json"

    extract_log_snippet "misarch-experiment-executor" \
      "Gatling Metrics pushed|Grafana|dashboard|Finished Experiment|deterioration|MisarchExperimentConfig|chaos" \
      "${run_dir}/executor.log.snippet"
    extract_log_snippet "misarch-gatling-executor" \
      "BUILD SUCCESSFUL|Simulation org\\.misarch\\.MainSimulation completed|trigger" \
      "${run_dir}/gatling.log.snippet"
  else
    warn "Cluster unreachable — skipping InfluxDB export and log snippets."
    echo "# cluster unreachable at export time" >"${run_dir}/influxdb-metrics.csv"
    echo '{"error": "cluster unreachable — re-run export when kubectl works"}' \
      >"${run_dir}/influxdb-summary.json"
    echo "# cluster unreachable at export time" >"${run_dir}/executor.log.snippet"
    echo "# cluster unreachable at export time" >"${run_dir}/gatling.log.snippet"
  fi

  write_readme "$run_dir"

  log "Results saved to: ${run_dir}"
  log "View InfluxDB:  kubectl port-forward svc/influxdb -n ${NAMESPACE} 8086:$(influx_service_port)"
  log "View Grafana:   kubectl port-forward svc/prometheus-stack-grafana -n ${NAMESPACE} 3000:80"
}

main "$@"
