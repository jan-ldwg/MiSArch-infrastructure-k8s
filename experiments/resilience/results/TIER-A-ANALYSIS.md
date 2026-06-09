# Tier A Resilience Experiment Analysis

**Reference run:** 2026-06-09 · Ingress `35.246.166.155` · Suite duration ~3.3 h  
**Branch:** `cursor/tier-a-resilience-experiments`  
**Data source:** Exported CSV/JSON in `experiments/resilience/results/` (4/7 profiles). Failed runs analyzed from suite logs, [REPRODUCTION_GUIDE.md](../REPRODUCTION_GUIDE.md), and profile catalogue.

> **Metric note:** Gatling OK/KO in Influx is primarily **response-time classification** (KO ≈ exceeded ~60 s threshold), not strictly HTTP/GraphQL business failure. `placeOrderMutation` OK/KO reflects user-visible checkout latency; aggregate totals are dominated by **`get` GraphQL reads** (~87–92% KO on GET across all successful runs).

---

## Executive Summary (Top 3 Refactorings by Impact)

### 1. Saga orchestration with payment/inventory outcome propagation + compensation (Architectural)

**Evidence:** `payment-failure` — 90% ECS errors on `payment`, yet **placeOrder KO rate fell** from 2.66% (baseline) to **0.50%** (12 KO / 2,392 OK). `paymentInformationsQuery` KO rose to **11.2%** (267 failures), but checkout mutation still succeeds. This matches MiSArch’s known limitation: **order does not observe payment/inventory failure**; no compensation runs.

**Impact:** Addresses orphan orders, silent inconsistency under `payment-failure`, `pubsub-disruption`, and (when re-run) `compound-fault`.  
**Effort:** Architectural · **Academic interest:** High — demonstrable *semantic fault masking* in choreographed microservice sagas.

### 2. Gateway sync-path resilience: timeouts, circuit breakers, bulkheads on Order→Inventory/Payment (Medium)

**Evidence:** `inventory-slowdown` — 3 s inventory delay + 10% 503s → **mean RT KO +13.7%** (83.1 s → 94.5 s), **createOrder RT KO +69%** (38.3 s → 64.8 s), **placeOrder RT OK +93%** (17.7 s → 34.2 s). No circuit breaking: peak KO RPS unchanged (~69/s). Baseline already shows **64.2% aggregate KO** at 250 users/s with GET saturation.

**Impact:** Cascading latency, retry-storm amplification, compound sync-leg failures.  
**Effort:** Medium (Resilience4j/Dapr policies on order + gateway) · **Academic interest:** Medium–high — quantified cascade without bulkhead isolation.

### 3. Durable async pipeline: transactional outbox + broker DLQ + fulfillment reconciliation (Architectural)

**Evidence:** `pubsub-disruption` — order pub/sub ECS (50% errors, 8 s delay) → **placeOrder 0% KO** (3,402/3,402 OK), while aggregate KO RPS rose **+46.6%** (69 → 101/s) and `paymentInformationsQuery` KO hit **42.7%**. User journey succeeds; async shipment/notification path is unobservable at GraphQL.

**Impact:** Silent event loss, fire-and-forget pub/sub, Redis non-durability.  
**Effort:** Architectural · **Academic interest:** High — *observability gap* between sync SLA and async correctness.

---

## Per-Experiment Analysis

### Profile 1 — `baseline-spike` ✅

| Field | Value |
|-------|-------|
| Catalogue ID | 1 |
| UUID | `96e749eb-3a05-43da-bc56-e3973aee446e` |
| Results | `96e749eb-3a05-43da-bc56-e3973aee446e-v1/` |
| Status | OK (2026-06-09T08:54:09Z) |

**Hypothesis:** Under 50→250→50 users/s with no faults, pipeline completes and captures baseline latency/error metrics.

