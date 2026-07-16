#!/usr/bin/env python3
"""
MiSArch Resilience Metrics Calculator
======================================
Calculates meaningful resilience metrics from InfluxDB CSV exports
for pod kill chaos experiments.

Metrics reported:
  - Failure rate increase vs baseline
  - Additional KO requests caused by chaos
  - P95 / P99 / Max response time change
  - Data consistency (orders placed via inventory delta)

Usage:
    python3 resilience_metrics.py \
        --baseline baseline/results.csv \
        --chaos order_kill_1rep/results.csv order_kill_2rep/results.csv \
        --labels "1 Replica" "2 Replicas" \
        --consistency baseline/consistency.json \
                      order_kill_1rep/consistency.json \
                      order_kill_2rep/consistency.json

Requirements:
    pip install pandas matplotlib
"""

import argparse
import sys
import io
import os
import json
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path


# ── Style — matches plot_results.py scientific paper theme ────────────────────
BG     = "#ffffff"
PANEL  = "#ffffff"
TEXT   = "#000000"
GRID   = "#b0b0b0"
COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#9467bd", "#8c564b"]

matplotlib.rcParams.update({
    "font.family":        "serif",
    "font.size":          10,
    "axes.titlesize":     11,
    "axes.labelsize":     9,
    "xtick.labelsize":    8,
    "ytick.labelsize":    8,
    "legend.fontsize":    8,
    "figure.facecolor":   BG,
    "axes.facecolor":     PANEL,
    "savefig.facecolor":  BG,
    "grid.color":         GRID,
    "grid.linestyle":     "--",
    "axes.edgecolor":     "#000000",
})


# ── CSV Parsing ───────────────────────────────────────────────────────────────

def parse_csv(filepath: str) -> pd.DataFrame:
    with open(filepath, "rb") as f:
        content = f.read().decode("utf-8")

    lines = content.splitlines()
    data_lines, header = [], None
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


def get_stat(df: pd.DataFrame, measurement: str) -> float | None:
    sub = df[df["_measurement"] == measurement]["_value"].dropna()
    return float(sub.iloc[0]) if not sub.empty else None


def get_timeseries(df: pd.DataFrame, measurement: str, flavor: str = None) -> pd.DataFrame:
    sub = df[df["_measurement"] == measurement].copy()
    if flavor:
        if "flavor" in sub.columns:
            sub = sub[sub["flavor"] == flavor]
        elif "scenario" in sub.columns:
            sub = sub[sub["scenario"] == flavor]
    return sub.sort_values("_time").reset_index(drop=True)


# ── Impact Metrics ────────────────────────────────────────────────────────────

def calculate_impact(chaos_df: pd.DataFrame, baseline_df: pd.DataFrame) -> dict:
    result = {}

    result["baseline_total"]   = get_stat(baseline_df, "numberOfRequestsTotal")
    result["chaos_total"]      = get_stat(chaos_df,    "numberOfRequestsTotal")
    result["baseline_ok"]      = get_stat(baseline_df, "numberOfRequestsOk")
    result["chaos_ok"]         = get_stat(chaos_df,    "numberOfRequestsOk")
    result["baseline_ko"]      = get_stat(baseline_df, "numberOfRequestsKo")
    result["chaos_ko"]         = get_stat(chaos_df,    "numberOfRequestsKo")

    b_ko = result["baseline_ko"] or 0
    c_ko = result["chaos_ko"]    or 0
    result["additional_failures"] = c_ko - b_ko

    b_fail = get_stat(baseline_df, "group4Percentage") or 0
    c_fail = get_stat(chaos_df,    "group4Percentage") or 0
    result["baseline_failure_pct"]  = b_fail
    result["chaos_failure_pct"]     = c_fail
    result["failure_rate_increase"] = c_fail - b_fail

    result["baseline_p95"] = (get_stat(baseline_df, "percentiles3") or 0) / 1000
    result["chaos_p95"]    = (get_stat(chaos_df,    "percentiles3") or 0) / 1000
    result["baseline_p99"] = (get_stat(baseline_df, "percentiles4") or 0) / 1000
    result["chaos_p99"]    = (get_stat(chaos_df,    "percentiles4") or 0) / 1000
    result["baseline_max"] = (get_stat(baseline_df, "maxResponseTime") or 0) / 1000
    result["chaos_max"]    = (get_stat(chaos_df,    "maxResponseTime") or 0) / 1000

    result["p95_increase"] = result["chaos_p95"] - result["baseline_p95"]
    result["p99_increase"] = result["chaos_p99"] - result["baseline_p99"]
    result["max_increase"] = result["chaos_max"] - result["baseline_max"]

    return result


