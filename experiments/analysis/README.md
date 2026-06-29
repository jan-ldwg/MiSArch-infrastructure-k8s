# Experiment Results Analysis

Offline visualization scripts for MiSArch Gatling experiment results.
Run locally without needing the cluster to be up.

## Requirements

```bash
pip install pandas matplotlib
```

## Usage

### Single experiment run
```bash
python3 plot_results.py --files experiment.csv --labels "Baseline"
```

### Compare before/after refactoring (recommended)
```bash
python3 plot_results.py \
    --files baseline.csv chaos_no_fix.csv chaos_with_fix.csv \
    --labels "Baseline" "Inventory Failure (No Fix)" "Inventory Failure (With Fix)" \
    --output results \
    --output-dir plots \
    --all
```

## Output

Running without `--all` produces one file. With `--all` produces four:

| File | Description |
|------|-------------|
| `<name>_timeseries.png` | Active users + OK/KO responses over time |
| `<name>_response_times.png` | Mean, P95, P99 response time per endpoint (bar chart) |
| `<name>_request_counts.png` | Total/OK/KO request counts + % failed per endpoint |
| `<name>_percentiles.png` | P50/P75/P95/P99 per endpoint |

A summary statistics table is always printed to the terminal.

When multiple CSV files are provided, all charts overlay the runs for
direct before/after comparison.

## Exporting Data from InfluxDB

While the cluster is running, port-forward InfluxDB:

```bash
kubectl port-forward svc/influxdb -n misarch 4000:80
```

Then go to `http://localhost:4000`, log in with:
- Username: `admin`
- Password: run `terraform output influxdb_admin_token`

Open **Data Explorer**, select the `gatling` bucket, set the time range
to your experiment window, and export as CSV.

## Understanding the Output

The InfluxDB CSV contains two types of data:

**Time series** (plotted over time in `_timeseries.png`):
- `activeUsers` — virtual users active per second, per scenario
- `responses` — responses per interval, split into ok/ko/all

**Summary statistics** (plotted as bar charts in the other 3 files):
- Single values recorded at the end of the experiment
- Cover response times, percentiles, request counts per endpoint

### Key metrics to watch

- **% Failed (group4)** — percentage of requests that failed entirely.
  A healthy baseline should be under 5%.
- **P95 response time** — 95% of requests completed faster than this.
  Under 800ms is good for this system.
- **createOrder / placeOrder failure rate** — the most important
  endpoints for the order completion steady-state metric.