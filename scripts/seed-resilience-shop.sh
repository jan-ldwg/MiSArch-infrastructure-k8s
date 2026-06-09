#!/usr/bin/env bash
# Prepare shop catalog for resilience experiments (normal or low-stock mode).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHOP_MODE="${SHOP_MODE:-normal}"

log() { printf '%s\n' "$*" >&2; }

start_port_forwards() {
  if curl -sf http://localhost:8080/actuator/health >/dev/null 2>&1; then
    return
  fi
  log "Starting gateway + Keycloak port-forwards..."
  kubectl port-forward svc/misarch-gateway -n misarch 8080:8080 >/tmp/pf-gateway.log 2>&1 &
  kubectl port-forward svc/keycloak -n misarch 8081:80 >/tmp/pf-keycloak.log 2>&1 &
  local deadline=$((SECONDS + 30))
  while (( SECONDS < deadline )); do
    if curl -sf http://localhost:8080/actuator/health >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  log "Warning: gateway port-forward may not be ready"
}

main() {
  start_port_forwards

  local restock_batches restock_size skip_restock
  case "$SHOP_MODE" in
    low-stock)
      restock_batches=1
      restock_size=80
      skip_restock=false
      log "Shop mode: low-stock (~${restock_size} units per SKU)"
      ;;
    normal|*)
      restock_batches=5
      restock_size=1000
      skip_restock=true
      log "Shop mode: normal (SKIP_RESTOCK=true, existing catalog)"
      ;;
  esac

  GRAPHQL_ENDPOINT="${GRAPHQL_ENDPOINT:-http://localhost:8080/graphql}" \
  KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081/keycloak}" \
  RESTOCK_BATCHES="$restock_batches" \
  RESTOCK_BATCH_SIZE="$restock_size" \
  SKIP_RESTOCK="$skip_restock" \
    "${ROOT_DIR}/scripts/seed-flash-sale-catalog.sh"
}

main "$@"