def load_consistency(filepath: str) -> dict | None:
    if not filepath or not Path(filepath).exists():
        return None
    with open(filepath) as f:
        return json.load(f)


# ── Visualization ─────────────────────────────────────────────────────────────

def plot_failure_rate(labels, impacts, baseline_label, output_path):
    """Bar chart showing failure rate increase for each chaos run."""
    n = len(labels)
    fig, ax = plt.subplots(figsize=(7, 5))
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(PANEL)
    ax.set_title("Failure Rate Increase vs Baseline (%)", color=TEXT,
                 fontsize=11, fontweight="semibold", pad=8)
    ax.tick_params(colors=TEXT, labelsize=8)
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID)
    ax.grid(True, color=GRID, linestyle="--", linewidth=0.5, alpha=0.8, axis="y")

    vals = [imp.get("failure_rate_increase", 0) for imp in impacts]
    bars = ax.bar(range(n), vals,
                  color=COLORS[:n], alpha=0.85, edgecolor="#000000", linewidth=0.5)

    # Value labels on bars
    for bar, val in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.05,
                f"+{val:.1f}%", ha="center", va="bottom", fontsize=9, color=TEXT)

    ax.set_xticks(range(n))
    ax.set_xticklabels([l.replace(" (", "\n(") for l in labels], color=TEXT, fontsize=8)
    ax.set_ylabel("Failure Rate Increase (%)", color=TEXT, fontsize=9)
    ax.axhline(y=0, color="black", linewidth=0.8)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


def plot_response_time_comparison(labels, impacts, baseline_label, output_path):
    """Grouped bar chart: P95, P99, Max for baseline vs each chaos run."""
    categories = ["P95", "P99", "Max"]
    n_groups = 1 + len(impacts)  # baseline + each chaos run
    all_labels = [baseline_label] + labels
    x = np.arange(len(categories))
    width = 0.8 / n_groups

    fig, ax = plt.subplots(figsize=(10, 5))
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(PANEL)
    ax.set_title("Response Time: Baseline vs Chaos Runs", color=TEXT, fontsize=11, fontweight="bold")
    ax.tick_params(colors=TEXT, labelsize=8)
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID)
    ax.grid(True, color=GRID, linewidth=0.5, alpha=0.5, axis="y")

    baseline_vals = [
        impacts[0]["baseline_p95"],
        impacts[0]["baseline_p99"],
        impacts[0]["baseline_max"],
    ] if impacts else [0, 0, 0]

    colors_rt = ["#4CAF50"] + COLORS[:len(impacts)]

    # Baseline bars
    ax.bar(x + 0 * width, baseline_vals, width,
           label=baseline_label, color="#4CAF50", alpha=0.85)

    # Chaos bars
    for i, (label, imp) in enumerate(zip(labels, impacts)):
        vals = [imp["chaos_p95"], imp["chaos_p99"], imp["chaos_max"]]
        ax.bar(x + (i + 1) * width, vals, width,
               label=label, color=COLORS[i % len(COLORS)], alpha=0.85)

    ax.set_xticks(x + width * (n_groups - 1) / 2)
    ax.set_xticklabels(categories, color=TEXT, fontsize=9)
    ax.set_ylabel("seconds", color=TEXT, fontsize=9)
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Summary Table ─────────────────────────────────────────────────────────────

