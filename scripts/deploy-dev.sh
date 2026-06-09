#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORM_DIR="${ROOT_DIR}/terraform/gcp-dev"
APP_DIR="${ROOT_DIR}"

ACTION="${1:-apply}"
EXTRA_ARGS=("${@:2}")

log() {
  printf '==> %s\n' "$*"
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_adc() {
  if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
    echo "Application Default Credentials are required for the GCS Terraform backend." >&2
    echo "Run: gcloud auth application-default login" >&2
    exit 1
  fi
}

project_id() {
  gcloud config get-value project 2>/dev/null | tr -d '\n'
}

state_bucket() {
  local project
  project="$(project_id)"
  if [[ -z "${project}" || "${project}" == "(unset)" ]]; then
    echo "gcloud project is not set. Run: gcloud config set project YOUR_PROJECT_ID" >&2
    exit 1
  fi
  echo "${project}-terraform-state"
}

platform_terraform() {
  export TF_VAR_project_id="$(project_id)"
  local -a var_file_args=()
  if [[ -f "${PLATFORM_DIR}/dev.tfvars" ]]; then
    var_file_args=(-var-file="${PLATFORM_DIR}/dev.tfvars")
  fi
  terraform -chdir="${PLATFORM_DIR}" "$@" \
    ${var_file_args+"${var_file_args[@]}"} \
    ${EXTRA_ARGS+"${EXTRA_ARGS[@]}"}
}

write_backend_config() {
  local target_dir="$1"
  local prefix="$2"
  local bucket
  bucket="$(state_bucket)"

  cat > "${target_dir}/backend.gcs.hcl" <<EOF
bucket = "${bucket}"
prefix = "${prefix}"
EOF
}

ensure_platform_backend() {
  write_backend_config "${PLATFORM_DIR}" "gcp-dev"
}

ensure_app_backend() {
  write_backend_config "${APP_DIR}" "misarch-k8s"
}

app_terraform() {
  terraform -chdir="${APP_DIR}" "$@" ${EXTRA_ARGS+"${EXTRA_ARGS[@]}"}
}

bootstrap_platform() {
  require_adc
  local bucket project
  bucket="$(state_bucket)"
  project="$(project_id)"

  log "Bootstrapping GCS state bucket gs://${bucket}"
  ensure_platform_backend

  gcloud services enable storage.googleapis.com --project="${project}" >/dev/null

  if ! gcloud storage buckets describe "gs://${bucket}" --project="${project}" >/dev/null 2>&1; then
    gcloud storage buckets create "gs://${bucket}" \
      --project="${project}" \
      --location=europe-west3 \
      --uniform-bucket-level-access
    gcloud storage buckets update "gs://${bucket}" --versioning
  fi

  terraform -chdir="${PLATFORM_DIR}" init -backend-config="${PLATFORM_DIR}/backend.gcs.hcl" -reconfigure
}

init_platform() {
  require_adc
  ensure_platform_backend
  if gcloud storage buckets describe "gs://$(state_bucket)" >/dev/null 2>&1; then
    terraform -chdir="${PLATFORM_DIR}" init -backend-config="${PLATFORM_DIR}/backend.gcs.hcl"
  else
    log "State bucket not found; running bootstrap first"
    bootstrap_platform
  fi
}

init_app() {
  require_adc
  ensure_app_backend
  if ! gcloud storage buckets describe "gs://$(state_bucket)" >/dev/null 2>&1; then
    echo "State bucket gs://$(state_bucket) does not exist. Run: ./scripts/deploy-dev.sh bootstrap" >&2
    exit 1
  fi
  app_terraform init -backend-config="${APP_DIR}/backend.gcs.hcl"
}

platform_output() {
  local name="$1"
  local default="${2:-}"
  local value=""
  value="$(platform_terraform output -raw "${name}" 2>/dev/null || true)"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf '%s' "${default}"
  fi
}

cluster_exists() {
  local cluster region project
  project="$(project_id)"
  region="$(platform_output region "europe-west3")"
  cluster="$(platform_output cluster_name "misarch-cluster")"

  [[ -n "${project}" && "${project}" != "(unset)" && -n "${cluster}" ]] || return 1
  gcloud container clusters describe "${cluster}" \
    --region "${region}" \
    --project "${project}" >/dev/null 2>&1
}

configure_kubeconfig() {
  local cluster region project
  project="$(project_id)"
  region="$(platform_output region "europe-west3")"
  cluster="$(platform_output cluster_name "misarch-cluster")"

  if [[ -z "${project}" || "${project}" == "(unset)" ]]; then
    echo "gcloud project is not set. Run: gcloud config set project YOUR_PROJECT_ID" >&2
    return 1
  fi

  if ! cluster_exists; then
    log "Cluster ${cluster} not found in ${project}; skipping kubeconfig"
    return 1
  fi

  log "Fetching kubeconfig for cluster ${cluster}"
  gcloud container clusters get-credentials "${cluster}" \
    --region "${region}" \
    --project "${project}"

  export TF_VAR_KUBERNETES_CONFIG_PATH="${KUBECONFIG:-${HOME}/.kube/config}"
  export TF_VAR_ROOT_DOMAIN="$(platform_output root_domain_url "")"
  if [[ -n "${TF_VAR_ROOT_DOMAIN}" ]]; then
    log "TF_VAR_ROOT_DOMAIN=${TF_VAR_ROOT_DOMAIN}"
  fi
}

disable_cluster_deletion_protection() {
  local cluster region project
  project="$(project_id)"
  region="$(platform_output region "europe-west3")"
  cluster="$(platform_output cluster_name "misarch-cluster")"

  if ! cluster_exists; then
    log "Cluster not found; skipping deletion protection update"
    return 0
  fi

  log "Disabling GKE deletion protection (required before cluster destroy)"
  if platform_terraform apply \
    -target=google_container_cluster.primary \
    -auto-approve; then
    return 0
  fi

  log "Terraform update failed; disabling deletion protection via gcloud"
  gcloud container clusters update "${cluster}" \
    --region "${region}" \
    --project "${project}" \
    --no-deletion-protection
}

destroy_app_stack() {
  if ! configure_kubeconfig; then
    log "Skipping app stack destroy (cluster unavailable)"
    return 0
  fi

  if ! command -v kubectl >/dev/null 2>&1; then
    log "kubectl not found; skipping app stack destroy"
    return 0
  fi

  init_app

  log "Destroying MiSArch application stack"
  if app_terraform destroy -auto-approve; then
    log "App stack destroyed"
    return 0
  fi

  log "App destroy failed; attempting namespace cleanup"
  kubectl delete namespace misarch --ignore-not-found --wait=true || true
}

init_submodules() {
  log "Initializing git submodules (Keycloak realm template)"
  git -C "${ROOT_DIR}" submodule update --init --recursive
}

cleanup_orphan_disks() {
  local region project
  region="$(platform_output region "europe-west3")"
  project="$(project_id)"

  log "Checking for orphan PVC disks in ${region}"
  local disks_output
  disks_output="$(gcloud compute disks list \
    --project "${project}" \
    --filter="name~'^pvc-' AND region~'${region}' AND -users:*" \
    --format="value(name,zone)" 2>/dev/null || true)"

  if [[ -z "${disks_output}" ]]; then
    log "No orphan PVC disks found"
    return
  fi

  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    local name zone
    name="${entry%% *}"
    zone="${entry#* }"
    log "Deleting orphan disk ${name} in ${zone}"
    gcloud compute disks delete "${name}" --zone "${zone}" --project "${project}" --quiet
  done <<< "${disks_output}"
}

do_verify() {
  require_cmd terraform
  log "Validating platform Terraform"
  terraform -chdir="${PLATFORM_DIR}" init -backend=false -reconfigure >/dev/null
  terraform -chdir="${PLATFORM_DIR}" validate
  log "Validating application Terraform"
  terraform -chdir="${APP_DIR}" init -backend=false -reconfigure >/dev/null
  terraform -chdir="${APP_DIR}" validate
  log "Configuration validation passed"
}

do_plan() {
  require_cmd terraform
  require_cmd gcloud
  require_adc

  init_platform
  platform_terraform plan

  if kubectl config current-context >/dev/null 2>&1; then
    init_app
    configure_kubeconfig
    init_submodules
    app_terraform plan
  else
    log "Skipping app plan until platform exists and kubeconfig is available"
  fi
}

do_apply() {
  require_cmd terraform
  require_cmd gcloud
  require_cmd kubectl
  require_cmd helm
  require_adc

  init_platform
  platform_terraform apply -auto-approve
  configure_kubeconfig
  init_submodules
  init_app
  app_terraform apply -auto-approve

  log "Deployment complete"
  log "Frontend URL: $(platform_terraform output -raw root_domain_url)"
  log "Keycloak URL: $(platform_terraform output -raw root_domain_url)/keycloak"
  log "Ingress IP: $(platform_terraform output -raw ingress_external_ip)"
  log "Note: HTTPS uses a self-signed certificate; accept the browser warning for dev."
}

do_destroy() {
  require_cmd terraform
  require_cmd gcloud
  require_adc

  if [[ -z "$(project_id)" || "$(project_id)" == "(unset)" ]]; then
    echo "gcloud project is not set. Run: gcloud config set project YOUR_PROJECT_ID" >&2
    exit 1
  fi

  init_platform
  destroy_app_stack
  disable_cluster_deletion_protection

  log "Destroying GCP platform stack"
  platform_terraform destroy -auto-approve

  cleanup_orphan_disks
  log "Destroy complete"
}

usage() {
  cat <<EOF
Usage: $(basename "$0") [bootstrap|verify|plan|apply|destroy|unlock LOCK_ID]

  bootstrap  Create the GCS state bucket and initialize Terraform remote state
  verify     Validate both Terraform stacks (no GCP changes)
  plan       Plan platform and app Terraform changes
  apply      Apply platform, configure kubeconfig, apply app stack
  destroy    Destroy app stack, platform stack, and orphan PVC disks
  unlock     Release a stale platform Terraform state lock (ID from error output)

Environment:
  KUBECONFIG  Path to kubeconfig (default: ~/.kube/config)

Prerequisites:
  gcloud, terraform, kubectl, helm, gke-gcloud-auth-plugin
  gcloud auth application-default login
EOF
}

case "${ACTION}" in
  bootstrap)
    require_cmd terraform
    require_cmd gcloud
    require_adc
    bootstrap_platform
    ensure_app_backend
    log "Bootstrap complete. Next: ./scripts/deploy-dev.sh apply"
    ;;
  verify)
    do_verify
    ;;
  plan)
    do_plan
    ;;
  apply)
    do_apply
    ;;
  destroy)
    do_destroy
    ;;
  unlock)
    require_cmd terraform
    require_adc
    init_platform
    lock_id="${2:-}"
    if [[ -z "${lock_id}" ]]; then
      echo "Usage: $(basename "$0") unlock LOCK_ID" >&2
      echo "Use the ID from 'Error acquiring the state lock' (e.g. ./scripts/deploy-dev.sh unlock 1780841827377398)" >&2
      exit 1
    fi
    platform_terraform force-unlock -force "${lock_id}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    echo "Unknown action: ${ACTION}" >&2
    usage
    exit 1
    ;;
esac
