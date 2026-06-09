#!/usr/bin/env bash
# Run a Tier A resilience experiment profile via the experiment-executor REST API.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPERIMENT_DIR="${ROOT_DIR}/experiments/resilience"
FLASH_SALE_DIR="${ROOT_DIR}/experiments/flash-sale"
PROFILE_DIR="${EXPERIMENT_DIR}/profiles"

EXPERIMENT_PROFILE="${EXPERIMENT_PROFILE:-baseline-spike}"
BASE_URL="${EXPERIMENT_BASE_URL:-}"
CURL_INSECURE="${CURL_INSECURE:-true}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-1200}"
BASELINE_USERS="${BASELINE_USERS:-50}"
TEST_DURATION="${TEST_DURATION:-210}"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd curl
require_cmd python3
require_cmd jq
require_cmd kubectl

[[ -f "${PROFILE_DIR}/catalog.json" ]] || die "Missing catalog: ${PROFILE_DIR}/catalog.json"
jq -e --arg p "$EXPERIMENT_PROFILE" '.[$p]' "${PROFILE_DIR}/catalog.json" >/dev/null \
  || die "Unknown EXPERIMENT_PROFILE: ${EXPERIMENT_PROFILE}"

PROFILE_JSON=$(jq -c --arg p "$EXPERIMENT_PROFILE" '.[$p]' "${PROFILE_DIR}/catalog.json")
TEST_NAME=$(jq -r '.name' <<<"$PROFILE_JSON")
LOAD_TYPE=$(jq -r '.loadType' <<<"$PROFILE_JSON")
PEAK_USERS="${PEAK_USERS:-$(jq -r '.peakUsers' <<<"$PROFILE_JSON")}"
SHOP_MODE=$(jq -r '.shopMode' <<<"$PROFILE_JSON")
MISARCH_FILE=$(jq -r '.misarchProfile' <<<"$PROFILE_JSON")
CHAOS_FILE=$(jq -r '.chaosProfile' <<<"$PROFILE_JSON")
EXPERIMENT_ID=$(jq -r '.id' <<<"$PROFILE_JSON")
HYPOTHESIS=$(jq -r '.hypothesis' <<<"$PROFILE_JSON")

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

build_gatling_payload() {
  python3 << PY
import base64
import json
import os
from pathlib import Path

root = Path("${FLASH_SALE_DIR}")
baseline = int(os.environ.get("BASELINE_USERS", "50"))
peak = int(os.environ.get("PEAK_USERS", "250"))

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
  curl_api POST "/generate?loadType=${LOAD_TYPE}&testName=${encoded_name}&testDuration=${TEST_DURATION}&maximumArrivingUsersPerSecond=${PEAK_USERS}&rate=1"
}

build_chaos_config() {
  local uuid="$1"
  local version="$2"
  local title="${uuid}:${version}"
  sed -e "s|__TITLE__|${title}|g" -e "s|__DESCRIPTION__|${title}|g" \
    "${PROFILE_DIR}/chaos/${CHAOS_FILE}"
}