def print_report(labels, impacts, baseline_label, consistency_files=None):
    print("\n" + "=" * 75)
    print("RESILIENCE IMPACT REPORT")
    print("=" * 75)
    col_w = 22

    header = f"{'Metric':<32}" + "".join(f"{l[:col_w-2]:<{col_w}}" for l in labels)
    print(header)
    print("-" * 75)

    def fmt(val, div=1, unit="", sign=False):
        if val is None:
            return "N/A"
        v = val / div
        prefix = "+" if sign and v > 0 else ""
        return f"{prefix}{v:.1f}{unit}"

    rows = [
        ("Baseline Failure Rate",     "baseline_failure_pct",  1,    "%",  False),
        ("Chaos Failure Rate",         "chaos_failure_pct",     1,    "%",  False),
        ("Failure Rate Increase",      "failure_rate_increase", 1,    "%",  True),
        ("Additional KO Requests",     "additional_failures",   1,    "",   True),
        ("Baseline P95",               "baseline_p95",          1,    "s",  False),
        ("Chaos P95",                  "chaos_p95",             1,    "s",  False),
        ("P95 Increase",               "p95_increase",          1,    "s",  True),
        ("Baseline P99",               "baseline_p99",          1,    "s",  False),
        ("Chaos P99",                  "chaos_p99",             1,    "s",  False),
        ("P99 Increase",               "p99_increase",          1,    "s",  True),
        ("Max Response Time (chaos)",  "chaos_max",             1,    "s",  False),
        ("Max Increase",               "max_increase",          1,    "s",  True),
    ]

    for label, key, div, unit, sign in rows:
        row = f"{label:<32}"
        for imp in impacts:
            row += f"{fmt(imp.get(key), div, unit, sign):<{col_w}}"
        print(row)

    # Data consistency
    if consistency_files:
        print()
        print(f"{'DATA CONSISTENCY (orders placed)':<32}", end="")
        all_files = consistency_files
        labels_with_baseline = [baseline_label] + labels

        baseline_cons = load_consistency(all_files[0]) if all_files else None
        baseline_orders = None
        if baseline_cons:
            b = baseline_cons.get("before", {}).get("inventoryCount", 0)
            a = baseline_cons.get("after", {}).get("inventoryCount", 0)
            baseline_orders = b - a
            print(f"Baseline: {baseline_orders} orders", end="  ")

        print()
        row = f"{'Orders placed (chaos runs)':<32}"
        for i, cf in enumerate(all_files[1:]):
            cons = load_consistency(cf)
            if cons:
                b = cons.get("before", {}).get("inventoryCount", 0)
                a = cons.get("after", {}).get("inventoryCount", 0)
                orders = b - a
                pct = ((orders - baseline_orders) / baseline_orders * 100) if baseline_orders else 0
                sign = "+" if pct >= 0 else ""
                row += f"{orders} ({sign}{pct:.1f}%){'':<{col_w - len(str(orders)) - 10}}"
            else:
                row += f"{'N/A':<{col_w}}"
        print(row)

    print("=" * 75 + "\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Calculate resilience impact metrics from InfluxDB CSV exports.")
    parser.add_argument("--baseline", required=True)
    parser.add_argument("--chaos", nargs="+", required=True)
    parser.add_argument("--labels", nargs="+")
    parser.add_argument("--baseline-label", default="Baseline")
    parser.add_argument("--output", default="impact.png")
    parser.add_argument("--output-dir", default=".")
    parser.add_argument("--consistency", nargs="+",
                        help="consistency.json files: baseline first, then chaos runs")
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
        if not Path(path).exists():
            print(f"ERROR: File not found: {path}", file=sys.stderr)
            sys.exit(1)
        print(f"Loading: {label} — {path}")
        chaos_dfs.append(parse_csv(path))

    impacts = [calculate_impact(cdf, baseline_df) for cdf in chaos_dfs]

    print_report(labels, impacts, args.baseline_label, args.consistency)

    out = Path(args.output_dir) / Path(args.output).stem
    print("Generating failure rate chart...")
    plot_failure_rate(labels, impacts, args.baseline_label,
                      str(out) + "_failure_rate.png")
    print("Generating response time chart...")
    plot_response_time_comparison(labels, impacts, args.baseline_label,
                                  str(out) + "_response_times.png")
    print("Done!")


if __name__ == "__main__":
    main()