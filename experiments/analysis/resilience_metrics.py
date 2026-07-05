#!/usr/bin/env python3
"""
MiSArch Resilience Metrics Calculator
======================================
Calculates MTTR and related resilience metrics from InfluxDB CSV exports.

For controlled chaos experiments (pod kill at t=120s), the key measurable
metrics are:
  - MTTR: Mean Time To Recovery — time from failure injection until
          error rate returns to within 10% of baseline
  - Error rate during failure window
  - Impact severity: % increase in KO requests vs baseline
  - Orders lost: inventory consumed vs baseline expectation

Usage:
    # Calculate metrics for one chaos experiment vs baseline:
    python3 resilience_metrics.py \
        --baseline baseline/results.csv \
        --chaos order_kill_1replica/results.csv \
        --kill-time 120 \
        --label "Order Kill (1 Replica)"

    # Compare before/after fix:
    python3 resilience_metrics.py \
        --baseline baseline/results.csv \
        --chaos order_kill_1replica/results.csv \
                order_kill_2replicas/results.csv \
        --labels "1 Replica (Before Fix)" "2 Replicas (After Fix)" \
        --kill-time 120

Requirements:
    pip install pandas matplotlib
"""

import argparse
import sys
import io
import os
import json
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path


# ── Style ─────────────────────────────────────────────────────────────────────
BG    = "#1a1a2e"
PANEL = "#16213e"
TEXT  = "#e0e0e0"
GRID  = "#333355"
COLOR_BASELINE = "#4CAF50"
COLOR_CHAOS    = ["#F44336", "#FF9800", "#2196F3", "#9C27B0"]


# ── CSV Parsing ───────────────────────────────────────────────────────────────

def parse_csv(filepath: str) -> pd.DataFrame:
    """Parse InfluxDB annotated CSV export."""
    with open(filepath, "rb") as f:
        content = f.read().decode("utf-8")

    lines = content.splitlines()
    data_lines = []
    header = None

    for line in lines:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if ",result," in line or line.startswith(",result,"):
            if header is None:
                header = line
            continue
        if header and line.startswith(",,"):
            data_lines.append(line)

    if not header or not data_lines:
        print(f"ERROR: Could not parse {filepath}", file=sys.stderr)
        sys.exit(1)

    df = pd.read_csv(io.StringIO(header + "\n" + "\n".join(data_lines)))
    df = df.loc[:, ~df.columns.str.startswith("Unnamed")]
    df["_time"] = pd.to_datetime(
        df["_time"], utc=True, errors="coerce", format="mixed"
    ).dt.tz_convert(None)
    df["_value"] = pd.to_numeric(df["_value"], errors="coerce")
    df = df.dropna(subset=["_time", "_value", "_measurement"])
    return df


def get_timeseries(df: pd.DataFrame, measurement: str,
                   flavor: str = None) -> pd.DataFrame:
    """Extract a time series for a specific measurement."""
    sub = df[df["_measurement"] == measurement].copy()
    if flavor and "flavor" in sub.columns:
        sub = sub[sub["flavor"] == flavor]
    return sub.sort_values("_time").reset_index(drop=True)


def get_stat(df: pd.DataFrame, measurement: str) -> float:
    """Get the single summary stat value for a measurement."""
    sub = df[df["_measurement"] == measurement]["_value"].dropna()
    return float(sub.iloc[0]) if not sub.empty else None


def elapsed_seconds(df: pd.DataFrame, col: str = "_time") -> pd.Series:
    """Convert timestamps to seconds from experiment start."""
    t0 = df[col].min()
    return (df[col] - t0).dt.total_seconds()


# ── Metrics Calculation ───────────────────────────────────────────────────────