wait_for_completion() {
  local uuid="$1"
  local version="$2"
  local deadline=$((SECONDS + WAIT_TIMEOUT))
  local dashboard_url=""
  local initial_restarts
  initial_restarts=$(kubectl get pod -n misarch -l app=misarch-gatling-executor \
    -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)

  log "Waiting for experiment completion (timeout ${WAIT_TIMEOUT}s)..."

  while (( SECONDS < deadline )); do
    if kubectl logs -n misarch deploy/misarch-experiment-executor --since=3h 2>/dev/null \
      | grep -q "Finished Experiment run for testUUID: ${uuid} and testVersion: ${version}"; then
      dashboard_url=$(kubectl logs -n misarch deploy/misarch-experiment-executor --since=3h 2>/dev/null \
        | grep "/d/${uuid}-${version}" \
        | grep -Eo 'https?://[^ ]+/d/[0-9a-f-]+-v[0-9]+' | tail -1 || true)
      if [[ -n "$dashboard_url" ]]; then
        log "Experiment finished. Dashboard URL: ${dashboard_url}"
      else
        log "Experiment finished (metrics pushed; check executor logs for dashboard URL)."
      fi
      return 0
    fi

    local current_restarts oom_reason
    current_restarts=$(kubectl get pod -n misarch -l app=misarch-gatling-executor \
      -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
    oom_reason=$(kubectl get pod -n misarch -l app=misarch-gatling-executor \
      -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}' 2>/dev/null || true)
    if (( current_restarts > initial_restarts )) && [[ "$oom_reason" == "OOMKilled" ]]; then
      die "Gatling executor was OOMKilled. Lower PEAK_USERS or raise memory limits."
    fi

    sleep 15
  done

  die "Experiment did not complete within ${WAIT_TIMEOUT}s."
}

write_resilience_notes() {
  local run_dir="$1"
  cat >"${run_dir}/resilience-notes.txt" <<EOF
MiSArch Tier A Resilience Experiment
====================================
Profile ID:    ${EXPERIMENT_ID}
Profile:       ${EXPERIMENT_PROFILE}
Name:          ${TEST_NAME}
Hypothesis:    ${HYPOTHESIS}
Load:          baseline=${BASELINE_USERS} peak=${PEAK_USERS} users/s (${TEST_DURATION}s)
Shop mode:     ${SHOP_MODE}
Misarch config: profiles/misarch/${MISARCH_FILE}
Chaos config:   profiles/chaos/${CHAOS_FILE}
Exported:      $(date -u +"%Y-%m-%dT%H:%M:%SZ")

Metrics focus:
  - influxdb-summary.json: error_ratio, response times, request rates (ok/ko)
  - Compare peak_requests_per_second and mean_response_time_ms across profiles
  - executor.log.snippet: Grafana export + fault plugin activity
  - gatling.log.snippet: BUILD SUCCESSFUL / simulation completion

Suggested refactorings if hypothesis confirmed:
  - Timeouts + circuit breakers on sync hot path (inventory, payment)
  - Saga orchestration + outbox + compensation
  - Durable messaging / DLQ for pub/sub pipeline
  - Gateway load shedding under spike + compound faults
EOF
}

main() {
  BASE_URL="$(resolve_base_url)"
  log "Profile: ${EXPERIMENT_PROFILE} (Tier A #${EXPERIMENT_ID})"
  log "Experiment API: ${BASE_URL}"
  log "Load: baseline=${BASELINE_USERS} peak=${PEAK_USERS} users/s"

  if [[ "${SKIP_SHOP_SEED:-false}" != "true" ]]; then
    log "Preparing shop (mode=${SHOP_MODE})..."
    SHOP_MODE="$SHOP_MODE" "${ROOT_DIR}/scripts/seed-resilience-shop.sh"
  fi

  for f in \
    "${FLASH_SALE_DIR}/flashSaleBuyProcess.kt" \
    "${FLASH_SALE_DIR}/flashSaleBrowseOnly.kt"; do
    [[ -f "$f" ]] || die "Missing Gatling scenario: $f"
  done

  local uuid_version uuid version
  uuid_version="$(generate_experiment | tr -d '\r\n')"
  [[ "$uuid_version" == *:* ]] || die "Unexpected generate response: ${uuid_version}"
  uuid="${uuid_version%%:*}"
  version="${uuid_version##*:}"
  log "Created experiment ${uuid} (${version})"

  local gatling_payload experiment_config chaos_config misarch_config
  gatling_payload="$(PEAK_USERS="$PEAK_USERS" BASELINE_USERS="$BASELINE_USERS" build_gatling_payload)"
  curl_api PUT "/${uuid}/${version}/gatlingConfig" \
    -H "Content-Type: application/json" \
    --data-binary "$gatling_payload" >/dev/null
  log "Uploaded Gatling scenarios"

  experiment_config=$(jq -n \
    --arg testUUID "$uuid" \
    --arg testVersion "$version" \
    --arg testName "$TEST_NAME" \
    --arg loadType "$LOAD_TYPE" \
    --arg profile "$EXPERIMENT_PROFILE" \
    '{
      testUUID: $testUUID,
      testVersion: $testVersion,
      testName: $testName,
      loadType: $loadType,
      goals: [
        { metric: "max response time", threshold: "5000", color: "red" },
        { metric: "mean response time", threshold: "2000", color: "yellow" }
      ]
    }')
  curl_api PUT "/${uuid}/${version}/config" \
    -H "Content-Type: application/json" \
    --data-binary "$experiment_config" >/dev/null

  chaos_config="$(build_chaos_config "$uuid" "$version")"
  curl_api PUT "/${uuid}/${version}/chaosToolkitConfig" \
    -H "Content-Type: application/json" \
    --data-binary "$chaos_config" >/dev/null

  misarch_config=$(cat "${PROFILE_DIR}/misarch/${MISARCH_FILE}")
  curl_api PUT "/${uuid}/${version}/misarchExperimentConfig" \
    -H "Content-Type: application/json" \
    --data-binary "$misarch_config" >/dev/null
  log "Uploaded fault injection configs"

  local start_code
  start_code=$(curl_api POST "/${uuid}/${version}/start" -o /tmp/resilience-start.out -w '%{http_code}')
  [[ "$start_code" == "200" ]] || die "Failed to start (HTTP ${start_code}): $(cat /tmp/resilience-start.out)"
  log "Experiment started"

  wait_for_completion "$uuid" "$version"

  local results_dir="${EXPERIMENT_DIR}/results/${uuid}-${version}"
  mkdir -p "$results_dir"
  write_resilience_notes "$results_dir"

  if [[ -x "${ROOT_DIR}/scripts/export-experiment-results.sh" ]]; then
    log "Exporting results..."
    TEST_UUID="$uuid" TEST_VERSION="$version" \
      EXPERIMENT_DIR="$EXPERIMENT_DIR" \
      PEAK_USERS="$PEAK_USERS" BASELINE_USERS="$BASELINE_USERS" \
      EXPERIMENT_BASE_URL="$BASE_URL" \
      EXPERIMENT_PROFILE="$EXPERIMENT_PROFILE" \
      "${ROOT_DIR}/scripts/export-experiment-results.sh" || \
      log "Warning: export failed (see errors above)."
  fi

  echo "${uuid}" > "${EXPERIMENT_DIR}/results/.last-uuid"
  echo "${EXPERIMENT_PROFILE}" >> "${EXPERIMENT_DIR}/results/run-log.txt"

  log "Done. Results: ${results_dir}/"
}

main "$@"
