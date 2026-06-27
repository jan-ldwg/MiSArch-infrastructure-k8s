#!/usr/bin/env python3
"""
MiSArch Experiment Results Visualizer
=======================================
Reads InfluxDB CSV exports from MiSArch Gatling experiments and produces
comparison dashboards matching the Grafana layout.

Usage:
    # Single experiment:
    python3 plot_results.py --files experiment1.csv --labels "Baseline"

    # Compare before/after refactoring:
    python3 plot_results.py \
        --files baseline.csv chaos_no_fix.csv chaos_with_fix.csv \
        --labels "Baseline" "Inventory Failure (No Fix)" "Inventory Failure (With Fix)" \
        --output comparison.png

Requirements:
    pip install pandas matplotlib
"""

import argparse
import sys
import io
import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from pathlib import Path

# ── Colors matching Grafana dark theme ───────────────────────────────────────
COLORS_RUNS   = ["#2196F3", "#F44336", "#4CAF50", "#FF9800", "#9C27B0"]
COLOR_OK      = "#4CAF50"   # green
COLOR_KO      = "#F44336"   # red
COLOR_ALL     = "#FF9800"   # orange
COLOR_ABORTED = "#2196F3"   # blue
COLOR_BUY     = "#FF9800"   # orange
LINESTYLES    = ["-", "--", "-.", ":", "-"]
BG_COLOR      = "#1a1a2e"
PANEL_COLOR   = "#16213e"
TEXT_COLOR    = "#e0e0e0"
GRID_COLOR    = "#333355"


# ── CSV Parsing ───────────────────────────────────────────────────────────────

def parse_influxdb_csv(filepath: str) -> dict:
    """
    Parse an InfluxDB annotated CSV export into a dict of DataFrames by measurement.
    InfluxDB exports consist of multiple table blocks separated by blank lines,
    each with #group/#datatype/#default annotation rows before the real header.
    """
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    blocks = content.strip().split("\n\n")
    all_dfs = []

    for block in blocks:
        lines = block.strip().split("\n")
        # Find the real header row (contains '_time' and '_value')
        header_idx = None
        for j, line in enumerate(lines):
            if "_time" in line and "_value" in line:
                header_idx = j
                break
        if header_idx is None:
            continue
        try:
            df = pd.read_csv(io.StringIO("\n".join(lines[header_idx:])))
            df = df.loc[:, ~df.columns.str.startswith("Unnamed")]
            df = df.dropna(subset=["_time", "_value", "_measurement"])
            df["_time"] = pd.to_datetime(df["_time"], utc=True, errors="coerce")
            df["_value"] = pd.to_numeric(df["_value"], errors="coerce")
            df = df.dropna(subset=["_time", "_value"])
            all_dfs.append(df)
        except Exception:
            continue

    if not all_dfs:
        print(f"ERROR: Could not parse any data from {filepath}", file=sys.stderr)
        sys.exit(1)

    combined = pd.concat(all_dfs, ignore_index=True)

    # Organise by measurement
    result = {}
    for meas, group in combined.groupby("_measurement"):
        result[meas] = group.copy().sort_values("_time").reset_index(drop=True)

    return result


# ── Plotting helpers ──────────────────────────────────────────────────────────

def style_ax(ax, title):
    ax.set_facecolor(PANEL_COLOR)
    ax.set_title(title, color=TEXT_COLOR, fontsize=10, fontweight="bold", pad=6)
    ax.tick_params(colors=TEXT_COLOR, labelsize=8)
    ax.xaxis.label.set_color(TEXT_COLOR)
    ax.yaxis.label.set_color(TEXT_COLOR)
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID_COLOR)
    ax.grid(True, color=GRID_COLOR, linewidth=0.5, alpha=0.7)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right")


def make_fig(nrows, ncols, title, figsize=None):
    if figsize is None:
        figsize = (7 * ncols, 4 * nrows)
    fig, axes = plt.subplots(nrows, ncols, figsize=figsize)
    fig.patch.set_facecolor(BG_COLOR)
    fig.suptitle(title, color=TEXT_COLOR, fontsize=13, fontweight="bold", y=1.01)
    return fig, axes


# ── Dashboard 1: Gatling Total (mirrors Image 6) ─────────────────────────────

