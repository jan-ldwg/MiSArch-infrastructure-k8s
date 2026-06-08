#!/usr/bin/env bash
# Seed flash-sale catalog and ensure the Gatling load-test user can complete checkout.
set -euo pipefail

GRAPHQL_ENDPOINT="${GRAPHQL_ENDPOINT:-http://localhost:8080/graphql}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8081/keycloak}"
REALM="${REALM:-Misarch}"
CLIENT_ID="${CLIENT_ID:-frontend}"
GATLING_USERNAME="${GATLING_USERNAME:-gatling}"
GATLING_PASSWORD="${GATLING_PASSWORD:-123}"
GRANT_TYPE="${GRANT_TYPE:-password}"
RESTOCK_BATCH_SIZE="${RESTOCK_BATCH_SIZE:-1000}"
RESTOCK_BATCHES="${RESTOCK_BATCHES:-50}"
SKIP_RESTOCK="${SKIP_RESTOCK:-false}"

log() { printf '%s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

require_cmd curl
require_cmd jq

get_token() {
  local token
  token=$(curl -sf -X POST "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=${GRANT_TYPE}" \
    -d "client_id=${CLIENT_ID}" \
    -d "username=${GATLING_USERNAME}" \
    -d "password=${GATLING_PASSWORD}" | jq -r '.access_token')
  [[ -n "$token" && "$token" != "null" ]] || die "Failed to obtain access token from Keycloak"
  echo "$token"
}

gql() {
  local query="$1"
  curl -sf -X POST "$GRAPHQL_ENDPOINT" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $AUTH_TOKEN" \
    -d "$(jq -n --arg query "$query" '{query: $query}')"
}

gql_data() {
  gql "$1" | jq -r '.data'
}

ensure_gatling_address() {
  local user_id address_count
  user_id=$(gql_data 'query { currentUser { id } }' | jq -r '.currentUser.id')
  address_count=$(gql_data 'query { currentUser { addresses(filter: { isArchived: false }) { totalCount } } }' \
    | jq -r '.currentUser.addresses.totalCount')

  if [[ "$address_count" == "0" ]]; then
    log "Creating shipping address for Gatling user ${user_id}..."
    gql_data "mutation { createUserAddress(input:{ city: \"Stuttgart\", companyName: \"Flash Sale Shopper\", country: \"Germany\", postalCode: \"70569\", street1: \"Sale Strasse\", street2: \"1\", userId: \"${user_id}\" }) { id } }" \
      | jq -e '.createUserAddress.id' >/dev/null
    log "Address created."
  else
    log "Gatling user already has ${address_count} active address(es)."
  fi

  local payment_count
  payment_count=$(gql_data 'query { currentUser { paymentInformations { totalCount } } }' \
    | jq -r '.currentUser.paymentInformations.totalCount')
  [[ "$payment_count" != "0" ]] || die "Gatling user has no payment methods; run misarch-testdata job first"
  log "Gatling user has ${payment_count} payment method(s)."
}

ensure_tax_rate() {
  local tax_rate_id
  tax_rate_id=$(gql_data 'query { taxRates { nodes { id } } }' | jq -r '.taxRates.nodes[0].id // empty')
  if [[ -z "$tax_rate_id" ]]; then
    log "Creating VAT tax rate..."
    tax_rate_id=$(gql_data 'mutation { createTaxRate(input: { description: "VAT", initialVersion: { rate: 19.0 }, name: "VAT" }) { id } }' \
      | jq -r '.createTaxRate.id')
  fi
  echo "$tax_rate_id"
}

ensure_flash_sale_category() {
  local category_id characteristic_id
  category_id=$(gql_data 'query { categories { nodes { id name } } }' \
    | jq -r '.categories.nodes[] | select(.name == "Flash Sale") | .id' | head -1)
  if [[ -n "$category_id" ]]; then
    log "Reusing Flash Sale category ${category_id}"
  else
    log "Creating Flash Sale category..."
    category_id=$(gql_data 'mutation { createCategory(input: { categoricalCharacteristics: { name: "Electronics", description: "Electronics" }, description: "Limited-time flash sale offers", name: "Flash Sale", numericalCharacteristics: [] }) { id } }' \
      | jq -r '.createCategory.id')
    log "Category created: ${category_id}"
  fi
  characteristic_id=$(gql_data "query { category(id: \"${category_id}\") { characteristics { nodes { id } } } }" \
    | jq -r '.category.characteristics.nodes[0].id')
  echo "${category_id}|${characteristic_id}"
}

create_product_if_missing() {
  local internal_name="$1"
  local display_name="$2"
  local price="$3"
  local category_id="$4"
  local characteristic_id="$5"
  local tax_rate_id="$6"

  local existing variant_id
  existing=$(gql_data 'query { products(first: 50, orderBy: { direction: DESC, field: ID }) { nodes { internalName defaultVariant { id } } } }' \
    | jq -r --arg name "$internal_name" '.products.nodes[] | select(.internalName == $name) | .defaultVariant.id' | head -1)

  if [[ -n "$existing" ]]; then
    log "Product ${internal_name} already exists (variant ${existing})"
    echo "$existing"
    return
  fi

  log "Creating product ${internal_name} (${display_name})..."
  variant_id=$(gql_data "mutation { createProduct(input: { categoryIds: [\"${category_id}\"], defaultVariant: { initialVersion: { canBeReturnedForDays: 30, categoricalCharacteristicValues: { characteristicId: \"${characteristic_id}\", value: \"Flash Sale\" }, description: \"${display_name}\", name: \"${display_name}\", numericalCharacteristicValues: [], retailPrice: ${price}, taxRateId: \"${tax_rate_id}\", weight: 0.5, mediaIds: [] }, isPubliclyVisible: true }, internalName: \"${internal_name}\", isPubliclyVisible: true }) { defaultVariant { id } } }" \
    | jq -r '.createProduct.defaultVariant.id')

  [[ -n "$variant_id" && "$variant_id" != "null" ]] || die "Failed to create product ${internal_name}"
  echo "$variant_id"
}

restock_variant() {
  local variant_id="$1"
  local label="$2"
  if [[ "$SKIP_RESTOCK" == "true" ]]; then
    log "Skipping restock for ${label} (SKIP_RESTOCK=true)"
    return
  fi
  log "Restocking ${label} (${variant_id}) to ~$((RESTOCK_BATCH_SIZE * RESTOCK_BATCHES)) units..."
  local i
  for ((i = 1; i <= RESTOCK_BATCHES; i++)); do
    gql_data "mutation { createProductItemBatch(input:{ productVariantId: \"${variant_id}\", number: ${RESTOCK_BATCH_SIZE} }) { id } }" >/dev/null
  done
  log "Restock complete for ${label}."
}

main() {
  log "Flash-sale catalog seed"
  log "GraphQL endpoint: ${GRAPHQL_ENDPOINT}"

  AUTH_TOKEN=$(get_token)
  ensure_gatling_address

  local tax_rate_id category_info category_id characteristic_id
  tax_rate_id=$(ensure_tax_rate)
  category_info=$(ensure_flash_sale_category)
  category_id="${category_info%%|*}"
  characteristic_id="${category_info##*|}"

  local products=(
    "FLASH_HEADPHONES|Wireless Headphones|29"
    "FLASH_SMARTWATCH|Smart Watch Bundle|49"
    "FLASH_SPEAKER|Bluetooth Speaker|19"
    "FLASH_GAMING_KIT|Gaming Starter Kit|39"
  )

  local entry internal_name display_name price variant_id
  for entry in "${products[@]}"; do
    IFS='|' read -r internal_name display_name price <<< "$entry"
    variant_id=$(create_product_if_missing "$internal_name" "$display_name" "$price" "$category_id" "$characteristic_id" "$tax_rate_id")
    restock_variant "$variant_id" "$internal_name"
  done

  log "Verifying newest public products..."
  gql_data 'query { products(filter: { isPubliclyVisible: true }, first: 5, orderBy: { direction: DESC, field: ID }) { nodes { internalName id } } }' \
    | jq -r '.products.nodes[] | "  - \(.internalName) (\(.id))"'

  log "Flash-sale catalog seed complete."
}

main "$@"