| Metric | Value |
|--------|-------|
| Peak OK / KO RPS | 38.6 / 69.2 |
| Error ratio (total) | **64.18%** (32,167 KO / 50,121 total) |
| Mean RT / RT OK / RT KO | 62.7 s / 26.1 s / 83.1 s |
| placeOrder err | **2.66%** (53 KO / 1,991 OK) |
| GET err | **92.2%** (28,196 KO) |
| Peak active users (buy) | 25,135 |

**Verdict:** **Partially confirmed.** Gatling completed in 464 s (`BUILD SUCCESSFUL`). Pipeline “completes” but is **already resilience-poor**: majority of requests classified KO, browse/GET path degraded before any fault injection.

**Degraded path:** Gateway GraphQL **reads (`get`)** >> order placement. Sync checkout (placeOrder) relatively healthy (~97% OK by latency bucket).

**Confidence:** **High**

---

### Profile 3 — `inventory-slowdown` ✅

| Field | Value |
|-------|-------|
| Catalogue ID | 3 |
| UUID | `e0085c85-6bed-4c48-8d4a-cc10e08697e9` |
| Results | `e0085c85-6bed-4c48-8d4a-cc10e08697e9-v1/` |
| Fault | Inventory `/` — 3 s delay, 10% 503 @ t=75 s |
| Status | OK (2026-06-09T09:02:51Z) |

**Hypothesis:** 3 s inbound delay on inventory during peak causes cascading latency without circuit breaking.

| Metric | Baseline | Profile | Δ |
|--------|----------|---------|---|
| Peak OK / KO RPS | 38.6 / 69.2 | 61.0 / 68.3 | +58% / −1% |
| Error ratio (total) | 64.18% | **52.82%** | **−11.4 pp** |
| Mean RT KO | 83.1 s | 94.5 s | **+13.7%** |
| placeOrder RT OK | 17.7 s | 34.2 s | **+93%** |
| createOrder RT KO | 38.3 s | 64.8 s | **+69%** |
| placeOrder err | 2.66% | 3.04% | +0.4 pp |
| group1 fail % | 4.4% | 5.5% | +1.1 pp |

**Verdict:** **Confirmed (latency cascade), refuted (aggregate error spike).**

- **Confirmed:** Inventory sync leg slows entire checkout chain (createOrder/placeOrder RT up; executor logged `Configure ... failure set 1` at t=75 s).
- **Refuted as stated:** Total error ratio **decreased** — baseline GET saturation dominates totals; slower inventory changes journey mix/completion rate rather than monotonically increasing KO%.

**Degraded path:** **Order → Inventory** sync invocation (GraphQL checkout chain); collateral **GET** saturation persists.

**Confidence:** **High**

---

### Profile 4 — `payment-failure` ✅

| Field | Value |
|-------|-------|
| Catalogue ID | 4 |
| UUID | `390c1939-dff6-4c82-8cad-ccafc5153db9` |
| Results | `390c1939-dff6-4c82-8cad-ccafc5153db9-v1/` |
| Fault | Payment `/` — 90% 500, 1 s delay @ t=75 s |
| Status | OK (2026-06-09T09:11:32Z) |

**Hypothesis:** 90% payment errors during checkout produce orphan orders or incorrect saga events.

| Metric | Baseline | Profile | Δ |
|--------|----------|---------|---|
| Peak OK / KO RPS | 38.6 / 69.2 | 53.7 / 68.9 | +39% / −0.4% |
| Error ratio (total) | 64.18% | 56.18% | −8.0 pp |
| placeOrder err | 2.66% | **0.50%** | **−2.2 pp** |
| paymentInfo err | 0% | **11.2%** | +11.2 pp |
| group1 fail % | 4.4% | **14.0%** | **+9.5 pp** |
| Mean RT KO | 83.1 s | 93.8 s | +12.9% |

**Verdict:** **Confirmed at architecture level; not directly counted in DB.**

- **Confirmed:** Payment fault visible on `paymentInformationsQuery` (+267 KO) and failed journey groups (+9.5 pp), yet **placeOrder succeeds more often** than baseline → order path **does not fail closed** on payment ECS errors. Consistent with MiSArch saga gap (no payment outcome observation, no compensation).
- **Cannot confirm:** Actual orphan row count (would need order/payment DB audit).