def plot_gatling_total(data_list, labels, output_path):
    """
    Active users over time + Responses (ok/ko/all) — one panel per run,
    plus a combined comparison panel for ok responses.
    """
    n = len(data_list)
    fig, axes = make_fig(2, max(n, 1) + 1,
                         "Gatling Total — Active Users & Responses",
                         figsize=(7 * (n + 1), 8))
    if n == 1:
        axes = axes.reshape(2, -1)

    # Row 0: active users per run
    for i, (data, label) in enumerate(zip(data_list, labels)):
        ax = axes[0, i]
        style_ax(ax, f"Active Users — {label}")
        if "activeUsers" in data:
            df = data["activeUsers"]
            for scenario, grp in df.groupby("scenario"):
                color = COLOR_ABORTED if "aborted" in scenario.lower() else COLOR_BUY
                ax.plot(grp["_time"], grp["_value"],
                        color=color, linewidth=1.5, label=scenario.replace("Scenario", ""))
            ax.legend(fontsize=7, facecolor=PANEL_COLOR, labelcolor=TEXT_COLOR)
            ax.set_ylabel("Active Users", color=TEXT_COLOR, fontsize=8)

    # Row 0 last column: combined active users
    ax = axes[0, n]
    style_ax(ax, "Active Users — All Runs")
    for i, (data, label) in enumerate(zip(data_list, labels)):
        if "activeUsers" in data:
            df = data["activeUsers"]
            total = df.groupby("_time")["_value"].sum().reset_index()
            ax.plot(total["_time"], total["_value"],
                    color=COLORS_RUNS[i], linestyle=LINESTYLES[i],
                    linewidth=2, label=label)
    ax.legend(fontsize=7, facecolor=PANEL_COLOR, labelcolor=TEXT_COLOR)
    ax.set_ylabel("Active Users", color=TEXT_COLOR, fontsize=8)

    # Row 1: responses (ok/ko/all) per run
    for i, (data, label) in enumerate(zip(data_list, labels)):
        ax = axes[1, i]
        style_ax(ax, f"Responses — {label}")
        if "responses" in data:
            df = data["responses"]
            flavor_colors = {"all": COLOR_ALL, "ok": COLOR_OK, "ko": COLOR_KO}
            for flavor, grp in df.groupby("flavor"):
                ax.plot(grp["_time"], grp["_value"],
                        color=flavor_colors.get(flavor, "grey"),
                        linewidth=1.5, label=flavor, alpha=0.9)
            ax.legend(fontsize=7, facecolor=PANEL_COLOR, labelcolor=TEXT_COLOR)
            ax.set_ylabel("Responses/interval", color=TEXT_COLOR, fontsize=8)

    # Row 1 last column: KO responses comparison
    ax = axes[1, n]
    style_ax(ax, "Failed Responses — Comparison")
    for i, (data, label) in enumerate(zip(data_list, labels)):
        if "responses" in data:
            df = data["responses"]
            ko = df[df["flavor"] == "ko"]
            if not ko.empty:
                ax.plot(ko["_time"], ko["_value"],
                        color=COLORS_RUNS[i], linestyle=LINESTYLES[i],
                        linewidth=2, label=label)
    ax.legend(fontsize=7, facecolor=PANEL_COLOR, labelcolor=TEXT_COLOR)
    ax.set_ylabel("Failed Responses/interval", color=TEXT_COLOR, fontsize=8)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG_COLOR)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Dashboard 2: Per-request metrics (mirrors Images 4 & 5) ──────────────────

