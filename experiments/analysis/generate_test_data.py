#!/usr/bin/env python3
"""
Generate synthetic InfluxDB CSV exports for testing plot_results.py
Simulates two experiment runs:
  - baseline.csv: system under normal load, healthy metrics
  - chaos_inventory.csv: inventory service killed mid-experiment, 
    showing spike in failures then recovery
"""

import csv
import math
import random
from datetime import datetime, timezone, timedelta

random.seed(42)

def write_csv(filename, rows):
    with open(filename, 'w', newline='') as f:
        writer = csv.DictWriter(f, fieldnames=rows[0].keys())
        writer.writeheader()
        writer.writerows(rows)
    print(f"Generated: {filename} ({len(rows)} rows)")

def make_rows(start_time, duration_s, step_s, metric_funcs):
    """Generate one row per timestep per metric."""
    rows = []
    t = start_time
    elapsed = 0
    while elapsed <= duration_s:
        for field, func in metric_funcs.items():
            value = func(elapsed)
            # Add small noise
            value += random.gauss(0, value * 0.03)
            value = max(0, value)
            rows.append({
                "_time": t.strftime("%Y-%m-%dT%H:%M:%SZ"),
                "_field": field,
                "_value": round(value, 2),
                "_measurement": "gatling",
            })
        t += timedelta(seconds=step_s)
        elapsed += step_s
    return rows

# ── Baseline: healthy system ──────────────────────────────────────────────────
start = datetime(2026, 6, 24, 10, 0, 0, tzinfo=timezone.utc)

baseline_funcs = {
    "percentageFailedRequests":        lambda t: 1.2,
    "meanResponseTime":                lambda t: 180 + 20 * math.sin(t / 30),
    "95thPercentileResponseTime":      lambda t: 320 + 30 * math.sin(t / 30),
    "99thPercentileResponseTime":      lambda t: 480 + 40 * math.sin(t / 30),
    "maxResponseTime":                 lambda t: 850 + 50 * math.sin(t / 30),
    "percentageRequestsUnder800ms":    lambda t: 96.5,
    "percentMeanRequestsPerSecondOK":  lambda t: 94.0,
    "percentMeanRequestsPerSecondKO":  lambda t: 1.2,
}

baseline_rows = make_rows(start, duration_s=180, step_s=5, metric_funcs=baseline_funcs)
write_csv("baseline.csv", baseline_rows)

# ── Chaos: inventory killed at t=60s, recovers at t=120s ─────────────────────
def chaos_failed(t):
    if 60 <= t <= 120:
        # Spike to ~65% failure rate during outage
        return 65.0 + 10 * math.sin((t - 60) / 10)
    elif 120 < t <= 150:
        # Gradual recovery
        return 65.0 * math.exp(-(t - 120) / 15)
    return 1.2

def chaos_response_time(t):
    base = 180 + 20 * math.sin(t / 30)
    if 60 <= t <= 120:
        # Timeouts cause very high response times
        return base + 3000 + 500 * math.sin((t - 60) / 10)
    elif 120 < t <= 150:
        return base + 3000 * math.exp(-(t - 120) / 15)
    return base

def chaos_p95(t):
    base = 320 + 30 * math.sin(t / 30)
    if 60 <= t <= 120:
        return base + 5000
    elif 120 < t <= 150:
        return base + 5000 * math.exp(-(t - 120) / 15)
    return base

def chaos_ok_rps(t):
    if 60 <= t <= 120:
        return 30.0
    elif 120 < t <= 150:
        return 30.0 + (94.0 - 30.0) * (1 - math.exp(-(t - 120) / 15))
    return 94.0

chaos_funcs = {
    "percentageFailedRequests":        chaos_failed,
    "meanResponseTime":                chaos_response_time,
    "95thPercentileResponseTime":      chaos_p95,
    "99thPercentileResponseTime":      lambda t: chaos_p95(t) * 1.3,
    "maxResponseTime":                 lambda t: chaos_p95(t) * 1.8,
    "percentageRequestsUnder800ms":    lambda t: max(5, 96.5 - chaos_failed(t)),
    "percentMeanRequestsPerSecondOK":  chaos_ok_rps,
    "percentMeanRequestsPerSecondKO":  chaos_failed,
}

chaos_rows = make_rows(start, duration_s=180, step_s=5, metric_funcs=chaos_funcs)
write_csv("chaos_inventory.csv", chaos_rows)

# ── After fix: circuit breaker installed ─────────────────────────────────────
def fixed_failed(t):
    if 60 <= t <= 75:
        # Brief spike while circuit opens
        return 8.0
    elif 75 < t <= 120:
        # Circuit breaker open: fast-fail, low error rate (graceful degradation)
        return 3.5
    elif 120 < t <= 135:
        # Half-open: testing recovery
        return 5.0
    return 1.2

def fixed_response_time(t):
    base = 180 + 20 * math.sin(t / 30)
    if 60 <= t <= 75:
        return base + 200
    elif 75 < t <= 120:
        # Circuit breaker fails fast — low latency even during outage
        return base + 50
    return base

fixed_funcs = {
    "percentageFailedRequests":        fixed_failed,
    "meanResponseTime":                fixed_response_time,
    "95thPercentileResponseTime":      lambda t: fixed_response_time(t) * 1.6,
    "99thPercentileResponseTime":      lambda t: fixed_response_time(t) * 2.2,
    "maxResponseTime":                 lambda t: fixed_response_time(t) * 3.5,
    "percentageRequestsUnder800ms":    lambda t: max(85, 96.5 - fixed_failed(t) * 2),
    "percentMeanRequestsPerSecondOK":  lambda t: max(88, 94.0 - fixed_failed(t) * 0.5),
    "percentMeanRequestsPerSecondKO":  fixed_failed,
}

fixed_rows = make_rows(start, duration_s=180, step_s=5, metric_funcs=fixed_funcs)
write_csv("chaos_inventory_fixed.csv", fixed_rows)

print("\nTest data generated. Now run:")
print("  python3 plot_results.py \\")
print("    --files baseline.csv chaos_inventory.csv chaos_inventory_fixed.csv \\")
print('    --labels "Baseline" "Inventory Failure (No Fix)" "Inventory Failure (With Fix)" \\')
print("    --output comparison.png \\")
print('    --title "MiSArch Resilience: Circuit Breaker Impact on Inventory Failure"')