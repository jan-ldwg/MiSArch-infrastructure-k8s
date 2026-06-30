#!/usr/bin/env python3
"""
Extract the full state of a MongoDB or PostgreSQL database as JSON.

    snapshot_db.py mongodb --uri <uri> [--output <file>]
    snapshot_db.py postgres --uri <uri> [--output <file>]

URI examples:

    mongodb://root:PWD@localhost:27017/?directConnection=true&authSource=admin
    postgresql://user:PWD@localhost:5432/dbname

Get a password and build the URI on the fly:

    # Terraform output
    python scripts/snapshot_db.py mongodb --uri "mongodb://root:$(terraform output -raw <output>)@localhost:27017/?directConnection=true&authSource=admin"

    # k8s secret
    PWD=$(kubectl get secret <name> -n misarch -o jsonpath='{.data.<key>}' | base64 -d)
    python scripts/snapshot_db.py postgres --uri "postgresql://misarch:$PWD@localhost:5432/misarch"

Port-forward the database first if running outside the cluster.
"""

import argparse
import json
import sys
from datetime import datetime, timezone

SYSTEM_DBS = {"admin", "local", "config"}


def snapshot_mongodb(uri):
    try:
        from pymongo import MongoClient
        from bson import json_util
    except ImportError:
        sys.exit("pymongo is required. Install with: pip install pymongo")

    client = MongoClient(uri, serverSelectionTimeoutMS=10000)
    try:
        client.admin.command("ping")
    except Exception as e:
        sys.exit(f"Failed to connect to MongoDB: {e}")

    db_names = [n for n in client.list_database_names() if n not in SYSTEM_DBS]

    result = {
        "db_type": "mongodb",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "databases": {},
    }

    for db_name in sorted(db_names):
        db = client[db_name]
        collections = {}
        for coll_name in sorted(db.list_collection_names()):
            docs = list(db[coll_name].find())
            collections[coll_name] = json.loads(json_util.dumps(docs))
        result["databases"][db_name] = collections

    client.close()
    return result


def snapshot_postgres(uri):
    try:
        import psycopg2
    except ImportError:
        sys.exit("psycopg2 is required. Install with: pip install psycopg2-binary")

    try:
        conn = psycopg2.connect(uri)
    except Exception as e:
        sys.exit(f"Failed to connect to PostgreSQL: {e}")

    cursor = conn.cursor()
    cursor.execute("SELECT current_database()")
    db_name = cursor.fetchone()[0]

    cursor.execute(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = 'public' ORDER BY table_name"
    )
    tables = [row[0] for row in cursor.fetchall()]

    result = {
        "db_type": "postgres",
        "db": db_name,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "tables": {},
    }

    for table in tables:
        cursor.execute(f'SELECT * FROM "{table}"')
        columns = [desc[0] for desc in cursor.description]
        rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
        result["tables"][table] = rows

    cursor.close()
    conn.close()
    return result


def main():
    parser = argparse.ArgumentParser(description="Extract database state as JSON")
    subparsers = parser.add_subparsers(dest="db_type", required=True)

    mongo = subparsers.add_parser("mongodb", help="Snapshot a MongoDB instance")
    mongo.add_argument("--uri", required=True, help="MongoDB connection URI")
    mongo.add_argument("--output", help="Output file path (default: stdout)")

    pg = subparsers.add_parser("postgres", help="Snapshot a PostgreSQL database")
    pg.add_argument("--uri", required=True, help="PostgreSQL connection URI")
    pg.add_argument("--output", help="Output file path (default: stdout)")

    args = parser.parse_args()

    if args.db_type == "mongodb":
        data = snapshot_mongodb(args.uri)
    else:
        data = snapshot_postgres(args.uri)

    output = json.dumps(data, indent=2, ensure_ascii=False, default=str)

    if args.output:
        with open(args.output, "w") as f:
            f.write(output)
            f.write("\n")
    else:
        print(output)


if __name__ == "__main__":
    main()