**Degraded path:** **Payment** service (ECS inbound); **not** reflected in placeOrder GraphQL response.

**Confidence:** **Medium–high** for architectural orphan risk; **low** for counted orphans.

---

### Profile 5 — `pubsub-disruption` ✅

| Field | Value |
|-------|-------|
| Catalogue ID | 5 |
| UUID | `299c86a0-1793-4c6d-ae0b-a738fc10ae6a` |
| Results | `299c86a0-1793-4c6d-ae0b-a738fc10ae6a-v1/` |
| Fault | Order pub/sub — 50% errors, 8 s delay @ t=75 s |
| Status | OK (2026-06-09T09:19:28Z) |

**Hypothesis:** Order pub/sub deterioration during peak causes silent async fulfillment failures.

| Metric | Baseline | Profile | Δ |
|--------|----------|---------|---|
| Peak OK / KO RPS | 38.6 / 69.2 | 56.4 / **101.4** | +46% / **+47%** |
| Error ratio (total) | 64.18% | 64.25% | +0.07 pp |
| placeOrder err | 2.66% | **0.00%** | −2.7 pp |
| placeOrder OK count | 1,938 | **3,402** | +75% |
| paymentInfo err | 0% | **42.7%** | +42.7 pp |
| product err | 31.5% | **50.4%** | +19 pp |

**Verdict:** **Confirmed for user-visible silence; partial for async loss.**

- **Confirmed:** Sync checkout **unaffected** (0% placeOrder KO) while system-wide KO RPS jumps +47% — fault is **not surfaced** to the Gatling buyer journey.
- **Partial:** Cannot prove shipment/notification loss without order-event traces or DB; Redis/Dapr fire-and-forget makes silent loss plausible.

**Degraded path:** **Order pub/sub → async saga** (shipment/notification); gateway checkout appears healthy.

**Confidence:** **High** for masking; **medium** for fulfillment loss.

---

### Profile 6 — `inventory-kill-oversell` ❌

| Field | Value |
|-------|-------|
| Catalogue ID | 6 |
| UUID | `bc30dcb7-ac6b-4cae-a730-f551aeaa5c98` |
| Results | *(no export)* |
| Fault | Chaos pod-kill on `misarch-inventory` + low-stock shop (~80 units/SKU) |
| Status | FAIL (2026-06-09T09:40:41Z) |

**Operational failure:** `run-resilience-experiment.sh` **1200 s wait timeout**. Likely **Chaos Toolkit hang** after pod-kill (`inventory-kill.json`: kill @ t=80 s, `after: 45` pause). Executor never logged `Finished Experiment run` within timeout.

**Partial evidence:**

- Suite log: `Experiment inventory-kill-oversell failed — continuing suite.` @ 09:40:41Z (~20 min after pubsub — consistent with full timeout).
- Chaos config targets `misarch-inventory` pod termination under **low-stock** shop (peak 200 users/s).

**Can conclude:** Tooling/chaos completion detection blocked the run; oversell hypothesis **untested**.  
**Cannot conclude:** Stock consistency, oversell count, or inventory recovery time.

**Re-run recommendation:** **Yes.** Fixes:

1. Decouple completion from Grafana export — treat `Gatling Metrics pushed` as success.
2. Chaos `after` probe with timeout + rollback.
3. Post-run stock audit script comparing reserved vs sold.
4. Export by UUID even on partial completion.

**Confidence:** **High** for failure mode; **none** for hypothesis.

---

### Profile 11 — `retry-storm` ❌

| Field | Value |
|-------|-------|
| Catalogue ID | 11 |
| UUID | `ec57de76-5df0-4292-ab19-4759affb5e39` |
| Results | *(no export)* |
| Fault | Inventory 2 s delay, 35% 503, 90% delay probability |
| Status | FAIL (2026-06-09T10:41:36Z) |

