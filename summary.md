# Infrastructure Improvements

## Problem

Deploying the MiSArch microservice architecture on GKE resulted in cascading failures: Redis master entered CrashLoopBackOff due to a liveness probe killing the pod during RDB data loading from slow HDD storage. All databases subsequently failed as Dapr sidecars (20+ pods) lost connectivity to Redis, which served as the backbone for pub/sub messaging and state management. The entire observability pipeline spat connection errors because the OTEL collector was unreachable during the restart storm.

## Changes by File

### `main.tf` — Dual-Mode Provider Configuration

| Change | Reason |
|--------|--------|
| Kubernetes/helm/kubectl providers use `host`/`cluster_ca_certificate`/`token` (GCP) or `config_path`/`config_context` (local) conditional on `deployment_target` | GCP uses access_token + cluster endpoint from remote state; local uses minikube kubeconfig |
| GCP data sources (`terraform_remote_state`, `google_client_config`) use `count` conditional on `deployment_target` | Skipped entirely on local; prevents requiring GCS bucket credentials |
| Google provider uses `try()` for project/region | Gracefully handles absent remote state without crashing the plan |
| Helm provider uses `kubernetes = { host = ..., token = ..., config_path = ... }` argument syntax (conditional like kubernetes/kubectl) | Helm provider 3.x requires `kubernetes = { ... }` (argument with equals), not `kubernetes { ... }` (block) — the latter fails with "Unsupported block type" |

### `dapr.tf` — Redis Resilience + Dapr Connection Tuning

| Change | Reason |
|--------|--------|
| Redis `readinessProbe` re-enabled (`periodSeconds: 5, failureThreshold: 3`) | Redis binds port 6379 quickly; fast readiness lets services discover Redis endpoints immediately |
| Redis `livenessProbe` explicit config (`initialDelaySeconds: 60`) | 60s grace period to survive RDB snapshot reload (~8s observed); detects real failures quickly |
| Dapr `statestore` component: added `dialTimeout: 30s`, `readTimeout: 15s`, `writeTimeout: 15s`, `maxRetries: 5`, `maxRetryBackoff: 5` | Prevents immediate Dapr sidecar fatal-exit when Redis is temporarily unavailable; retries with backoff |
| Dapr `pubsub` + `experiment-config-pubsub` components: added `dialTimeout`, `maxRetries`, `maxRetryBackoff`, `publishRetryInterval` | Same resilience for pub/sub — transient Redis outages no longer crash Dapr sidecars. Note: `readTimeout` and `writeTimeout` intentionally omitted for pubsub because they kill Redis Stream blocking reads (XREAD BLOCK) |
| Dapr tracing `samplingRate` made configurable via `var.dapr_tracing_sampling_rate` | Allows disabling tracing export in local development or enabling it when a collector is present |

### `storage.tf` — Cross-Platform StorageClass

| Change | Reason |
|--------|--------|
| GCP `hdd` StorageClass made conditional (`count = var.create_gcp_storage_class ? 1 : 0`) | On minikube/kind, GCP's `pd.csi.storage.gke.io` provisioner doesn't exist; PVCs must bind to the platform's default StorageClass |
| `local.storage_class_name` wired to `var.storage_class_name` | Single source of truth; overridable per deployment target via tfvars |

### `dbs-mongodb.tf` — MongoDB Probe Fix

| Change | Reason |
|--------|--------|
| All 8 MongoDB instances now use `tcpSocket` probes on port 27017 instead of `mongosh` exec probes | The `mongosh` Node.js CLI spawn is too slow for 5s probe timeouts, causing liveness-probe kills → init container restart loops → CPU exhaustion from constant re-init |
| Probe configuration defined once as `local.mongodb_probe_config` | DRY: single definition injected into all 8 instances via heredoc interpolation |

### `variables-annotations.tf` — Dapr Sidecar Probe Tuning

