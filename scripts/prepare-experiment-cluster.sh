#!/usr/bin/env bash
# Wait for cluster readiness and seed shop before resilience experiments.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NAMESPACE="${NAMESPACE:-misarch}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd kubectl
require_cmd curl

log "Waiting for misarch-testdata job..."
kubectl wait --for=condition=complete "job/misarch-testdata" -n "$NAMESPACE" --timeout=900s

log "Waiting for core experiment pods..."
kubectl wait --for=condition=available deployment/misarch-experiment-executor -n "$NAMESPACE" --timeout=300s
kubectl wait --for=condition=available deployment/misarch-gatling-executor -n "$NAMESPACE" --timeout=300s
kubectl wait --for=condition=available deployment/misarch-gateway -n "$NAMESPACE" --timeout=300s

log "Seeding resilience shop (normal mode)..."
SHOP_MODE=normal "${ROOT_DIR}/scripts/seed-resilience-shop.sh"

log "Cluster ready for experiments."