def calculate_mttr(chaos_df: pd.DataFrame, baseline_df: pd.DataFrame,
                   kill_time_s: float, recovery_threshold: float = 0.1) -> dict:
    """
    Calculate MTTR (Mean Time To Recovery).

    Method:
    1. Get baseline KO rate (responses with flavor='ko' as % of all responses)
    2. Find the point after the kill where KO rate returns to within
       `recovery_threshold` (default 10%) above baseline
    3. MTTR = that timestamp - kill timestamp

    Returns dict with:
        kill_time_s: when the pod was killed
        recovery_time_s: when the system recovered
        mttr_s: recovery time in seconds
        peak_ko_rate: maximum KO rate observed during failure
        baseline_ko_rate: KO rate before failure
    """
    result = {
        "kill_time_s": kill_time_s,
        "recovery_time_s": None,
        "mttr_s": None,
        "peak_ko_rate": None,
        "baseline_ko_rate": None,
        "no_recovery_detected": False,
    }

    # Get baseline KO rate
    baseline_ko = get_timeseries(baseline_df, "responses", "ko")
    baseline_all = get_timeseries(baseline_df, "responses", "all")

    if baseline_ko.empty or baseline_all.empty:
        result["no_recovery_detected"] = True
        return result

    # Baseline KO rate as fraction of total responses
    b_ko_total = baseline_ko["_value"].sum()
    b_all_total = baseline_all["_value"].sum()
    baseline_ko_rate = b_ko_total / b_all_total if b_all_total > 0 else 0
    result["baseline_ko_rate"] = baseline_ko_rate

    # Chaos KO rate over time
    chaos_ko = get_timeseries(chaos_df, "responses", "ko")
    chaos_all = get_timeseries(chaos_df, "responses", "all")

    if chaos_ko.empty or chaos_all.empty:
        result["no_recovery_detected"] = True
        return result

    # Align on elapsed seconds
    t0 = chaos_ko["_time"].min()
    chaos_ko = chaos_ko.copy()
    chaos_ko["elapsed"] = (chaos_ko["_time"] - t0).dt.total_seconds()

    chaos_all_t = chaos_all.copy()
    chaos_all_t["elapsed"] = (chaos_all_t["_time"] - t0).dt.total_seconds()

    # Merge ko and all on elapsed time
    merged = pd.merge_asof(
        chaos_ko.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "ko"}),
        chaos_all_t.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "all"}),
        on="elapsed", direction="nearest", tolerance=5
    ).dropna()

    merged["ko_rate"] = merged["ko"] / merged["all"].replace(0, np.nan)
    merged = merged.dropna(subset=["ko_rate"])

    # Peak KO rate after kill
    post_kill = merged[merged["elapsed"] >= kill_time_s]
    if post_kill.empty:
        result["no_recovery_detected"] = True
        return result

    result["peak_ko_rate"] = float(post_kill["ko_rate"].max())

    # Find recovery: first point after kill where ko_rate <= baseline + threshold
    recovery_level = baseline_ko_rate + recovery_threshold
    recovered = post_kill[post_kill["ko_rate"] <= recovery_level]

    if recovered.empty:
        result["no_recovery_detected"] = True
        return result

    recovery_elapsed = float(recovered["elapsed"].iloc[0])
    result["recovery_time_s"] = recovery_elapsed
    result["mttr_s"] = recovery_elapsed - kill_time_s

    return result


def calculate_impact(chaos_df: pd.DataFrame, baseline_df: pd.DataFrame,
                     kill_time_s: float, recovery_time_s: float = None) -> dict:
    """Calculate impact metrics during the failure window."""
    result = {}

    # Total requests comparison
    baseline_total = get_stat(baseline_df, "numberOfRequestsTotal")
    chaos_total = get_stat(chaos_df, "numberOfRequestsTotal")
    baseline_ok = get_stat(baseline_df, "numberOfRequestsOk")
    chaos_ok = get_stat(chaos_df, "numberOfRequestsOk")
    baseline_ko = get_stat(baseline_df, "numberOfRequestsKo")
    chaos_ko = get_stat(chaos_df, "numberOfRequestsKo")

    result["baseline_total_requests"] = baseline_total
    result["chaos_total_requests"] = chaos_total
    result["baseline_ok_requests"] = baseline_ok
    result["chaos_ok_requests"] = chaos_ok
    result["baseline_ko_requests"] = baseline_ko
    result["chaos_ko_requests"] = chaos_ko

    # Extra failures caused by the chaos
    if baseline_ko is not None and chaos_ko is not None:
        result["additional_failures"] = chaos_ko - baseline_ko
    else:
        result["additional_failures"] = None

    # Failure rate comparison
    baseline_fail_pct = get_stat(baseline_df, "group4Percentage")
    chaos_fail_pct = get_stat(chaos_df, "group4Percentage")
    result["baseline_failure_rate_pct"] = baseline_fail_pct
    result["chaos_failure_rate_pct"] = chaos_fail_pct
    if baseline_fail_pct is not None and chaos_fail_pct is not None:
        result["failure_rate_increase_pct"] = chaos_fail_pct - baseline_fail_pct

    # Response time impact
    result["baseline_p95_s"] = (get_stat(baseline_df, "percentiles3") or 0) / 1000
    result["chaos_p95_s"] = (get_stat(chaos_df, "percentiles3") or 0) / 1000
    result["baseline_p99_s"] = (get_stat(baseline_df, "percentiles4") or 0) / 1000
    result["chaos_p99_s"] = (get_stat(chaos_df, "percentiles4") or 0) / 1000

    return result