**Operational failure:** Gatling completed (~7 min) but executor logged **`Dashboard creation failed`**; wait script never saw `Finished Experiment run` → **1200 s timeout**.

**Partial evidence:**

- Fault config designed to amplify Order→Inventory retries.
- Prior `inventory-slowdown` showed inventory delay propagates to createOrder RT (+69%) without reducing downstream load (KO RPS flat) — consistent with **retry amplification risk**, but not measured here.
- Metrics may exist in InfluxDB for UUID (not exported locally).

**Can conclude:** Operational pipeline defect masked a likely-valid experiment; retry-storm hypothesis **not evaluated**.  
**Cannot conclude:** Retry multiplication factor, inventory RPS vs user RPS, or circuit-breaker necessity quantification.

**Re-run recommendation:** **Yes.** Fixes:

1. Grafana password/export fix (see REPRODUCTION_GUIDE).
2. `wait_for_completion` fallback on metrics push.
3. Add Prometheus counter for Order→Inventory invocation rate vs Gatling RPS.
4. Manual `export-experiment-results.sh` with UUID.

**Confidence:** **High** for ops failure; **low** for hypothesis (architecture-only inference).

---

### Profile 12 — `compound-fault` ❌

| Field | Value |
|-------|-------|
| Catalogue ID | 12 |
| UUID | `53ae4e3e-77c7-491f-a566-cfb542c718e5` |
| Results | *(no export)* |
| Fault | Inventory delay + payment errors + order pub/sub (sequential from t=75 s) |
| Status | FAIL (2026-06-09T12:00:12Z) |

**Operational failure:** Same as retry-storm — **dashboard export failure + completion detector timeout** (~80 min slot).

**Partial evidence:**

- Compound profile stacks inventory delay (3 s) → payment errors (70%) → order pub/sub errors (40%) sequentially from t=75 s.
- Individual successful runs show **non-additive** aggregate effects (payment lowered total err%; pubsub raised KO RPS but not total err%). Compound **superlinear impact** remains unmeasured.

**Can conclude:** Cannot validate emergent compound failure hypothesis.  
**Cannot conclude:** Whether combined faults exceed sum of individuals (key research question).

**Re-run recommendation:** **Yes**, after tooling fixes and with **per-leg observability** (sync vs async dashboards). Consider lowering peak to 200 users/s to separate load saturation from compound fault.

**Confidence:** **High** for ops failure; **none** for compound hypothesis.

---

## Cross-Experiment Synthesis

### Architecture paths

```
Sync hot path (observed by Gatling):
  Gateway GraphQL → Order → Inventory/Payment

Async saga (not observed by Gatling):
  Order → Dapr pub/sub → Shipment / Notification
```

### Sync vs async failure patterns

| Pattern | Sync path (Profiles 1, 3, 4) | Async path (Profile 5) |
|---------|------------------------------|------------------------|
| User-visible errors | Dominated by **GET/browse** saturation (baseline 64% KO) | **placeOrder ~0–3% KO** under faults |
| Fault effect | Inventory delay → **RT cascade** (+69% createOrder RT KO) | Pub/sub fault → **+47% system KO RPS**, **0% placeOrder KO** |
| Correctness | Payment fault **does not fail checkout** (orphan risk) | **Silent** — no fulfillment metrics in export |
| Load interaction | Baseline saturation **masks** injected fault delta on aggregate err% | More completed placeOrders (+75%) under pubsub fault |

**Key finding:** Injected ECS faults often **do not increase aggregate error ratio** vs baseline because the system is **already KO-saturated on reads**. Resilience work must separate **browse bulkhead**, **checkout sync chain**, and **async saga** SLOs — not one global error rate.

---

## Refactoring Roadmap

