#!/usr/bin/env python3
"""
MiSArch Experiment Results Visualizer
=======================================
Reads InfluxDB CSV exports from MiSArch Gatling experiments and produces
dashboards matching the Grafana layout.

The CSV contains two types of data:
  1. Time series: activeUsers, requests, responses (plotted over time)
  2. Summary stats: response times, percentiles, request counts per endpoint
     (plotted as bar charts — single value per experiment run)

Usage:
    # Single experiment:
    python3 plot_results.py --files experiment.csv --labels "Baseline"

    # Compare before/after:
    python3 plot_results.py \\
        --files baseline.csv chaos.csv fixed.csv \\
        --labels "Baseline" "Failure (No Fix)" "Failure (With Fix)" \\
        --output results.png

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
import matplotlib.ticker as mticker
import numpy as np
from pathlib import Path

# ── Style ─────────────────────────────────────────────────────────────────────
BG = "#ffffff"
PANEL = "#ffffff"
TEXT = "#000000"
GRID = "#b0b0b0"
COLOR_OK = "#1f77b4"
COLOR_KO = "#d62728"
COLOR_ALL = "#7f7f7f"
COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#9467bd", "#8c564b"]
LSTYLES = ["-", "--", "-.", ":", "-"]

plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": ["Times New Roman", "Times", "Palatino", "serif"],
        "font.size": 10,
        "axes.titlesize": 11,
        "axes.labelsize": 10,
        "xtick.labelsize": 8,
        "ytick.labelsize": 8,
        "legend.fontsize": 8,
        "figure.facecolor": BG,
        "axes.facecolor": PANEL,
        "savefig.facecolor": BG,
        "grid.color": GRID,
        "grid.linestyle": "--",
        "grid.linewidth": 0.5,
        "axes.edgecolor": "#000000",
        "axes.linewidth": 0.8,
    }
)

ENDPOINT_NAMES = {
    "getadmintoken": "Get Admin Token",
    "createnewuser": "Create User",
    "getuserid": "Get User Id",
    "setpassword": "Set Password",
    "getbuyerrole": "Get Buyer Role",
    "getemployeerole": "Get Employee Role",
    "assignroles": "Assign Roles",
    "getaccesstoken": "Get Access Token",
    "frontpage": "Frontpage",
    "products": "Products",
    "product": "Product",
    "users": "Users",
    "addaddress": "Add Address",
    "address": "Get Address",
    "createshoppingc": "Create Cart",
    "shipmentmethods": "Shipment Methods",
    "paymentinformat": "Payment Info",
    "createordermuta": "Create Order",
    "placeordermutat": "Place Order",
}


# ── CSV Parsing ───────────────────────────────────────────────────────────────


def parse_influxdb_csv(filepath: str) -> dict:
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    blocks = content.strip().split("\n\n")
    all_dfs = []

    for block in blocks:
        lines = block.strip().split("\n")
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
            df["_time"] = pd.to_datetime(
                df["_time"], utc=True, errors="coerce"
            ).dt.tz_convert(None)
            df["_value"] = pd.to_numeric(df["_value"], errors="coerce")
            df = df.dropna(subset=["_time", "_value"])
            all_dfs.append(df)
        except Exception:
            continue

    if not all_dfs:
        print(f"ERROR: Could not parse any data from {filepath}", file=sys.stderr)
        sys.exit(1)

    combined = pd.concat(all_dfs, ignore_index=True)
    result = {}
    for meas, group in combined.groupby("_measurement"):
        result[meas] = group.copy().sort_values("_time").reset_index(drop=True)
    return result


def get_stat(data: dict, meas: str) -> float | None:
    if meas not in data:
        return None
    vals = data[meas]["_value"].dropna()
    return float(vals.iloc[0]) if not vals.empty else None


# ── Helpers ───────────────────────────────────────────────────────────────────


def style_ax(ax, title):
    ax.set_facecolor(PANEL)
    ax.set_title(title, color=TEXT, fontsize=11, fontweight="semibold", pad=8)
    ax.xaxis.label.set_color(TEXT)
    ax.yaxis.label.set_color(TEXT)
    ax.tick_params(colors=TEXT, labelsize=8, which="both")
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.grid(True, color=GRID, linestyle="--", linewidth=0.5, alpha=0.8)


def make_fig(nrows, ncols, title, figsize=None):
    fig, axes = plt.subplots(nrows, ncols, figsize=figsize or (7 * ncols, 4 * nrows))
    fig.patch.set_facecolor(BG)
    fig.suptitle(title, color=TEXT, fontsize=13, fontweight="bold", y=1.01)
    return fig, axes


# ── Dashboard 1: Time series ──────────────────────────────────────────────────


def plot_timeseries(data_list, labels, output_path):
    fig, axes = make_fig(2, 2, "Gatling Time Series", figsize=(14, 9))
    axes = axes.flatten()

    # Panel 0: Active users per run (all scenarios combined)
    ax = axes[0]
    style_ax(ax, "Active Users")
    for i, (data, label) in enumerate(zip(data_list, labels)):
        if "activeUsers" in data:
            df = data["activeUsers"]
            total = df.groupby("_time")["_value"].sum().reset_index()
            ax.plot(
                total["_time"],
                total["_value"],
                color=COLORS[i],
                linestyle=LSTYLES[i],
                linewidth=2,
                label=label,
            )
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)
    ax.set_ylabel("Active Users", color=TEXT, fontsize=8)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right", color=TEXT)

    # Panel 1: Active users by scenario (first run only)
    ax = axes[1]
    style_ax(ax, f"Active Users by Scenario — {labels[0]}")
    if "activeUsers" in data_list[0]:
        df = data_list[0]["activeUsers"]
        scenario_colors = {
            "abortedBuyProcessScenario": COLOR_ALL,
            "buyProcessScenario": COLOR_OK,
        }
        for scenario, grp in df.groupby("scenario"):
            color = scenario_colors.get(scenario, COLORS[0])
            name = "Aborted Buy" if "aborted" in scenario.lower() else "Buy Process"
            ax.plot(grp["_time"], grp["_value"], color=color, linewidth=1.5, label=name)
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)
    ax.set_ylabel("Active Users", color=TEXT, fontsize=8)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right", color=TEXT)

    # Panel 2: Responses ok/ko line plot (first run)
    ax = axes[2]
    style_ax(ax, f"Responses (ok/ko) — {labels[0]}")
    if "responses" in data_list[0]:
        df = data_list[0]["responses"]
        pivoted = df.pivot_table(
            index="_time", columns="flavor", values="_value", aggfunc="sum"
        )
        pivoted = pivoted.reindex(columns=["ok", "ko"]).fillna(0)
        time = pivoted.index

        ax.plot(
            time, pivoted["ok"], color=COLORS[0], linewidth=2, label="OK"
        )
        ax.plot(
            time, pivoted["ko"], color=COLOR_KO, linewidth=2, label="KO"
        )
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)
    ax.set_ylabel("Responses / interval", color=TEXT, fontsize=8)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right", color=TEXT)

    # Panel 3: KO responses comparison across all runs
    ax = axes[3]
    style_ax(ax, "Failed Responses — Comparison")
    for i, (data, label) in enumerate(zip(data_list, labels)):
        if "responses" in data:
            df = data["responses"]
            ko = df[df["flavor"] == "ko"]
            if not ko.empty:
                ax.plot(
                    ko["_time"],
                    ko["_value"],
                    color=COLORS[i],
                    linestyle=LSTYLES[i],
                    linewidth=2,
                    label=label,
                )
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)
    ax.set_ylabel("Failed Responses / interval", color=TEXT, fontsize=8)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%H:%M"))
    plt.setp(ax.xaxis.get_majorticklabels(), rotation=30, ha="right", color=TEXT)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Dashboard 2: Response time summary (bar charts) ──────────────────────────


def plot_response_times(data_list, labels, output_path):
    endpoints = list(ENDPOINT_NAMES.keys())
    endpoint_labels = [ENDPOINT_NAMES[e] for e in endpoints]
    n_runs = len(data_list)
    x = np.arange(len(endpoints))
    width = 0.8 / n_runs

    fig, axes = make_fig(2, 2, "Response Time Summary per Endpoint", figsize=(16, 10))
    axes = axes.flatten()

    metric_sets = [
        ("Mean Response Time OK (ms)", [f"meanResponseTimeOk_{e}" for e in endpoints]),
        ("Mean Response Time KO (ms)", [f"meanResponseTimeKo_{e}" for e in endpoints]),
        ("P95 Response Time (ms)", [f"percentiles3_{e}" for e in endpoints]),
        ("P99 Response Time (ms)", [f"percentiles4_{e}" for e in endpoints]),
    ]

    for ax, (title, meas_keys) in zip(axes, metric_sets):
        style_ax(ax, title)
        for i, (data, label) in enumerate(zip(data_list, labels)):
            vals = [get_stat(data, m) or 0 for m in meas_keys]
            bars = ax.bar(
                x + i * width, vals, width, label=label, color=COLORS[i], alpha=0.85
            )
        ax.set_xticks(x + width * (n_runs - 1) / 2)
        ax.set_xticklabels(
            endpoint_labels, rotation=35, ha="right", color=TEXT, fontsize=7
        )
        ax.set_ylabel("ms", color=TEXT, fontsize=8)
        ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)
        ax.yaxis.set_major_formatter(
            mticker.FuncFormatter(
                lambda v, _: f"{v/1000:.1f}s" if v >= 1000 else f"{v:.0f}ms"
            )
        )

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Dashboard 3: Request counts and error rates ───────────────────────────────


def plot_request_counts(data_list, labels, output_path):
    endpoints = list(ENDPOINT_NAMES.keys())
    endpoint_labels = [ENDPOINT_NAMES[e] for e in endpoints]
    n_runs = len(data_list)
    x = np.arange(len(endpoints))
    width = 0.8 / n_runs

    fig, axes = make_fig(
        1, 2, "Request Counts & Error Rates per Endpoint", figsize=(18, 6)
    )
    axes = axes.flatten()

    # ── Panel 0: Stacked bar (OK on bottom, KO on top) ─────────────────────────
    ax = axes[0]
    style_ax(ax, "Requests (OK / Failed)")

    ok_keys = [f"numberOfRequestsOk_{e}" for e in endpoints]
    ko_keys = [f"numberOfRequestsKo_{e}" for e in endpoints]

    for i, (data, label) in enumerate(zip(data_list, labels)):
        ok_vals = [get_stat(data, m) or 0 for m in ok_keys]
        ko_vals = [get_stat(data, m) or 0 for m in ko_keys]

        ax.bar(
            x + i * width,
            ok_vals,
            width,
            color=COLORS[i],
            alpha=0.85,
            label=label,
        )
        ax.bar(
            x + i * width,
            ko_vals,
            width,
            bottom=ok_vals,
            color=COLOR_KO,
            alpha=0.55,
            label="Failed" if i == 0 else None,
        )

    ax.set_xticks(x + width * (n_runs - 1) / 2)
    ax.set_xticklabels(endpoint_labels, rotation=35, ha="right", color=TEXT, fontsize=7)
    ax.set_ylabel("count", color=TEXT, fontsize=8)
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)

    # ── Panel 1: % Failed ──────────────────────────────────────────────────────
    ax = axes[1]
    style_ax(ax, "% Failed (group4)")

    fail_keys = [f"group4Percentage_{e}" for e in endpoints]
    for i, (data, label) in enumerate(zip(data_list, labels)):
        vals = [get_stat(data, m) or 0 for m in fail_keys]
        ax.bar(x + i * width, vals, width, label=label, color=COLORS[i], alpha=0.85)
    ax.set_xticks(x + width * (n_runs - 1) / 2)
    ax.set_xticklabels(endpoint_labels, rotation=35, ha="right", color=TEXT, fontsize=7)
    ax.set_ylabel("%", color=TEXT, fontsize=8)
    ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Dashboard 4: Percentile overview table ────────────────────────────────────


def plot_percentile_table(data_list, labels, output_path):
    endpoints = [""] + list(ENDPOINT_NAMES.keys())  # "" = overall
    endpoint_labels = ["OVERALL"] + [ENDPOINT_NAMES[e] for e in endpoints[1:]]

    percentile_keys = {
        "P50": ("percentiles1", "percentiles1_{}"),
        "P75": ("percentiles2", "percentiles2_{}"),
        "P95": ("percentiles3", "percentiles3_{}"),
        "P99": ("percentiles4", "percentiles4_{}"),
    }

    fig, axes = make_fig(
        len(data_list),
        1,
        "Percentile Response Times per Endpoint (ms)",
        figsize=(16, 5 * len(data_list)),
    )
    if len(data_list) == 1:
        axes = [axes]

    for ax, (data, label) in zip(axes, zip(data_list, labels)):
        style_ax(ax, label)
        x = np.arange(len(endpoint_labels))
        width = 0.2
        pct_colors = ["#4FC3F7", "#29B6F6", "#039BE5", "#0277BD"]

        for i, (pct_label, (overall_key, per_key)) in enumerate(
            percentile_keys.items()
        ):
            vals = []
            for ep in endpoints:
                key = overall_key if ep == "" else per_key.format(ep)
                vals.append((get_stat(data, key) or 0) / 1000)  # convert to seconds
            ax.bar(
                x + i * width,
                vals,
                width,
                label=pct_label,
                color=pct_colors[i],
                alpha=0.85,
            )

        ax.set_xticks(x + width * 1.5)
        ax.set_xticklabels(
            endpoint_labels, rotation=35, ha="right", color=TEXT, fontsize=7
        )
        ax.set_ylabel("seconds", color=TEXT, fontsize=8)
        ax.legend(fontsize=8, facecolor=PANEL, labelcolor=TEXT)

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches="tight", facecolor=BG)
    print(f"  Saved: {output_path}")
    plt.close()


# ── Summary table ─────────────────────────────────────────────────────────────


def print_summary(data_list, labels):
    print("\n" + "=" * 80)
    print("EXPERIMENT SUMMARY")
    print("=" * 80)
    col_w = 22
    header = f"{'Metric':<32}" + "".join(f"{l[:col_w-2]:<{col_w}}" for l in labels)
    print(header)
    print("-" * 80)

    def fmt(val, div=1, unit=""):
        if val is None:
            return "N/A"
        return f"{val/div:.1f}{unit}"

    rows = [
        ("Total Requests", "numberOfRequestsTotal", 1, ""),
        ("OK Requests", "numberOfRequestsOk", 1, ""),
        ("KO Requests", "numberOfRequestsKo", 1, ""),
        ("% Failed (group4)", "group4Percentage", 1, "%"),
        ("Mean Response Time OK", "meanResponseTimeOk", 1000, "s"),
        ("Mean Response Time KO", "meanResponseTimeKo", 1000, "s"),
        ("P50 Response Time", "percentiles1", 1000, "s"),
        ("P75 Response Time", "percentiles2", 1000, "s"),
        ("P95 Response Time", "percentiles3", 1000, "s"),
        ("P99 Response Time", "percentiles4", 1000, "s"),
        ("Max Response Time", "maxResponseTime", 1000, "s"),
        ("Mean Req/sec OK", "meanNumberOfRequestsPerSecondOk", 1, "/s"),
        ("Mean Req/sec KO", "meanNumberOfRequestsPerSecondKo", 1, "/s"),
    ]

    for label, meas, div, unit in rows:
        row = f"{label:<32}"
        for data in data_list:
            val = get_stat(data, meas)
            row += f"{fmt(val, div, unit):<{col_w}}"
        print(row)

    print("=" * 80 + "\n")


# ── Main ──────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Visualise MiSArch Gatling experiment results from InfluxDB CSV exports."
    )
    parser.add_argument("--files", "-f", nargs="+", required=True)
    parser.add_argument("--labels", "-l", nargs="+")
    parser.add_argument("--output", "-o", default="timeseries.png")
    parser.add_argument("--output-dir", default=".")
    parser.add_argument("--all", action="store_true", help="Generate all dashboards")
    args = parser.parse_args()

    labels = args.labels if args.labels else [Path(f).stem for f in args.files]
    if len(labels) != len(args.files):
        print("ERROR: --labels count must match --files count", file=sys.stderr)
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

    print_summary(data_list, labels)

    out_dir = Path(args.output_dir)
    stem = Path(args.output).stem

    print("Generating time series dashboard...")
    plot_timeseries(data_list, labels, out_dir / f"{stem}_timeseries.png")

    if args.all:
        print("Generating response time summary...")
        plot_response_times(data_list, labels, out_dir / f"{stem}_response_times.png")

        print("Generating request counts dashboard...")
        plot_request_counts(data_list, labels, out_dir / f"{stem}_request_counts.png")

        print("Generating percentile overview...")
        plot_percentile_table(data_list, labels, out_dir / f"{stem}_percentiles.png")

    print("\nDone!")


if __name__ == "__main__":
    main()