# ── Visualization ─────────────────────────────────────────────────────────────

def plot_mttr(baseline_df, chaos_dfs, chaos_labels, kill_time_s, mttr_results,
              output_path):
    """Plot KO rate over time for all runs with MTTR annotation."""
    fig, ax = plt.subplots(figsize=(12, 5))
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(PANEL)
    ax.set_title("KO Response Rate Over Time — MTTR Analysis",
                 color=TEXT, fontsize=12, fontweight="bold", pad=8)
    ax.tick_params(colors=TEXT, labelsize=8)
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID)
    ax.grid(True, color=GRID, linewidth=0.5, alpha=0.6)

    # Plot baseline KO rate
    b_ko = get_timeseries(baseline_df, "responses", "ko")
    b_all = get_timeseries(baseline_df, "responses", "all")
    if not b_ko.empty and not b_all.empty:
        t0 = b_ko["_time"].min()
        b_ko["elapsed"] = (b_ko["_time"] - t0).dt.total_seconds()
        b_all_t = b_all.copy()
        b_all_t["elapsed"] = (b_all_t["_time"] - t0).dt.total_seconds()
        merged_b = pd.merge_asof(
            b_ko.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "ko"}),
            b_all_t.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "all"}),
            on="elapsed", direction="nearest", tolerance=5
        ).dropna()
        merged_b["ko_rate_pct"] = (merged_b["ko"] / merged_b["all"].replace(0, np.nan)) * 100
        ax.plot(merged_b["elapsed"], merged_b["ko_rate_pct"],
                color=COLOR_BASELINE, linewidth=1.5, linestyle="--",
                label="Baseline", alpha=0.7)

    # Plot chaos runs
    for i, (chaos_df, label, mttr) in enumerate(
            zip(chaos_dfs, chaos_labels, mttr_results)):
        c_ko = get_timeseries(chaos_df, "responses", "ko")
        c_all = get_timeseries(chaos_df, "responses", "all")
        if c_ko.empty or c_all.empty:
            continue
        t0 = c_ko["_time"].min()
        c_ko["elapsed"] = (c_ko["_time"] - t0).dt.total_seconds()
        c_all_t = c_all.copy()
        c_all_t["elapsed"] = (c_all_t["_time"] - t0).dt.total_seconds()
        merged_c = pd.merge_asof(
            c_ko.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "ko"}),
            c_all_t.sort_values("elapsed")[["elapsed", "_value"]].rename(columns={"_value": "all"}),
            on="elapsed", direction="nearest", tolerance=5
        ).dropna()
        merged_c["ko_rate_pct"] = (merged_c["ko"] / merged_c["all"].replace(0, np.nan)) * 100

        color = COLOR_CHAOS[i % len(COLOR_CHAOS)]
        ax.plot(merged_c["elapsed"], merged_c["ko_rate_pct"],
                color=color, linewidth=2, label=label)

        # MTTR annotation
        if mttr["mttr_s"] is not None:
            ax.axvline(x=kill_time_s, color="white", linewidth=1,
                       linestyle=":", alpha=0.6)
            ax.axvline(x=mttr["recovery_time_s"], color=color,
                       linewidth=1, linestyle=":", alpha=0.6)
            ax.annotate(
                f"MTTR: {mttr['mttr_s']:.0f}s",
                xy=(mttr["recovery_time_s"], mttr["peak_ko_rate"] * 50),
                color=color, fontsize=8,
                xytext=(10, 0), textcoords="offset points"
            )

    # Kill time line
    ax.axvline(x=kill_time_s, color="white", linewidth=1.5,
               linestyle="--", alpha=0.8, label=f"Pod killed (t={kill_time_s}s)")

    ax.set_xlabel("Time (seconds from experiment start)", color=TEXT, fontsize=9)
    ax.set_ylabel("KO Response Rate (%)", color=TEXT, fontsize=9)
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


