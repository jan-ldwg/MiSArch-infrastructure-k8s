# MiSArch Tier A Resilience Experiments

Hypothesis-driven resilience experiments using the MiSArch experiment stack:

- **Gatling** — flash-sale load profile (50 → peak → 50 users/s, 210s)
- **ECS deterioration** — `misarchExperimentConfig` (latency/errors on service paths & pub/sub)
- **Chaos Toolkit** — pod kills via `chaosToolkitConfig`
- **Metrics** — InfluxDB (`gatling` bucket), Grafana dashboards, local CSV/JSON export

**Team reproduction guide:** [REPRODUCTION_GUIDE.md](REPRODUCTION_GUIDE.md) — full step-by-step record of provisioning, execution, and results collection.

## Tier A catalogue

| ID | Profile | Fault | Resilience aspect tested |
|----|---------|-------|--------------------------|
| 1 | `baseline-spike` | None | Ingress capacity, saturation under flash sale |
| 3 | `inventory-slowdown` | ECS delay on inventory inbound (`/`) | Cascading latency, timeout absence |
| 4 | `payment-failure` | ECS errors on payment inbound | Saga correctness, orphan orders |
| 5 | `pubsub-disruption` | ECS pub/sub errors on order | Async pipeline durability |
| 6 | `inventory-kill-oversell` | Chaos pod-kill + low stock | Stock consistency under crash |
| 11 | `retry-storm` | ECS intermittent inventory delay/errors | Retry amplification on Order→Inventory |
| 12 | `compound-fault` | Inventory delay + payment errors + order pub/sub | Emergent compound failure |

## Quick start

```sh
# After cluster deploy + testdata job complete:
./scripts/seed-resilience-shop.sh

# Single experiment:
EXPERIMENT_PROFILE=inventory-slowdown ./scripts/run-resilience-experiment.sh

# Full Tier A suite (sequential):
./scripts/run-tier-a-suite.sh
```

## Results

Exports land in `experiments/resilience/results/{uuid}-v1/` (gitignored).

Key files per run: `manifest.json`, `influxdb-metrics.csv`, `influxdb-summary.json`, `resilience-notes.txt`.