| Change | Reason |
|--------|--------|
| `dapr.io/log-level` changed from hardcoded `debug` to `var.dapr_log_level` | Local dev uses `info` level (80% fewer log lines); GCP keeps `debug` for diagnostics |
| Sidecar liveness threshold: `10 → 3` | Fails fast when sidecar is truly unhealthy (30s kill instead of 150s) |
| Sidecar liveness delay: `10s → 30s` | Grace period after startup before liveness checks begin |
| Added `startup-probe` annotations (`threshold: 12, period: 10s`) | Sidecar gets 120s startup window; prevents premature kills during component initialization |
| Added explicit `period-seconds` for liveness/readiness | Previously relied on chart defaults; explicit is safer |

### `configmaps.tf` — Centralized OTEL Configuration

| Change | Reason |
|--------|--------|
| Base configmap (`base_misarch_env_vars`) now carries all OTEL env vars: `OTEL_LOG_LEVEL`, `OTEL_METRICS_EXPORTER`, `OTEL_TRACES_EXPORTER`, `OTEL_LOGS_EXPORTER`, and conditionally `OTEL_EXPORTER_OTLP_ENDPOINT` | Single source of truth for observability config across all services |
| `OTEL_EXPORTER_OTLP_ENDPOINT` removed from all 18 service-specific configmaps | Prevents per-service overrides and duplication; now controlled exclusively by the base configmap |
| `OTEL_EXPORTER_OTLP_ENDPOINT` uses `merge()` with conditional empty map — key is absent when `otel_disabled = true` | The Rust OTEL SDK creates an OTLP exporter when the key *exists* at all (even if set to empty string). Removing the key entirely is the only way to reliably disable export for Rust services. |

### `otel.tf` — Dual-Mode OTEL Collector

| Change | Reason |
|--------|--------|
| Split into two configurations via `var.otel_collector_mode`: GCP (Prometheus receiver + Prometheus exporter) and local (debug exporter, `verbosity: detailed`) | GCP needs Prometheus service discovery for Dapr metrics scraping; local needs a lightweight collector to accept OTLP data and silence log spam from services that try to export |
| Collector listen address: local mode uses `0.0.0.0:4318` instead of `$${MY_POD_IP}:4318` | Services that fall back to the Rust SDK default (`localhost:4318`) can reach the collector; pod IP binding would prevent localhost connections |
| `ClusterRole` + `ClusterRoleBinding` conditional on GCP mode (`count = var.otel_collector_mode == "gcp" ? 1 : 0`) | Prometheus service discovery requires cluster-level pod list/watch RBAC; not needed for the debug exporter |
| Collector `telemetry.logs.level`: `debug` locally, `error` on GCP | The debug exporter's output is logged at the collector's own log level; must be at least `debug` for `verbosity: detailed` to produce visible output |

### `variables-misc.tf` — 9 New Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `deployment_target` | `"gcp"` | Switch between GCP and local provider configurations |
| `storage_class_name` | `"standard"` | Override StorageClass for local environments |
| `create_gcp_storage_class` | `false` | Conditionally create GCP-specific `hdd` class |
| `dapr_log_level` | `"debug"` | Control Dapr sidecar verbosity |
| `otel_log_level` | `"info"` | Set OTEL log level via env vars |
| `otel_disabled` | `false` | Disable OTEL export entirely |
| `dapr_tracing_sampling_rate` | `"1"` | Control Dapr trace sampling (0 = off, 1 = 100%) |
| `otel_collector_mode` | `"gcp"` | Switch between GCP (Prometheus) and local (debug exporter) collector config |

`cluster_bucket_id` and `cluster_bucket_prefix` given empty-string defaults so they are not required for local deployments.

## Deployment Instructions

### Prerequisites

- Terraform >= 1.5
- kubectl configured for your target cluster
- Dapr initialized (`dapr init -k`)

---

### Option A: Full Cluster on GCP

**Step 1: Provision the GKE cluster**

```sh
cd cluster
terraform init
terraform apply
```

This creates the GKE cluster, node pool, and outputs the cluster endpoint, CA certificate, and project metadata to a GCS backend bucket.

**Step 2: Install MiSArch**

```sh
cd ..  # back to root
terraform init
terraform apply -var-file=main-deployment.tfvars
```

This deploys all 20+ microservices, databases, Redis, Dapr, ingress, monitoring stack, and the OTEL collector to the GKE cluster. Takes 5-10 minutes.

**Step 3: Access the application**

```sh
terraform output global_domain
```