def plot_request_metrics(data_list, labels, output_path):
    """
    Per-request group counts (group1Count_*) — number of requests per endpoint.
    """
    # Collect all request-level measurements
    request_metrics = []
    for data in data_list:
        for meas in data:
            if meas.startswith("group1Count_") and meas not in request_metrics:
                request_metrics.append(meas)

    if not request_metrics:
        print("  No per-request metrics found, skipping request metrics dashboard.")
        return

    # Friendly names
    def friendly(m):
        return m.replace("group1Count_", "").replace("createordermuta", "createOrder") \
               .replace("createshoppingc", "createShoppingCart") \
               .replace("placeordermutat", "placeOrder") \
               .replace("paymentinformat", "paymentInfo") \
               .replace("shipmentmethods", "shipmentMethods")

    ncols = 3
    nrows = (len(request_metrics) + ncols - 1) // ncols
    fig, axes = make_fig(nrows, ncols,
                         "Request Counts per Endpoint",
                         figsize=(7 * ncols, 4 * nrows))
    axes_flat = axes.flatten() if hasattr(axes, "flatten") else [axes]

    for idx, meas in enumerate(sorted(request_metrics)):
        ax = axes_flat[idx]
        style_ax(ax, friendly(meas))
        for i, (data, label) in enumerate(zip(data_list, labels)):
            if meas in data:
                df = data[meas]
                ax.plot(df["_time"], df["_value"],
                        color=COLORS_RUNS[i], linestyle=LINESTYLES[i],
                        linewidth=1.5, label=label)
        ax.legend(fontsize=7, facecolor=PANEL_COLOR, labelcolor=TEXT_COLOR)
        ax.set_ylabel("Count", color=TEXT_COLOR, fontsize=8)

    for idx in range(len(request_metrics), len(axes_flat)):
        axes_flat[idx].set_visible(False)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG_COLOR)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Dashboard 3: Summary stats table ─────────────────────────────────────────

def print_summary(data_list, labels):
    print("\n" + "=" * 75)
    print("EXPERIMENT SUMMARY")
    print("=" * 75)
    header = f"{'Metric':<30}" + "".join(f"{l[:20]:<22}" for l in labels)
    print(header)
    print("-" * 75)

    def stat(data, meas, flavor=None, fn=None):
        if meas not in data:
            return "N/A"
        df = data[meas]
        if flavor:
            df = df[df.get("flavor", pd.Series()) == flavor] if "flavor" in df.columns else df
        vals = df["_value"].dropna()
        if vals.empty:
            return "N/A"
        if fn == "max":
            return f"{vals.max():.1f}"
        if fn == "mean":
            return f"{vals.mean():.1f}"
        return f"{vals.iloc[-1]:.1f}"  # last value

    metrics = [
        ("Total Active Users (peak)", "activeUsers", None, "max"),
        ("Requests all (total)",      "requests",    None, "max"),
        ("Responses OK (last)",       "responses",   "ok", "max"),
        ("Responses KO (last)",       "responses",   "ko", "max"),
    ]

    for label, meas, flavor, fn in metrics:
        row = f"{label:<30}"
        for data in data_list:
            val = stat(data, meas, flavor, fn)
            row += f"{val:<22}"
        print(row)

    print("=" * 75 + "\n")


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Visualise MiSArch Gatling experiment results from InfluxDB CSV exports.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--files", "-f", nargs="+", required=True,
                        help="One or more InfluxDB CSV export files")
    parser.add_argument("--labels", "-l", nargs="+",
                        help="Labels for each file (default: filename stem)")
    parser.add_argument("--output", "-o", default="gatling_total.png",
                        help="Output filename for the main dashboard (default: gatling_total.png)")
    parser.add_argument("--output-dir", default=".",
                        help="Output directory for all plots (default: current directory)")
    parser.add_argument("--all", action="store_true",
                        help="Generate all dashboards (total + per-request)")
    args = parser.parse_args()

    labels = args.labels if args.labels else [Path(f).stem for f in args.files]
    if len(labels) != len(args.files):
        print(f"ERROR: --labels count must match --files count", file=sys.stderr)
        sys.exit(1)

    os.makedirs(args.output_dir, exist_ok=True)

    print(f"\nLoading {len(args.files)} file(s)...")
    data_list = []
    for filepath, label in zip(args.files, labels):
        if not Path(filepath).exists():
            print(f"ERROR: File not found: {filepath}", file=sys.stderr)
            sys.exit(1)
        print(f"  {label}: {filepath}")
        data = parse_influxdb_csv(filepath)
        data_list.append(data)
        print(f"    → Measurements: {list(data.keys())[:8]}")

    print_summary(data_list, labels)

    out = Path(args.output_dir) / args.output
    print("Generating Gatling Total dashboard...")
    plot_gatling_total(data_list, labels, out)

    if args.all:
        req_out = Path(args.output_dir) / args.output.replace(".png", "_requests.png")
        print("Generating per-request metrics dashboard...")
        plot_request_metrics(data_list, labels, req_out)

    print("\nDone!")


if __name__ == "__main__":
    main()
