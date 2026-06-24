#!/usr/bin/env python3
"""
MiSArch Experiment Results Visualizer
======================================
Reads exported CSV files from InfluxDB and produces comparison plots
for before/after resilience refactoring analysis.

Usage:
    # Single experiment run:
    python3 plot_results.py --files experiment1.csv --labels "Baseline"

    # Compare multiple runs side by side:
    python3 plot_results.py \
        --files baseline.csv chaos_no_fix.csv chaos_with_fix.csv \
        --labels "Baseline" "Inventory Failure (Before Fix)" "Inventory Failure (After Fix)" \
        --output comparison.png

Requirements:
    pip install pandas matplotlib
"""

import argparse
import sys
import os
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
from pathlib import Path


# ── Metric column detection ──────────────────────────────────────────────────

# These are the field names Gatling writes to InfluxDB.
# The CSV export from InfluxDB uses "_field" and "_value" columns.
METRICS_OF_INTEREST = {
    "percentageFailedRequests":        "Failed Requests (%)",
    "meanResponseTime":                "Mean Response Time (ms)",
    "percentageRequestsUnder800ms":    "Requests < 800ms (%)",
    "maxResponseTime":                 "Max Response Time (ms)",
    "percentMeanRequestsPerSecondOK":  "Successful Req/sec (%)",
    "percentMeanRequestsPerSecondKO":  "Failed Req/sec (%)",
    "95thPercentileResponseTime":      "P95 Response Time (ms)",
    "99thPercentileResponseTime":      "P99 Response Time (ms)",
}

# Key metrics to show in the main dashboard (subset of above)
DASHBOARD_METRICS = [
    "percentageFailedRequests",
    "meanResponseTime",
    "95thPercentileResponseTime",
    "percentMeanRequestsPerSecondOK",
]


def load_csv(filepath: str) -> pd.DataFrame:
    """Load and normalise an InfluxDB CSV export."""
    path = Path(filepath)
    if not path.exists():
        print(f"ERROR: File not found: {filepath}", file=sys.stderr)
        sys.exit(1)

    df = pd.read_csv(filepath, comment="#")

    # InfluxDB exports can have two formats:
    # Format A: columns include _time, _field, _value (annotated CSV)
    # Format B: wide format where each metric is its own column
    if "_field" in df.columns and "_value" in df.columns:
        df = _parse_long_format(df)
    elif "_time" in df.columns:
        df = _parse_wide_format(df)
    else:
        print(f"WARNING: Unrecognised CSV format in {filepath}.", file=sys.stderr)
        print(f"  Columns found: {list(df.columns)}", file=sys.stderr)
        print("  Attempting to use file as-is.", file=sys.stderr)

    return df


def _parse_long_format(df: pd.DataFrame) -> pd.DataFrame:
    """Convert InfluxDB long-format (annotated) CSV to wide format."""
    # Drop InfluxDB annotation rows if present
    if "#datatype" in df.columns or df.iloc[0, 0] == "#datatype":
        df = df[~df.iloc[:, 0].astype(str).str.startswith("#")]

    df = df[df["_field"].isin(METRICS_OF_INTEREST.keys())].copy()
    df["_time"] = pd.to_datetime(df["_time"], utc=True, errors="coerce")
    df["_value"] = pd.to_numeric(df["_value"], errors="coerce")

    wide = df.pivot_table(
        index="_time", columns="_field", values="_value", aggfunc="mean"
    ).reset_index()
    wide.rename(columns={"_time": "time"}, inplace=True)
    return wide


def _parse_wide_format(df: pd.DataFrame) -> pd.DataFrame:
    """Normalise InfluxDB wide-format CSV."""
    df = df.copy()
    df.rename(columns={"_time": "time"}, inplace=True)
    df["time"] = pd.to_datetime(df["time"], utc=True, errors="coerce")
    for col in df.columns:
        if col != "time":
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


# ── Plotting ─────────────────────────────────────────────────────────────────

COLORS = ["#2196F3", "#F44336", "#4CAF50", "#FF9800", "#9C27B0"]
LINESTYLES = ["-", "--", "-.", ":", "-"]


def plot_metric(ax, dfs, labels, metric_key, metric_label):
    """Plot one metric across all experiment runs on a single axis."""
    plotted = False
    for i, (df, label) in enumerate(zip(dfs, labels)):
        if metric_key not in df.columns:
            continue
        series = df[["time", metric_key]].dropna()
        if series.empty:
            continue
        # Normalise time to seconds from experiment start for easier comparison
        t0 = series["time"].min()
        series = series.copy()
        series["elapsed_s"] = (series["time"] - t0).dt.total_seconds()
        ax.plot(
            series["elapsed_s"],
            series[metric_key],
            color=COLORS[i % len(COLORS)],
            linestyle=LINESTYLES[i % len(LINESTYLES)],
            linewidth=2,
            label=label,
            alpha=0.85,
        )
        plotted = True

    ax.set_title(metric_label, fontsize=11, fontweight="bold", pad=8)
    ax.set_xlabel("Time (seconds from start)", fontsize=9)
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=8)
    if not plotted:
        ax.text(
            0.5, 0.5, "No data available",
            ha="center", va="center", transform=ax.transAxes,
            fontsize=10, color="grey"
        )
    return plotted


