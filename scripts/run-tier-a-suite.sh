#!/usr/bin/env bash
# Run all Tier A resilience experiments sequentially and record outcomes.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_ROOT="${ROOT_DIR}/experiments/resilience/results"
SUITE_LOG="${RESULTS_ROOT}/suite-summary.txt"

PROFILES=(
  baseline-spike
  inventory-slowdown
  payment-failure
  pubsub-disruption
  inventory-kill-oversell
  retry-storm
  compound-fault
)

SUITE_LOG_FILE="${SUITE_LOG_FILE:-/tmp/tier-a-suite.log}"

log() { printf '%s\n' "$*" | tee -a "$SUITE_LOG_FILE"; }
die() { printf 'ERROR: %s\n' "$*" >&2 | tee -a "$SUITE_LOG_FILE"; exit 1; }

mkdir -p "$RESULTS_ROOT"
: > "$SUITE_LOG_FILE"
: > "${RESULTS_ROOT}/run-log.txt"

log "Tier A resilience suite — ${#PROFILES[@]} experiments"
log "Started: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "${SKIP_CLUSTER_PREP:-false}" != "true" ]]; then
  "${ROOT_DIR}/scripts/prepare-experiment-cluster.sh"
fi

local_fail=0
for profile in "${PROFILES[@]}"; do
  log ""
  log "========== ${profile} =========="
  # prepare-experiment-cluster.sh seeds once; re-seed only for low-stock profile
  skip_shop_seed=true
  if [[ "$profile" == "inventory-kill-oversell" ]]; then
    skip_shop_seed=false
  fi
  if EXPERIMENT_PROFILE="$profile" SKIP_SHOP_SEED="$skip_shop_seed" \
    "${ROOT_DIR}/scripts/run-resilience-experiment.sh"; then
    echo "OK  ${profile}  $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SUITE_LOG"
  else
    echo "FAIL ${profile}  $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$SUITE_LOG"
    local_fail=1
    log "Experiment ${profile} failed — continuing suite."
  fi
  # Brief cooldown between runs so Gatling/executor logs stay separable
  sleep 30
done

log ""
log "Suite finished: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
log "Summary: ${SUITE_LOG}"
[[ "$local_fail" -eq 0 ]] || exit 1
