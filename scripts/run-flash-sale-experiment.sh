#!/usr/bin/env bash
# Configure and run the flash-sale load experiment via the experiment-executor REST API.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPERIMENT_DIR="${ROOT_DIR}/experiments/flash-sale"

BASE_URL="${EXPERIMENT_BASE_URL:-}"
CURL_INSECURE="${CURL_INSECURE:-true}"
TEST_NAME="${TEST_NAME:-Flash Sale Spike}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-900}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd curl
require_cmd python3
require_cmd jq

resolve_base_url() {
  if [[ -n "$BASE_URL" ]]; then
    echo "$BASE_URL"
    return
  fi
  local ip
  ip=$(kubectl get svc -n ingress-nginx ingress-nginx-controller \
    -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  [[ -n "$ip" ]] || die "Set EXPERIMENT_BASE_URL or ensure ingress EXTERNAL-IP is available"
  echo "https://${ip}/experiment"
}

curl_api() {
  local method="$1"
  local path="$2"
  shift 2
  local curl_args=(-sS -X "$method")
  if [[ "$CURL_INSECURE" == "true" ]]; then
    curl_args+=(-k)
  fi
  curl "${curl_args[@]}" "${BASE_URL}${path}" "$@"
}

b64_file() {
  python3 -c 'import base64, pathlib, sys; print(base64.b64encode(pathlib.Path(sys.argv[1]).read_bytes()).decode())' "$1"
}

build_gatling_payload() {
  python3 << PY
import base64
import json
import os
from pathlib import Path

root = Path("${EXPERIMENT_DIR}")
baseline = int(os.environ.get("BASELINE_USERS", "50"))
peak = int(os.environ.get("PEAK_USERS", "500"))

def build_steps():
    steps = [baseline] * 60
    steps += [baseline + int(i * (peak - baseline) / 15) for i in range(1, 16)]
    steps += [peak] * 60
    steps += [peak - int(i * (peak - baseline) / 15) for i in range(1, 16)]
    steps += [baseline] * 60
    return steps

buy = build_steps()
browse = [max(1, s // 5) for s in buy]

def csv_bytes(steps):
    return ("usersteps\n" + "\n".join(str(s) for s in steps) + "\n").encode()

scenarios = [
    ("flashSaleBuyProcess", root / "flashSaleBuyProcess.kt", csv_bytes(buy)),
    ("flashSaleBrowseOnly", root / "flashSaleBrowseOnly.kt", csv_bytes(browse)),
]
payload = []
for file_name, kt, csv in scenarios:
    payload.append({
        "fileName": file_name,
        "encodedWorkFileContent": base64.b64encode(kt.read_bytes()).decode(),
        "encodedUserStepsFileContent": base64.b64encode(csv).decode(),
    })
print(json.dumps(payload))
PY
}

generate_experiment() {
  local encoded_name
  encoded_name=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${TEST_NAME}'))")
  curl_api POST "/generate?loadType=ScalabilityLoadTest&testName=${encoded_name}&testDuration=210&maximumArrivingUsersPerSecond=500&rate=1"
}

wait_for_completion() {
  local uuid="$1"
  local version="$2"
  local curl_args=(-sSN --max-time "$WAIT_TIMEOUT")
  if [[ "$CURL_INSECURE" == "true" ]]; then
    curl_args+=(-k)
  fi

  log "Waiting for experiment completion (timeout ${WAIT_TIMEOUT}s)..."
  if curl "${curl_args[@]}" "${BASE_URL}/${uuid}/${version}/events" | tee /tmp/flash-sale-experiment-events.log; then
    if grep -q '/d/' /tmp/flash-sale-experiment-events.log 2>/dev/null; then
      log "Experiment finished. Dashboard URL:"
      grep -Eo 'https?://[^ ]+/d/[0-9a-f-]+-v[0-9]+' /tmp/flash-sale-experiment-events.log | tail -1 || true
      return 0
    fi
  fi
  die "Experiment did not complete within ${WAIT_TIMEOUT}s. Check: kubectl logs -n misarch deploy/misarch-gatling-executor"
}

main() {
  BASE_URL="$(resolve_base_url)"
  log "Experiment API: ${BASE_URL}"

  for f in \
    "${EXPERIMENT_DIR}/flashSaleBuyProcess.kt" \
    "${EXPERIMENT_DIR}/flashSaleBrowseOnly.kt" \
    "${EXPERIMENT_DIR}/usersteps-buy.csv" \
    "${EXPERIMENT_DIR}/usersteps-browse.csv"; do
    [[ -f "$f" ]] || die "Missing required file: $f"
  done

  local uuid_version uuid version
  uuid_version="$(generate_experiment | tr -d '\r\n')"
  [[ "$uuid_version" == *:* ]] || die "Unexpected generate response: ${uuid_version}"
  uuid="${uuid_version%%:*}"
  version="${uuid_version##*:}"
  log "Created experiment ${uuid} (${version})"

  local gatling_payload experiment_config chaos_config
  gatling_payload="$(build_gatling_payload)"
  curl_api PUT "/${uuid}/${version}/gatlingConfig" \
    -H "Content-Type: application/json" \
    --data-binary "$gatling_payload" >/dev/null
  log "Uploaded Gatling scenarios and load profile"

  experiment_config=$(jq -n \
    --arg testUUID "$uuid" \
    --arg testVersion "$version" \
    --arg testName "$TEST_NAME" \
    '{
      testUUID: $testUUID,
      testVersion: $testVersion,
      testName: $testName,
      loadType: "ScalabilityLoadTest",
      goals: [
        { metric: "max response time", threshold: "2000", color: "red" },
        { metric: "mean response time", threshold: "1000", color: "yellow" }
      ]
    }')
  curl_api PUT "/${uuid}/${version}/config" \
    -H "Content-Type: application/json" \
    --data-binary "$experiment_config" >/dev/null
  log "Updated experiment config (no warm-up / steady-state)"

  chaos_config=$(jq -n \
    --arg title "${uuid}:${version}" \
    --arg description "${uuid}:${version}" \
    '{ title: $title, description: $description, method: [] }')
  curl_api PUT "/${uuid}/${version}/chaosToolkitConfig" \
    -H "Content-Type: application/json" \
    --data-binary "$chaos_config" >/dev/null

  curl_api PUT "/${uuid}/${version}/misarchExperimentConfig" \
    -H "Content-Type: application/json" \
    --data-binary '[]' >/dev/null
  log "Disabled failure injection configs"

  local start_code
  start_code=$(curl_api POST "/${uuid}/${version}/start" -o /tmp/flash-sale-start.out -w '%{http_code}')
  [[ "$start_code" == "200" ]] || die "Failed to start experiment (HTTP ${start_code}): $(cat /tmp/flash-sale-start.out)"
  log "Experiment started"

  wait_for_completion "$uuid" "$version"
  log "Done. Experiment UI: ${BASE_URL%/experiment}/frontend/"
}

main "$@"