| Priority | Refactoring | Evidence | Effort | Academic interest |
|:--:|---|---|---|---|
| **P0** | **Saga orchestrator**: order observes payment + inventory outcomes; compensating transactions on failure | payment-failure: 0.5% placeOrder KO under 90% payment errors; group1 +9.5 pp | Architectural | Choreography vs orchestration under semantic faults |
| **P0** | **Transactional outbox + durable broker/DLQ** for order events | pubsub-disruption: 0% placeOrder KO, +47% KO RPS; Redis non-durable | Architectural | Measuring silent data loss in event-driven sagas |
| **P1** | **Circuit breaker + timeout + bulkhead** on Order→Inventory and Order→Payment | inventory-slowdown: +69% createOrder RT KO, flat KO RPS; retry-storm (pending) | Medium | Cascade containment without retry storms |
| **P1** | **Gateway GraphQL bulkhead**: separate pools / rate limits for browse vs checkout | baseline: 92% GET KO, 64% total KO at 250 u/s | Medium | Load shedding under flash-sale vs fault injection |
| **P1** | **Sync inventory reservation** (hold + confirm) before placeOrder success | inventory-kill-oversell (untested); known oversell under crash | Architectural | CAP/consistency trade-offs in e-commerce spikes |
| **P2** | **Retry policy**: capped retries, jitter, idempotency keys on Order→Inventory | retry-storm profile; inventory delay without CB | Medium | Retry amplification measurement methodology |
| **P2** | **Fulfillment reconciliation job**: orphan orders, stock drift, unpublished events | payment-failure + pubsub patterns | Medium | Automated audit for partial sagas |
| **P2** | **End-to-end tracing**: correlate placeOrder → payment → pub/sub → shipment | Observability gap across all profiles | Quick–medium | Closing the "silent async" blind spot |
| **P3** | **HPA on gateway/order/inventory** keyed to checkout latency | baseline saturation before faults | Quick | Autoscaling vs flash-sale burst |
| **P3** | **Readiness probes** including Dapr sidecar + downstream health | chaos kill + recovery (untested) | Quick | Probe design for microservice+messaging stacks |
| **P3** | **Experiment tooling**: multi-table CSV parser, completion detector, chaos timeout | 3/7 failed runs; empty `influxdb-summary.json` highlights | Quick | Reproducible resilience benchmarking |

### Phased rollout

**Quick wins (1–2 sprints):** Fix export summary parser (use `_measurement` not `_field`); completion detector accepts metrics push; add stock/order audit scripts; Grafana dashboard export; per-endpoint dashboards (`placeordermutat`, `get`, `paymentinformat`).

**Medium (1–2 months):** Resilience4j/Dapr HTTP timeouts + circuit breakers on order→inventory/payment; gateway bulkheads; capped retries with idempotency; Prometheus metrics for downstream call fan-out.

**Architectural (thesis-scale):** Saga orchestrator + outbox + durable messaging; sync reservation pattern; optional cell-based bulkheads for checkout vs catalog.

---

## Research Angles

1. **Semantic fault masking:** Quantify divergence between *client-perceived success* (placeOrder OK) and *system correctness* (payment/pubsub faults) — extends beyond “add retries.”

2. **Saturation–fault superposition:** Show injected faults are **orthogonal** to baseline GET saturation; propose **decomposed SLOs** (browse p95, checkout p95, fulfillment lag).

3. **Retry amplification under choreographed sagas:** Re-run retry-storm with Order→Inventory call-count telemetry vs user RPS.

4. **Compound failure non-linearity:** Re-run compound-fault to test if combined impact exceeds sum of profiles 3+4+5.

5. **Chaos + consistency:** inventory-kill-oversell as study of **crash during reservation** with low stock.

---

## Appendix

### Experiment UUIDs & result paths