Open the printed URL in a browser. Default credentials: `admin` / `admin` (Keycloak).

**Step 4: Seed test data** (runs automatically as a Kubernetes Job during apply; re-run if needed)

```sh
kubectl delete job misarch-testdata -n misarch
terraform apply -var-file=main-deployment.tfvars
```

---

### Option B: Single Service Locally (Minikube)

**Step 1: Start minikube**

```sh
minikube start --cpus=4 --memory=8192
```

**Step 2: Deploy a single service with dependencies**

The `-target` flag deploys only the selected resources and their dependencies. Replace `<service>` below with any service name (e.g., `order`, `catalog`, `address`, `payment`, etc.).

```sh
terraform init
terraform apply -var-file=local-dev.tfvars \
  -target=kubernetes_namespace.misarch \
  -target=helm_release.dapr \
  -target=helm_release.redis \
  -target=helm_release.misarch_<service>_db \
  -target=helm_release.otel-collector \
  -target=terraform_data.dapr \
  -target=kubernetes_config_map.base_misarch_env_vars \
  -target=kubernetes_config_map.misarch_<service>_env_vars \
  -target=kubernetes_config_map.misarch_<service>_ecs_env_vars \
  -target=module.misarch_<service>
```
> **Note:** Service deployments are defined via the `modules/misarch-service` module. Target the module (`module.misarch_<service>`) instead of the raw `kubernetes_deployment` resource.

**Example — deploy the order service:**

```sh
terraform apply -var-file=local-dev.tfvars \
  -target=kubernetes_namespace.misarch \
  -target=helm_release.dapr \
  -target=helm_release.redis \
  -target=helm_release.misarch_order_db \
  -target=helm_release.otel-collector \
  -target=terraform_data.dapr \
  -target=kubernetes_config_map.base_misarch_env_vars \
  -target=kubernetes_config_map.misarch_order_env_vars \
  -target=kubernetes_config_map.misarch_order_ecs_env_vars \
  -target=module.misarch_order
```

**Step 3: Verify the service is running**

```sh
kubectl get pods -n misarch
# Expected: services/deps show 1/1 or 2/2 or 3/3 Running
```

**Step 4: View telemetry**

```sh
kubectl logs -f -n misarch -l app.kubernetes.io/name=opentelemetry-collector
```

Shows traces from Dapr and metrics from the service. Filter with:
```sh
# Traces only
kubectl logs -n misarch -l app.kubernetes.io/name=opentelemetry-collector --tail=50 | grep '"traces"'

# Metrics only
kubectl logs -n misarch -l app.kubernetes.io/name=opentelemetry-collector --tail=50 | grep '"metrics"'
```

**Step 5: Access the service**

Each service exposes its HTTP API internally via Dapr. For the order service:

```sh
# Port-forward the Dapr HTTP port
kubectl port-forward -n misarch deploy/misarch-order 3500:3500

# Invoke via Dapr
curl http://localhost:3500/v1.0/invoke/order/method/health
```

**Step 6: Clean up**

```sh
terraform destroy -var-file=local-dev.tfvars
minikube stop
```

---

### Option C: Running Any Set of Services Locally (General Pattern)

The `-target` list for any service follows a fixed template. Replace `<name>` with the service name (e.g., `order`, `catalog`, `address`, `payment`, etc.):

#### Base infrastructure (always needed)
```
-target=kubernetes_namespace.misarch
-target=helm_release.dapr
-target=helm_release.redis
-target=helm_release.otel-collector
-target=terraform_data.dapr
-target=kubernetes_config_map.base_misarch_env_vars
```

#### Per-service resources (repeat for each <name>)
```
-target=helm_release.misarch_<name>_db
-target=kubernetes_config_map.misarch_<name>_env_vars
-target=kubernetes_config_map.misarch_<name>_ecs_env_vars
-target=module.misarch_<name>
```