def print_report(kill_time_s, mttr_results, impact_results, chaos_labels,
                 consistency_files=None):
    """Print a comprehensive resilience metrics report."""

    print("\n" + "=" * 70)
    print("RESILIENCE METRICS REPORT")
    print("=" * 70)
    print(f"Failure injected at: t = {kill_time_s}s\n")

    for label, mttr, impact in zip(chaos_labels, mttr_results, impact_results):
        print(f"─── {label} ─────────────────────────────────")

        # MTTR
        print("\n  RECOVERY (MTTR)")
        if mttr["mttr_s"] is not None:
            print(f"    Time to recovery:      {mttr['mttr_s']:.0f}s")
            print(f"    Recovery timestamp:    t = {mttr['recovery_time_s']:.0f}s")
        else:
            print(f"    Time to recovery:      No recovery detected within experiment")
        if mttr["baseline_ko_rate"] is not None:
            print(f"    Baseline KO rate:      {mttr['baseline_ko_rate']*100:.1f}%")
        if mttr["peak_ko_rate"] is not None:
            print(f"    Peak KO rate:          {mttr['peak_ko_rate']*100:.1f}%")

        # Impact
        print("\n  IMPACT (during experiment)")
        if impact.get("baseline_failure_rate_pct") is not None:
            print(f"    Baseline failure rate: {impact['baseline_failure_rate_pct']:.1f}%")
        if impact.get("chaos_failure_rate_pct") is not None:
            print(f"    Chaos failure rate:    {impact['chaos_failure_rate_pct']:.1f}%")
        if impact.get("failure_rate_increase_pct") is not None:
            print(f"    Failure rate increase: +{impact['failure_rate_increase_pct']:.1f}%")
        if impact.get("additional_failures") is not None:
            print(f"    Additional failures:   {impact['additional_failures']:.0f} requests")
        print(f"    Baseline P95:          {impact.get('baseline_p95_s', 0):.2f}s")
        print(f"    Chaos P95:             {impact.get('chaos_p95_s', 0):.2f}s")
        print(f"    Baseline P99:          {impact.get('baseline_p99_s', 0):.2f}s")
        print(f"    Chaos P99:             {impact.get('chaos_p99_s', 0):.2f}s")
        print()

    # Consistency (if provided)
    if consistency_files:
        print("─── DATA CONSISTENCY ─────────────────────────────────")
        for label, cf in zip(["Baseline"] + chaos_labels, consistency_files):
            if cf and Path(cf).exists():
                with open(cf) as f:
                    data = json.load(f)
                before = data.get("before", {}).get("inventoryCount", "N/A")
                after = data.get("after", {}).get("inventoryCount", "N/A")
                consumed = (before - after) if isinstance(before, int) and isinstance(after, int) else "N/A"
                print(f"  {label}: {consumed} items consumed ({before} → {after})")

    print("\n" + "=" * 70 + "\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Calculate MTTR and resilience metrics from InfluxDB CSV exports.")
    parser.add_argument("--baseline", required=True,
                        help="Path to baseline results.csv")
    parser.add_argument("--chaos", nargs="+", required=True,
                        help="Path(s) to chaos experiment results.csv")
    parser.add_argument("--labels", nargs="+",
                        help="Labels for each chaos run")
    parser.add_argument("--kill-time", type=float, default=120.0,
                        help="Seconds from experiment start when pod was killed (default: 120)")
    parser.add_argument("--recovery-threshold", type=float, default=0.10,
                        help="KO rate delta above baseline to consider recovered (default: 0.10 = 10%%)")
    parser.add_argument("--output", default="mttr_analysis.png",
                        help="Output filename for MTTR plot")
    parser.add_argument("--output-dir", default=".",
                        help="Output directory")
    parser.add_argument("--consistency", nargs="+",
                        help="Path(s) to consistency.json files (baseline first, then chaos)")
    args = parser.parse_args()

    labels = args.labels if args.labels else [f"Chaos Run {i+1}" for i in range(len(args.chaos))]
    if len(labels) != len(args.chaos):
        print("ERROR: --labels count must match --chaos count", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"\nLoading baseline: {args.baseline}")
    baseline_df = parse_csv(args.baseline)

    chaos_dfs = []
    for path, label in zip(args.chaos, labels):
        print(f"Loading chaos run: {label} — {path}")
        chaos_dfs.append(parse_csv(path))

    # Calculate metrics
    mttr_results = []
    impact_results = []
    for chaos_df, label in zip(chaos_dfs, labels):
        print(f"\nCalculating metrics for: {label}")
        mttr = calculate_mttr(chaos_df, baseline_df, args.kill_time,
                              args.recovery_threshold)
        impact = calculate_impact(chaos_df, baseline_df, args.kill_time,
                                  mttr.get("recovery_time_s"))
        mttr_results.append(mttr)
        impact_results.append(impact)

    # Print report
    print_report(args.kill_time, mttr_results, impact_results, labels,
                 args.consistency)

    # Plot
    out = Path(args.output_dir) / args.output
    print("Generating MTTR plot...")
    plot_mttr(baseline_df, chaos_dfs, labels, args.kill_time,
              mttr_results, str(out))

    print("Done!")


if __name__ == "__main__":
    main()