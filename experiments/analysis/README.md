# MiSArch Experiment Results Analysis

Offline visualization and analysis scripts for MiSArch experiment results.
These scripts run locally without needing the cluster to be running.

## Requirements

```bash
pip install pandas matplotlib
```

## Usage

### Basic — single experiment run

```bash
python3 plot_results.py --files my_experiment.csv --labels "Baseline"
```

### Compare two runs (before/after refactoring)

```bash
python3 plot_results.py \
    --files baseline.csv after_fix.csv \
    --labels "Baseline" "After Dapr Circuit Breaker" \
    --output before_after.png \
    --title "MiSArch: Impact of Circuit Breaker on Inventory Failure"
```

### Compare three runs with all metrics

```bash
python3 plot_results.py \
    --files baseline.csv chaos_before.csv chaos_after.csv \
    --labels "Baseline" "Inventory Failure (No Fix)" "Inventory Failure (With Fix)" \
    --output comparison.png \
    --all-metrics \
    --title "MiSArch Resilience Refactoring: Before vs After"
```

## Exporting Data from InfluxDB

While the cluster is running, export experiment data:

```bash
kubectl port-forward svc/influxdb -n misarch 4000:80
```

Then in your browser go to `http://localhost:4000`, log in with:
- Username: `admin`
- Password: `admin123`

Navigate to Data Explorer, select the `gatling` bucket, choose your
experiment's measurement, and export as CSV.

Alternatively use the InfluxDB CLI:

```bash
influx query \
  --host http://localhost:4000 \
  --token <your-token> \
  'from(bucket:"gatling") |> range(start: -1h)' \
  --raw > my_experiment.csv
```

## Output

The script produces:
- A 4-panel dashboard PNG comparing key metrics across runs
- (Optional) Individual PNG per metric with `--all-metrics`
- A summary statistics table printed to the terminal

## Metrics Visualized

| Metric | Description |
|--------|-------------|
| Failed Requests (%) | Percentage of requests that failed |
| Mean Response Time (ms) | Average response time across all requests |
| P95 Response Time (ms) | 95th percentile response time |
| Successful Req/sec (%) | Percentage of successful requests per second |
| Max Response Time (ms) | Maximum response time observed |
| Requests < 800ms (%) | Percentage of requests completing under 800ms |
| P99 Response Time (ms) | 99th percentile response time |
| Failed Req/sec (%) | Percentage of failed requests per second |