| ID | Profile | Status | UUID | Results path |
|:--:|---------|:--:|--------|--------------|
| 1 | baseline-spike | OK | `96e749eb-3a05-43da-bc56-e3973aee446e` | `96e749eb-3a05-43da-bc56-e3973aee446e-v1/` |
| 3 | inventory-slowdown | OK | `e0085c85-6bed-4c48-8d4a-cc10e08697e9` | `e0085c85-6bed-4c48-8d4a-cc10e08697e9-v1/` |
| 4 | payment-failure | OK | `390c1939-dff6-4c82-8cad-ccafc5153db9` | `390c1939-dff6-4c82-8cad-ccafc5153db9-v1/` |
| 5 | pubsub-disruption | OK | `299c86a0-1793-4c6d-ae0b-a738fc10ae6a` | `299c86a0-1793-4c6d-ae0b-a738fc10ae6a-v1/` |
| 6 | inventory-kill-oversell | FAIL | `bc30dcb7-ac6b-4cae-a730-f551aeaa5c98` | *(none)* |
| 11 | retry-storm | FAIL | `ec57de76-5df0-4292-ab19-4759affb5e39` | *(none)* |
| 12 | compound-fault | FAIL | `53ae4e3e-77c7-491f-a566-cfb542c718e5` | *(none)* |

### Suite summary (`suite-summary.txt`)

```
OK   baseline-spike          2026-06-09T08:54:09Z
OK   inventory-slowdown      2026-06-09T09:02:51Z
OK   payment-failure         2026-06-09T09:11:32Z
OK   pubsub-disruption       2026-06-09T09:19:28Z
FAIL inventory-kill-oversell  2026-06-09T09:40:41Z
FAIL retry-storm             2026-06-09T10:41:36Z
FAIL compound-fault          2026-06-09T12:00:12Z
```

### Known tooling gaps

| Gap | Effect on analysis |
|-----|---------------------|
| `influxdb-summary.json` highlights empty | Required manual multi-table CSV parsing |
| Completion waits on `Finished Experiment run` only | 3/7 profiles marked FAIL despite Gatling success |
| Grafana dashboard export failure | Blocks executor completion for retry-storm/compound-fault |
| Chaos hang / no export on kill profile | inventory-kill-oversell untested |
| No backend audit in export | Orphan/oversell hypotheses inferred from GraphQL metrics only |
| ECS 404 warnings on catalog/simulation/user | Fault injection still applied to order/inventory/payment (executor logs confirm failure set 1/2) |

### Re-export failed runs

If InfluxDB still holds data for failed UUIDs:

```sh
export EXPERIMENT_BASE_URL=https://35.246.166.155/experiment
for u p in \
  bc30dcb7-ac6b-4cae-a730-f551aeaa5c98:inventory-kill-oversell \
  ec57de76-5df0-4292-ab19-4759affb5e39:retry-storm \
  53ae4e3e-77c7-491f-a566-cfb542c718e5:compound-fault; do
  uuid="${u%%:*}"; profile="${u##*:}"
  TEST_UUID="$uuid" EXPERIMENT_PROFILE="$profile" EXPERIMENT_DIR=experiments/resilience \
    ./scripts/export-experiment-results.sh
done
```

### Full comparison table (successful runs vs baseline)

| Metric | baseline | inventory-slowdown | payment-failure | pubsub-disruption |
|--------|----------|-------------------|-----------------|-------------------|
| Peak OK RPS | 38.6 | 61.0 (+58%) | 53.7 (+39%) | 56.4 (+46%) |
| Peak KO RPS | 69.2 | 68.3 (−1%) | 68.9 (−0.4%) | 101.4 (+47%) |
| Error ratio (total) | 64.18% | 52.82% (−11.4 pp) | 56.18% (−8.0 pp) | 64.25% (+0.07 pp) |
| Mean RT KO | 83.1 s | 94.5 s (+14%) | 93.8 s (+13%) | 71.7 s (−14%) |
| placeOrder err | 2.66% | 3.04% | 0.50% | 0.00% |
| group1 fail % | 4.4% | 5.5% | 14.0% | 11.6% |

---

**Bottom line:** Four successful runs expose three systemic gaps — **(1)** checkout succeeds while payment/async fail, **(2)** inventory delay cascades without isolation, **(3)** baseline browse saturation swamps aggregate metrics. Three failed runs are primarily an **experiment-ops** problem; re-run with completion-detector and export fixes before drawing conclusions on oversell, retry storms, or compound emergence.
