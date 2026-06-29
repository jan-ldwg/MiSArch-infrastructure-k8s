#!/usr/bin/env python3
"""
Export annotated CSV data from InfluxDB buckets.

    export_influxdb.py --token <token> --test-uuid <uuid> [--output file.csv]
    export_influxdb.py --token <token> --list-buckets
    export_influxdb.py --token <token> --query 'from(bucket:"gatling") |> range(start: -1h)'

Port-forward InfluxDB first if running inside Kubernetes:

    kubectl port-forward svc/influxdb -n misarch 4000:80

Then get the admin token and export:

    TOKEN=$(terraform output -raw influxdb_admin_token)
    python export_influxdb.py --token $TOKEN --test-uuid abc123-def456 -o data.csv
"""

import argparse
import sys

from influxdb_client import InfluxDBClient
from influxdb_client.client.exceptions import InfluxDBError


def main():
    parser = argparse.ArgumentParser(description="Export annotated CSV data from InfluxDB buckets.")

    parser.add_argument("--token", required=True, help="InfluxDB API token")
    parser.add_argument("--url", default="http://localhost:4000", help="InfluxDB URL")
    parser.add_argument("--org", default="misarch", help="InfluxDB organization")
    parser.add_argument("--bucket", default="gatling", help="InfluxDB bucket to query")
    parser.add_argument("--query", help="Custom Flux query (overrides default bucket export)")
    parser.add_argument("-o", "--output", help="Output CSV file path (default: stdout)")
    parser.add_argument("-u", "--test-uuid", help="Test UUID to filter (required for default export)")
    parser.add_argument("--list-buckets", action="store_true", help="List all available buckets and exit")

    args = parser.parse_args()

    if not args.list_buckets and not args.query and not args.test_uuid:
        parser.error("--test-uuid is required (unless using --list-buckets or --query)")

    with InfluxDBClient(url=args.url, token=args.token, org=args.org) as client:

        if args.list_buckets:
            buckets = client.buckets_api().find_buckets().buckets
            for b in sorted(buckets, key=lambda b: b.name):
                print(f"  {b.name}")
            return

        if args.query:
            query = args.query
        else:
            query = f'from(bucket:"{args.bucket}") |> range(start: 0) |> filter(fn:(r) => r.testUUID == "{args.test_uuid}")'

        try:
            response = client.query_api().query_raw(query=query, org=args.org)
        except InfluxDBError as e:
            sys.exit(f"Query failed: {e}")

        csv_text = response.data.decode("utf-8").rstrip()

        if not csv_text:
            sys.exit("Query returned no data.")

        if args.output:
            with open(args.output, "w") as f:
                f.write(csv_text)
                f.write("\n")
        else:
            print(csv_text)


if __name__ == "__main__":
    main()