#### Full command template
```sh
terraform apply -var-file=local-dev.tfvars \
  -target=kubernetes_namespace.misarch \
  -target=helm_release.dapr \
  -target=helm_release.redis \
  -target=helm_release.otel-collector \
  -target=terraform_data.dapr \
  -target=kubernetes_config_map.base_misarch_env_vars \
  -target=helm_release.misarch_<NAME1>_db \
  -target=kubernetes_config_map.misarch_<NAME1>_env_vars \
  -target=kubernetes_config_map.misarch_<NAME1>_ecs_env_vars \
  -target=module.misarch_<NAME1> \
  -target=helm_release.misarch_<NAME2>_db \
  -target=kubernetes_config_map.misarch_<NAME2>_env_vars \
  -target=kubernetes_config_map.misarch_<NAME2>_ecs_env_vars \
  -target=module.misarch_<NAME2>
```

#### Quick reference — service names

| Service | DB type | Command substitution |
|---------|---------|---------------------|
| address | PostgreSQL | `misarch_address_db` |
| catalog | PostgreSQL | `misarch_catalog_db` |
| discount | PostgreSQL | `misarch_discount_db` |
| inventory | MongoDB | `misarch_inventory_db` |
| invoice | MongoDB | `misarch_invoice_db` |
| media | MongoDB | `misarch_media_db` |
| notification | PostgreSQL | `misarch_notification_db` |
| order | MongoDB | `misarch_order_db` |
| payment | MongoDB | `misarch_payment_db` |
| return | PostgreSQL | `misarch_return_db` |
| review | MongoDB | `misarch_review_db` |
| shipment | PostgreSQL | `misarch_shipment_db` |
| shoppingcart | MongoDB | `misarch_shoppingcart_db` |
| tax | PostgreSQL | `misarch_tax_db` |
| user | PostgreSQL | `misarch_user_db` |
| wishlist | MongoDB | `misarch_wishlist_db` |

#### Example — deploy order, catalog, and payment:
```sh
terraform apply -var-file=local-dev.tfvars \
  -target=kubernetes_namespace.misarch \
  -target=helm_release.dapr \
  -target=helm_release.redis \
  -target=helm_release.otel-collector \
  -target=terraform_data.dapr \
  -target=kubernetes_config_map.base_misarch_env_vars \
  -target=helm_release.misarch_order_db \
  -target=kubernetes_config_map.misarch_order_env_vars \
  -target=kubernetes_config_map.misarch_order_ecs_env_vars \
  -target=module.misarch_order \
  -target=helm_release.misarch_catalog_db \
  -target=kubernetes_config_map.misarch_catalog_env_vars \
  -target=kubernetes_config_map.misarch_catalog_ecs_env_vars \
  -target=module.misarch_catalog \
  -target=helm_release.misarch_payment_db \
  -target=kubernetes_config_map.misarch_payment_env_vars \
  -target=kubernetes_config_map.misarch_payment_ecs_env_vars \
  -target=module.misarch_payment
```

#### Minimal resource footprint

| Service count | Deployments | DBs | Target lines |
|---------------|-------------|-----|-------------|
| 1 service | 1 | 1 | 10 |
| 2 services | 2 | 2 | 14 |
| 3 services | 3 | 3 | 18 |
| N services | N | N | 6 + 4×N |

### Testing Services Locally via Dapr

Once services are deployed, invoke them through the Dapr sidecar. This works identically for any service — only the `app_id` (service name) and GraphQL query change.

#### 1. Port-forward the Dapr sidecar

```sh
# Replace <service> with the service name (e.g., catalog, order, address)
kubectl port-forward -n misarch deploy/misarch-<service> 3500:3500
```

#### 2. Verify Dapr health

```sh
curl http://localhost:3500/v1.0/healthz
# Expected: empty 204 response (HTTP success)
```

#### 3. Invoke the service via Dapr

Dapr routes requests using the pattern `/v1.0/invoke/<app-id>/method/<path>`. The `app-id` is defined in the Dapr annotation (`dapr.io/app-id` in `variables-annotations.tf`).

**Catalog (GraphQL — gets all categories):**

```sh
curl -s -X POST http://localhost:3500/v1.0/invoke/catalog/method/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ categories(first: 5) { nodes { id name } } }"}' | python3 -m json.tool
```

**Order (GraphQL — query order by ID):**

```sh
curl -s -X POST http://localhost:3500/v1.0/invoke/order/method/graphql \
  -H "Content-Type: application/json" \
  -d '{"query": "{ order(id: \"some-id\") { id status } }"}'
```

