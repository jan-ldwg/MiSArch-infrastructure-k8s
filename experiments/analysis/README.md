# Experiment Results Analysis

Offline visualization scripts for MiSArch Gatling experiment results.
These scripts run locally without needing the cluster to be running.

## Requirements

```bash
pip install pandas matplotlib
```

## Usage

### Single experiment run
```bash
python3 plot_results.py --files experiment.csv --labels "Baseline"
```

### Compare before/after refactoring
```bash
python3 plot_results.py \
    --files baseline.csv chaos_with_fix.csv \
    --labels "Baseline" "After Circuit Breaker" \
    --output comparison.png
```

### Full output including per-request metrics
```bash
python3 plot_results.py \
    --files baseline.csv chaos_no_fix.csv chaos_with_fix.csv \
    --labels "Baseline" "Inventory Failure (No Fix)" "Inventory Failure (With Fix)" \
    --output comparison.png \
    --output-dir plots \
    --all
```

## Exporting Data from InfluxDB

While the cluster is running, port-forward InfluxDB:

```bash
kubectl port-forward svc/influxdb -n misarch 4000:80
```

Then go to `http://localhost:4000`, log in (admin / get password from
`terraform output influxdb_admin_token`), open Data Explorer, select
the `gatling` bucket, choose your experiment's time range, and export
as CSV.

## Output

- **gatling_total.png** — Active users over time + OK/KO responses,
  with a comparison column when multiple runs are provided
- **gatling_total_requests.png** (with `--all`) — Per-endpoint request
  counts for all Gatling request groups
- Summary statistics table printed to terminal
