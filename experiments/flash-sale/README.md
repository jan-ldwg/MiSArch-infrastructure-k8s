# Flash-Sale Load Experiment

Simulates a marketing flash sale on the MiSArch platform: **50 users/s baseline → 500 users/s peak (60s) → 50 users/s**, using the experiment stack (Gatling executor → GraphQL gateway → InfluxDB → Grafana).

## Prerequisites

- GKE cluster deployed with MiSArch stack (`./scripts/deploy-dev.sh apply`)
- `misarch-testdata` job completed (`kubectl get job misarch-testdata -n misarch`)
- Core pods running: `misarch-experiment-executor`, `misarch-gatling-executor`, `misarch-gateway`, `influxdb`
- Tools: `kubectl`, `curl`, `jq`, `python3`

## Quick start

```sh
# 1. Port-forward gateway + Keycloak (in separate terminals or background)
kubectl port-forward svc/misarch-gateway -n misarch 8080:8080
kubectl port-forward svc/keycloak -n misarch 8081:80

# 2. Seed flash-sale catalog
chmod +x scripts/seed-flash-sale-catalog.sh scripts/run-flash-sale-experiment.sh
GRAPHQL_ENDPOINT=http://localhost:8080/graphql KEYCLOAK_URL=http://localhost:8081/keycloak \
  ./scripts/seed-flash-sale-catalog.sh

# 3. Run the experiment (~4–6 min including Gatling compile)
./scripts/run-flash-sale-experiment.sh
```

Override API URL if needed:

```sh
EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment ./scripts/run-flash-sale-experiment.sh
```

## Load profile

| Phase | Seconds | Users/s (buy scenario) | Users/s (browse scenario) |
|-------|---------|------------------------|---------------------------|
| Pre-sale baseline | 0–59 | 50 | ~10 |
| Ramp up | 60–74 | 50 → 500 | ~10 → ~100 |
| Flash sale peak | 75–134 | 500 | ~100 |
| Ramp down | 135–149 | 500 → 50 | ~100 → ~10 |
| Post-sale baseline | 150–209 | 50 | ~10 |

Total duration: **210 seconds** per scenario.

## User journeys

- **`flashSaleBuyProcess`** (~85%): login → browse newest products → product detail → cart → checkout → place order
- **`flashSaleBrowseOnly`** (~15%): login → browse → product detail → add to cart → abandon

Both scenarios target in-cluster services and prefer newest public products (`orderBy: ID DESC`) so flash-sale SKUs are hit first.

## Catalog seeded

| SKU | Product | Price |
|-----|---------|-------|
| FLASH_HEADPHONES | Wireless Headphones | €29 |
| FLASH_SMARTWATCH | Smart Watch Bundle | €49 |
| FLASH_SPEAKER | Bluetooth Speaker | €19 |
| FLASH_GAMING_KIT | Gaming Starter Kit | €39 |

Each SKU is restocked to **50,000 units** by default (`1000 × 50` batches).

## Verification checklist

| Check | Command / signal |
|-------|------------------|
| Experiment starts | `run-flash-sale-experiment.sh` prints HTTP 200 on start |
| Gatling runs | `kubectl logs -n misarch deploy/misarch-gatling-executor \| grep -i trigger` |
| Load spike | Grafana dashboard URL in script output or `/tmp/flash-sale-experiment-events.log` |
| Metrics in InfluxDB | Experiment executor writes to bucket `gatling` (configured in `configmaps.tf`) |
| Shop traffic | Gateway/shoppingcart CPU rises during seconds 60–134 |

Grafana (port-forward):

```sh
kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
# user: admin  password: kubectl get secret -n misarch prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
```

Experiment UI: `https://<INGRESS_IP>/frontend/`

## Viewing and exporting results

After a run completes, metrics are stored in **InfluxDB** (bucket `gatling`, org `misarch`) tagged with `testUUID` and `testVersion`. The run script also exports a local snapshot under `experiments/flash-sale/results/` (gitignored).

### 1. Local export (recommended for analysis)

```sh
TEST_UUID=<uuid> TEST_VERSION=v1 ./scripts/export-experiment-results.sh
# or automatically after a successful run via run-flash-sale-experiment.sh
```

Each export directory contains `manifest.json`, API configs, `usersteps-*.csv`, `influxdb-metrics.csv`, `influxdb-summary.json`, and log snippets.

### 2. InfluxDB (primary metrics store)

```sh
kubectl port-forward svc/influxdb -n misarch 8086:8086
terraform output -raw influxdb_admin_token   # or secret influxdb-admin-token
```

Example Flux query:

```flux
from(bucket:"gatling")
  |> range(start: -24h)
  |> filter(fn: (r) => r.testUUID == "f539bdee-22cc-4ef2-91ba-602e72e4de5f" and r.testVersion == "v1")
```

Web UI: `http://localhost:8086` (user `admin`; password from `variables-misc.tf`, default `admin123`).

Useful measurements: `meanNumberOfRequestsPerSecondTotal`, `numberOfRequestsTotal`, `meanResponseTimeTotal` (and `flavor=ok|ko` variants).

### 3. Grafana (Explore)

Grafana is not on ingress — port-forward only:

```sh
kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
kubectl get secret -n misarch prometheus-stack-grafana \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Use **Explore** with the pre-provisioned InfluxDB datasource and the same Flux filter as above.

**Auto-dashboard note:** The experiment executor creates a Grafana dashboard URL on success. If you see `401 Unauthorized` in executor logs, `GRAFANA_ADMIN_PASSWORD` in `configmaps.tf` did not match the `prometheus-stack-grafana` secret. This is fixed in Terraform by reading the secret value directly; run `terraform apply` to roll out.

### 4. Experiment UI and executor PVC

- **UI:** `https://<INGRESS_IP>/frontend/` — load experiment by UUID/version for configs and re-run.
- **API:** `GET /experiment/{uuid}/{version}/config` and `/gatlingConfig`
- **PVC:** configs persist at `/home/java/tests/{uuid}/{version}/` on the experiment-executor pod. Raw Gatling HTML is not stored (`STORE_RESULT_DATA_IN_FILES=false`).

```sh
kubectl exec -n misarch deploy/misarch-experiment-executor -- \
  ls /home/java/tests/<uuid>/<version>/
```

## Files

| File | Purpose |
|------|---------|
| `flashSaleBuyProcess.kt` | Full purchase journey |
| `flashSaleBrowseOnly.kt` | Browse-and-abandon journey |
| `usersteps-buy.csv` | 50→500→50 load profile (buy) |
| `usersteps-browse.csv` | ~15% load profile (browse) |
| `../../scripts/seed-flash-sale-catalog.sh` | Catalog + Gatling user setup |
| `../../scripts/run-flash-sale-experiment.sh` | REST API automation |
| `../../scripts/export-experiment-results.sh` | Export configs + InfluxDB metrics locally |

## Troubleshooting

- **No address for gatling user**: re-run `seed-flash-sale-catalog.sh` (creates address if missing)
- **Gatling OOM at 500 users/s**: reduce peak in `usersteps-buy.csv` or increase gatling pod limits in `misarch-gatling-executor.tf`
- **Experiment API unreachable**: confirm `curl -sk https://<IP>/experiment/list` returns `[]` or experiment list
- **High error rate during peak**: expected under stress; success = pipeline completes and metrics are captured