**Address (Spring Boot — actuator health):**

```sh
curl http://localhost:3500/v1.0/invoke/address/method/health
# Returns Spring Boot Actuator health status
```

#### 4. Expected results

- **Empty data**: The services respond with valid GraphQL responses but return empty collections (`nodes: []`). This is expected — no test data has been seeded locally. The Flyway migrations created the schema, but the `testdata` Kubernetes Job (which populates products, categories, tax rates, etc.) depends on Keycloak and the gateway service, which are not deployed in minimal local testing.
- **No errors**: The response should be valid JSON with `"data"` (not `"errors"`). If you see `"errors"`, check `kubectl logs deploy/misarch-<service> -n misarch -c misarch-<service> --tail=30`.

#### 5. List subscriptions (pubsub topics the service listens to)

```sh
curl http://localhost:3500/v1.0/invoke/<app-id>/method/dapr/subscribe
```

This returns the list of pubsub topics the service is subscribed to, useful for verifying the messaging layer is correctly configured.

### local-dev.tfvars Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `deployment_target` | `"local"` | Uses minikube kubeconfig context |
| `ROOT_DOMAIN` | `"http://localhost:8080"` | No cloud LB available |
| `storage_class_name` | `"standard"` | minikube's default StorageClass |
| `create_gcp_storage_class` | `false` | Skip GCP CSI provisioner |
| `dapr_log_level` | `"info"` | Reduce Dapr log noise |
| `otel_log_level` | `"error"` | Minimal OTEL log output |
| `otel_disabled` | `false` | OTEL enabled (local collector deployed) |
| `otel_collector_mode` | `"local"` | Debug exporter, no Prometheus RBAC |
| `dapr_tracing_sampling_rate` | `"1"` | Full Dapr trace capture |

## Probe Testing

The `misarch-service` module adds startup, liveness, and readiness probes to every deployment. You can verify they work correctly:

### Setup: separate liveness path

The module supports a separate `liveness_probe_path` (defaults to `probe_path`) so liveness can be tested independently without breaking readiness (which would cause `terraform apply` to hang on `wait_for_rollout`).

**Temporarily edit the module call** for any service to override:

```hcl
  liveness_probe_path             = "/nonexistent"
  liveness_initial_delay_seconds  = 10
```

Then apply:

```sh
terraform apply -var-file=local-dev.tfvars -target=module.misarch_<service> -auto-approve
```

### What happens

| Step | Prob | Path | Result |
|---|---|---|---|
| Pod starts | Startup | `/health` | Passes after boot → liveness/readiness activated |
| Rollout | Readiness | `/health` | Pod becomes Ready → Terraform apply completes |
| ~10s after startup | Liveness | `/nonexistent` | 404 response → fails 3× → **container killed** |

```sh
# Watch for the restart:
kubectl get pods -n misarch -l app=misarch-<service> -w

# Expected: 3/3 Running → 2/3 Running → restarts increment → cycle repeats
```

Verify via events:

```sh
kubectl describe pod -n misarch -l app=misarch-<service> | grep -E "Liveness probe failed|Killing"
# Expected: "Container misarch-<service> failed liveness probe, will be restarted"
```

### Revert

Remove the two override lines and re-apply. The pod returns to stable `3/3 Running`.

---

## What Remains Unresolved

- **Rust OTEL SDK debug logs**: The order service (and other Rust-based services) hardcodes its OTEL SDK at DEBUG level. The `OTEL_LOG_LEVEL` and `RUST_LOG` env vars are ignored by the compiled binary. Internal SDK status messages (e.g., `PeriodReaderThreadExportingDueToTimer`, `pooling idle connection`) appear every 5 seconds. Fix requires a code change in the service binaries, not IaC.

- **ECS sidecar heartbeat failures at startup**: The experiment-config sidecar tries to publish heartbeats via Dapr before the Dapr sidecar is fully initialized. Self-resolves within seconds. Non-fatal startup race condition.

- **Pre-existing configmap typos**: Several service configmaps hardcode `OTEL_SERVICE_NAME = "payment"` instead of their actual service name (e.g., inventory, gateway, simulation). Not related to these changes.
