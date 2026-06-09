# MiSArch Tier A Resilience Experiments — Reproduction Guide

This document documents work on: cluster provisioning, experiment design, shop preparation, execution, result export, and teardown.

**Repository:** `MiSArch-infrastructure-k8s`  
**Branch used:** `cursor/tier-a-resilience-experiments`  
**Reference run:** 2026-06-09 (~3.3 hours for full Tier A suite)

---

## 1. Goal

Run **hypothesis-driven resilience experiments** on MiSArch deployed to GKE:

- Inject faults via **experiment-config sidecars (ECS)** and **Chaos Toolkit**
- Generate load with **Gatling** (flash-sale user journeys)
- Capture metrics in **InfluxDB / Grafana**
- Export local snapshots for offline analysis
- Identify resilience gaps (cascading latency, saga correctness, async event loss, etc.)

We executed **Tier A** — seven profiles mapped to the [MiSArch Resilience Experiment Catalogue](https://github.com/MiSArch) (experiments 1, 3, 4, 5, 6, 11, 12).

---

## 2. Prerequisites

### Tools

| Tool | Purpose |
|------|---------|
| `gcloud` | GCP project + cluster credentials |
| `terraform` | Platform + app stack |
| `kubectl` | Cluster operations |
| `helm` | Charts (via Terraform) |
| `curl`, `jq`, `python3` | API scripts + export |
| `git` | Submodule init (Keycloak realm) |

### GCP auth

```sh
gcloud config set project YOUR_PROJECT_ID
gcloud auth application-default login
```

Terraform state uses a GCS bucket: `{project_id}-terraform-state`.

### Clone and enter repo

```sh
cd /path/to/MiSArch-infrastructure-k8s
git checkout cursor/flash-sale-load-experiment   # or branch containing resilience scripts
```

---

## 3. Repository layout (what we built)

```
MiSArch-infrastructure-k8s/
├── scripts/
│   ├── deploy-dev.sh                 # bootstrap | apply | destroy
│   ├── prepare-experiment-cluster.sh # wait for testdata + seed shop
│   ├── seed-resilience-shop.sh       # normal vs low-stock catalog
│   ├── seed-flash-sale-catalog.sh    # GraphQL catalog + Gatling user setup
│   ├── run-resilience-experiment.sh  # single Tier A profile
│   ├── run-tier-a-suite.sh           # all 7 profiles sequentially
│   └── export-experiment-results.sh  # InfluxDB + API + log export
├── experiments/
│   ├── flash-sale/                   # Gatling scenarios (shared load journeys)
│   │   ├── flashSaleBuyProcess.kt
│   │   ├── flashSaleBrowseOnly.kt
│   │   └── usersteps-*.csv
│   └── resilience/
│       ├── profiles/
│       │   ├── catalog.json            # profile metadata + hypotheses
│       │   ├── misarch/*.json          # ECS fault injection configs
│       │   └── chaos/*.json            # Chaos Toolkit configs
│       ├── results/                    # gitignored local exports
│       └── REPRODUCTION_GUIDE.md       # this file
├── configmaps.tf                     # Grafana password wired from K8s secret
└── terraform/gcp-dev/                # GKE platform stack
```

---

## 4. Step-by-step workflow

### Phase A — Provision the cluster

#### A.1 Bootstrap remote state

Creates the GCS Terraform state bucket and initializes the platform backend.

```sh
./scripts/deploy-dev.sh bootstrap
```

Expected: `Bootstrap complete. Next: ./scripts/deploy-dev.sh apply`

#### A.2 Apply platform + MiSArch stack

Deploys GKE, ingress-nginx, all MiSArch microservices, experiment executor, Gatling executor, InfluxDB, Grafana (kube-prometheus-stack), Dapr, databases, etc.

```sh
./scripts/deploy-dev.sh apply
```

**Duration:** ~20–40 minutes on first run.

**Expected output (note your IP):**

```
==> Deployment complete
==> Frontend URL: https://<INGRESS_IP>
==> Keycloak URL: https://<INGRESS_IP>/keycloak
==> Ingress IP: <INGRESS_IP>
```

Save `<INGRESS_IP>` — used as `EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment`.

#### A.3 Verify cluster readiness

```sh
# Testdata job must complete (creates Gatling user, sample products, etc.)
kubectl wait --for=condition=complete job/misarch-testdata -n misarch --timeout=900s

# Core pods
kubectl get pods -n misarch | grep -E 'experiment-executor|gatling-executor|gateway|influxdb'
```

#### A.4 Optional — Grafana admin password

```sh
kubectl get secret prometheus-stack-grafana -n misarch \
  -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Port-forward Grafana:

```sh
kubectl port-forward svc/prometheus-stack-grafana -n misarch 3000:80
# http://localhost:3000  user: admin
```

---

### Phase B — Understand the experiment design

#### B.1 Load generation (Gatling)

All Tier A profiles reuse **flash-sale Gatling scenarios**:

| Scenario | Traffic share | Journey |
|----------|---------------|---------|
| `flashSaleBuyProcess` | ~85% | login → browse → product → cart → checkout → place order |
| `flashSaleBrowseOnly` | ~15% | login → browse → cart → abandon |

**Load profile:** 210 seconds total, per scenario:

| Phase | Seconds | Users/s (buy) |
|-------|---------|---------------|
| Baseline | 0–59 | 50 |
| Ramp up | 60–74 | 50 → peak |
| Peak | 75–134 | peak (250 default, 200 for inventory-kill) |
| Ramp down | 135–149 | peak → 50 |
| Baseline | 150–209 | 50 |

Fault injection is timed to start at **t=75s** (`pauses.before: 75` in misarch profiles) — aligned with the load spike.

#### B.2 Fault injection

Two mechanisms:

1. **ECS deterioration** (`misarchExperimentConfig`) — latency/errors on Dapr service invocations and pub/sub, per service name (`inventory`, `payment`, `order`, …).
2. **Chaos Toolkit** (`chaosToolkitConfig`) — pod kills (used only for `inventory-kill-oversell`).

Profile definitions: `experiments/resilience/profiles/catalog.json`

| Profile | Catalogue ID | Peak users/s | Fault | Shop mode |
|---------|--------------|--------------|-------|-----------|
| `baseline-spike` | 1 | 250 | None | normal |
| `inventory-slowdown` | 3 | 250 | 3s delay + 10% errors on `inventory` | normal |
| `payment-failure` | 4 | 250 | 90% errors on `payment` | normal |
| `pubsub-disruption` | 5 | 250 | pub/sub delay/errors on `order` | normal |
| `inventory-kill-oversell` | 6 | 200 | Chaos pod-kill on `misarch-inventory` | **low-stock** (~80 units/SKU) |
| `retry-storm` | 11 | 250 | 2s delay + 35% errors on `inventory` | normal |
| `compound-fault` | 12 | 250 | inventory + payment + order pub/sub faults | normal |

#### B.3 Metrics pipeline

```
Gatling → experiment-executor → InfluxDB (bucket: gatling, org: misarch)
                             → Grafana dashboard (auto-created per run)
                             → local export (CSV/JSON)
```

Key Influx fields for analysis: `meanNumberOfRequestsPerSecondOk/Ko`, `meanResponseTimeOk/Ko`, `numberOfRequestsOk/Ko`, `activeUsers`.

---

### Phase C — Prepare the shop catalog

The seed scripts talk to GraphQL via **port-forward** (Keycloak does not accept self-signed ingress certs without `-k`).

#### C.1 Automatic (recommended)

The suite calls this automatically:

```sh
./scripts/prepare-experiment-cluster.sh
```

This waits for `misarch-testdata`, core deployments, then runs `seed-resilience-shop.sh` in **normal** mode.

#### C.2 Manual seed

```sh
# Port-forwards (if not already running)
kubectl port-forward svc/misarch-gateway -n misarch 8080:8080 &
kubectl port-forward svc/keycloak -n misarch 8081:80 &

# Normal mode — ensures Flash Sale category + SKUs exist
SHOP_MODE=normal ./scripts/seed-resilience-shop.sh

# Low-stock mode — restocks each SKU to ~80 units (for inventory-kill-oversell)
SHOP_MODE=low-stock ./scripts/seed-resilience-shop.sh
```

**What gets created:**

- Flash Sale category + products: `FLASH_HEADPHONES`, `FLASH_SMARTWATCH`, `FLASH_SPEAKER`, `FLASH_GAMING_KIT`
- Gatling user shipping address (if missing)
- Uses Keycloak user `gatling` / password `123` (from testdata job)

---

### Phase D — Run experiments

Set the experiment API URL (replace with your ingress IP):

```sh
export EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment
```

#### D.1 Single experiment

```sh
EXPERIMENT_PROFILE=inventory-slowdown ./scripts/run-resilience-experiment.sh
```

**What the script does:**

1. Reads profile from `profiles/catalog.json`
2. Seeds shop (unless `SKIP_SHOP_SEED=true`)
3. `POST /experiment/generate` — creates UUID + v1
4. `PUT` Gatling config (Kotlin scenarios + dynamic usersteps CSV)
5. `PUT` experiment config, chaos config, misarch fault config
6. `POST .../start`
7. Waits for executor log: `Finished Experiment run for testUUID: ...`
8. Writes `resilience-notes.txt` and calls `export-experiment-results.sh`

**Duration per experiment:** ~8–12 minutes (Gatling compile + 210s simulation + export).

#### D.2 Full Tier A suite (sequential)

```sh
EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment ./scripts/run-tier-a-suite.sh
```

Runs all seven profiles in order with a 30s cooldown between runs. Logs to `/tmp/tier-a-suite.log`.

Shop seeding: once at start (normal); re-seeds with **low-stock** only for `inventory-kill-oversell`.

**Override peak load:**

```sh
EXPERIMENT_PROFILE=baseline-spike PEAK_USERS=150 ./scripts/run-resilience-experiment.sh
```

#### D.3 Manual export (if needed)

```sh
TEST_UUID=<uuid> TEST_VERSION=v1 \
EXPERIMENT_PROFILE=inventory-slowdown \
PEAK_USERS=250 BASELINE_USERS=50 \
EXPERIMENT_DIR=experiments/resilience \
EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment \
./scripts/export-experiment-results.sh
```

---

### Phase E — Collect and read results

#### E.1 Local export directory

```
experiments/resilience/results/{uuid}-v1/
├── manifest.json                  # uuid, profile, peak/baseline, export time
├── experiment-config.json         # goals, load type
├── gatling-config.json            # scenarios (base64)
├── misarch-experiment-config.json # fault injection config used
├── chaos-toolkit-config.json      # chaos config used
├── usersteps-buy.csv / usersteps-browse.csv
├── influxdb-metrics.csv           # raw Flux export
├── influxdb-summary.json          # aggregated ok/ko RPS, response times, error ratios
├── executor.log.snippet           # metrics push, dashboard, fault activity
├── gatling.log.snippet            # BUILD SUCCESSFUL, simulation completion
├── resilience-notes.txt           # hypothesis + analysis hints
└── README.txt                     # how to re-open InfluxDB/Grafana
```

Results are **gitignored** (`experiments/**/results/`).

#### E.2 Suite summary

After a full suite run:

```
experiments/resilience/results/suite-summary.txt
experiments/resilience/results/run-log.txt
```

#### E.3 Live metrics (without export)

```sh
# InfluxDB
kubectl port-forward svc/influxdb -n misarch 8086:80
terraform output -raw influxdb_admin_token

# Example Flux filter
from(bucket:"gatling")
  |> range(start: -24h)
  |> filter(fn: (r) => r.testUUID == "<uuid>" and r.testVersion == "v1")
```

#### E.4 Experiment UI

```
https://<INGRESS_IP>/frontend/
```

---

### Phase F — Tear down the cluster

```sh
./scripts/deploy-dev.sh destroy
```

Destroys the MiSArch app stack, disables GKE deletion protection, destroys the platform stack, and cleans orphan PVC disks.

**Duration:** ~15–30 minutes.

---

## 5. Our reference run (2026-06-09)

**Ingress IP:** `35.246.166.155`  
**Suite duration:** ~3.3 hours  
**Log file:** `/tmp/tier-a-suite.log`

### Results summary

| Profile | Status | Experiment UUID | Results path |
|---------|--------|-----------------|--------------|
| `baseline-spike` | OK | `96e749eb-3a05-43da-bc56-e3973aee446e` | `results/96e749eb-...-v1/` |
| `inventory-slowdown` | OK | `e0085c85-6bed-4c48-8d4a-cc10e08697e9` | `results/e0085c85-...-v1/` |
| `payment-failure` | OK | `390c1939-dff6-4c82-8cad-ccafc5153db9` | `results/390c1939-...-v1/` |
| `pubsub-disruption` | OK | `299c86a0-1793-4c6d-ae0b-a738fc10ae6a` | `results/299c86a0-...-v1/` |
| `inventory-kill-oversell` | **FAIL** (1200s timeout) | `bc30dcb7-ac6b-4cae-a730-f551aeaa5c98` | no export |
| `retry-storm` | **FAIL** (1200s timeout) | `ec57de76-5df0-4292-ab19-4759affb5e39` | no export |
| `compound-fault` | **FAIL** (1200s timeout) | `53ae4e3e-77c7-491f-a566-cfb542c718e5` | no export |

### Failure notes

- **`inventory-kill-oversell`:** Likely stuck waiting for Chaos Toolkit pod-kill completion or experiment executor never logged `Finished Experiment run`.
- **`retry-storm` / `compound-fault`:** Gatling completed (~7 min) but executor logged `Dashboard creation failed`; the wait script never saw `Finished Experiment run` and timed out after 1200s. Metrics may exist in InfluxDB for these UUIDs even without local export.

To re-run failed profiles only:

```sh
export EXPERIMENT_BASE_URL=https://<INGRESS_IP>/experiment
for p in inventory-kill-oversell retry-storm compound-fault; do
  EXPERIMENT_PROFILE=$p SKIP_SHOP_SEED=$([[ "$p" == inventory-kill-oversell ]] && echo false || echo true) \
    ./scripts/run-resilience-experiment.sh
  sleep 30
done
```

---

## 6. Infrastructure changes we made (for reproducibility)

These are in the repo and affect experiment behavior:

| Change | File | Why |
|--------|------|-----|
| Grafana admin password from K8s secret | `configmaps.tf`, `prometheus.tf` | Fixes 401 on auto-dashboard creation |
| Gatling memory limit 8Gi | `misarch-gatling-executor.tf` | Prevents OOM at 250+ users/s |
| Resilience profiles + run scripts | `experiments/resilience/`, `scripts/run-*.sh` | Tier A automation |
| Export script fixes | `scripts/export-experiment-results.sh` | InfluxDB port 80 (not 8080), CSV parser, profile in manifest |
| Results gitignored | `.gitignore` | Large CSV/JSON not committed |

After changing `configmaps.tf`, run `terraform apply` (or re-`deploy-dev.sh apply`) to roll out the Grafana password fix.

---

## 7. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Seed script fails on Keycloak | HTTPS/self-signed cert | Use port-forward (`8080`/`8081`), not ingress URL |
| Gatling OOMKilled | Peak too high for pod memory | Lower `PEAK_USERS` or confirm 8Gi limit |
| Export: `port-forward exited` | Wrong InfluxDB service port | Script uses port `80` → target `8086` (fixed in export script) |
| No Grafana dashboard URL | Password mismatch before configmaps fix | `terraform apply` + restart experiment-executor |
| Experiment timeout | Dashboard export failure or chaos hang | Check `kubectl logs -n misarch deploy/misarch-experiment-executor --since=1h`; re-export manually by UUID |
| `require_cmd: command not found` | Old prepare script | Pull latest `prepare-experiment-cluster.sh` |
| Suite log empty | Shell wrapper buffering | Suite now writes to `/tmp/tier-a-suite.log` via `tee -a` |

---

## 8. Quick command cheat sheet

```sh
# Full lifecycle
./scripts/deploy-dev.sh bootstrap
./scripts/deploy-dev.sh apply
export EXPERIMENT_BASE_URL=https://$(cd terraform/gcp-dev && terraform output -raw ingress_external_ip)/experiment
./scripts/run-tier-a-suite.sh
./scripts/deploy-dev.sh destroy

# One-off experiment
EXPERIMENT_PROFILE=payment-failure ./scripts/run-resilience-experiment.sh

# Re-export
TEST_UUID=<uuid> EXPERIMENT_DIR=experiments/resilience EXPERIMENT_PROFILE=<profile> \
  ./scripts/export-experiment-results.sh
```

---

## 9. Further reading

- Tier A profile README: [`README.md`](README.md)
- Flash-sale runbook: [`../flash-sale/README.md`](../flash-sale/README.md)
- MiSArch docs: https://misarch.github.io/docs
- Resilience experiment catalogue: `MiSArch Resilience Experiment Catalogue.md` (team vault)
- Resilience aspects framework: `Aspects of Resilience.md` (team vault)