def plot_dashboard(dfs, labels, output_path, title):
    """Generate the main 4-panel comparison dashboard."""
    fig, axes = plt.subplots(2, 2, figsize=(14, 9))
    fig.suptitle(title, fontsize=14, fontweight="bold", y=1.01)

    axes_flat = axes.flatten()
    for i, metric_key in enumerate(DASHBOARD_METRICS):
        metric_label = METRICS_OF_INTEREST.get(metric_key, metric_key)
        plot_metric(axes_flat[i], dfs, labels, metric_key, metric_label)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight")
    print(f"  Saved: {output_path}")
    plt.close()


def plot_all_metrics(dfs, labels, output_dir, prefix):
    """Generate one PNG per metric for detailed analysis."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    for metric_key, metric_label in METRICS_OF_INTEREST.items():
        fig, ax = plt.subplots(figsize=(10, 5))
        plotted = plot_metric(ax, dfs, labels, metric_key, metric_label)
        if plotted:
            filename = output_dir / f"{prefix}_{metric_key}.png"
            plt.tight_layout()
            plt.savefig(filename, dpi=150, bbox_inches="tight")
            print(f"  Saved: {filename}")
        plt.close()


def print_summary_table(dfs, labels):
    """Print a text summary table of key statistics."""
    print("\n" + "=" * 70)
    print("EXPERIMENT SUMMARY")
    print("=" * 70)

    key_metrics = {
        "percentageFailedRequests": "Failed Requests (%)",
        "meanResponseTime":         "Mean Response Time (ms)",
        "95thPercentileResponseTime": "P95 Response Time (ms)",
        "percentMeanRequestsPerSecondOK": "Successful Req/sec (%)",
    }

    header = f"{'Metric':<35}" + "".join(f"{l[:15]:<18}" for l in labels)
    print(header)
    print("-" * 70)

    for metric_key, metric_label in key_metrics.items():
        row = f"{metric_label:<35}"
        for df in dfs:
            if metric_key in df.columns:
                val = df[metric_key].mean()
                row += f"{val:>10.1f}        "
            else:
                row += f"{'N/A':>10}        "
        print(row)

    print("=" * 70 + "\n")


# ── CLI ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Visualise MiSArch experiment results from InfluxDB CSV exports.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        "--files", "-f",
        nargs="+",
        required=True,
        help="One or more CSV files exported from InfluxDB",
    )
    parser.add_argument(
        "--labels", "-l",
        nargs="+",
        help="Labels for each file (default: filename). Must match number of files.",
    )
    parser.add_argument(
        "--output", "-o",
        default="experiment_comparison.png",
        help="Output filename for the dashboard plot (default: experiment_comparison.png)",
    )
    parser.add_argument(
        "--output-dir",
        default="plots",
        help="Directory for individual metric plots (default: plots/)",
    )
    parser.add_argument(
        "--title",
        default="MiSArch Experiment Results",
        help="Title for the dashboard plot",
    )
    parser.add_argument(
        "--all-metrics",
        action="store_true",
        help="Also generate individual PNG for each metric",
    )
    parser.add_argument(
        "--summary",
        action="store_true",
        default=True,
        help="Print summary statistics table (default: True)",
    )

    args = parser.parse_args()

    # Validate labels
    labels = args.labels if args.labels else [Path(f).stem for f in args.files]
    if len(labels) != len(args.files):
        print(
            f"ERROR: --labels count ({len(labels)}) must match --files count ({len(args.files)})",
            file=sys.stderr,
        )
        sys.exit(1)

    # Load data
    print(f"\nLoading {len(args.files)} experiment file(s)...")
    dfs = []
    for filepath, label in zip(args.files, labels):
        print(f"  {label}: {filepath}")
        df = load_csv(filepath)
        dfs.append(df)
        print(f"    → {len(df)} rows, columns: {[c for c in df.columns if c != 'time']}")

    # Summary table
    if args.summary:
        print_summary_table(dfs, labels)

    # Dashboard plot
    print("Generating dashboard plot...")
    plot_dashboard(dfs, labels, args.output, args.title)

    # Individual metric plots
    if args.all_metrics:
        print("Generating individual metric plots...")
        prefix = Path(args.output).stem
        plot_all_metrics(dfs, labels, args.output_dir, prefix)

    print("\nDone!")


if __name__ == "__main__":
    main()
