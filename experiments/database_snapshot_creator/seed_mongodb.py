#!/usr/bin/env python3
"""
Insert test inventory data into MongoDB for testing snapshot_db.py.

Usage:
    seed_mongodb.py --username root --password <pwd>
    seed_mongodb.py --uri "mongodb://root:pwd@localhost:27017/?directConnection=true&authSource=admin"

Get the password from Terraform:
    terraform output mongodb_root_password_inventory
"""

import argparse
import sys
from urllib.parse import quote_plus

DEFAULT_HOST = "localhost:27017"
DEFAULT_ARGS = "directConnection=true&authSource=admin"
DEFAULT_AUTH_SOURCE = "admin"

WAREHOUSES = [
    {"name": "Main Warehouse", "location": "Stuttgart", "code": "WH-STG"},
    {"name": "Secondary Warehouse", "location": "Berlin", "code": "WH-BER"},
    {"name": "Express Depot", "location": "Munich", "code": "WH-MUC"},
]

PRODUCTS = [
    {"name": "POP 2025", "internalName": "POP2025", "category": "CDs", "retailPrice": 20.0},
    {"name": "Rock Album 2025", "internalName": "ROCK2025", "category": "CDs", "retailPrice": 25.0},
    {"name": "Jazz Hits 2025", "internalName": "JAZZ2025", "category": "CDs", "retailPrice": 15.0},
    {"name": "Swing Classics", "internalName": "SWING2016", "category": "CDs", "retailPrice": 17.0},
]


def build_uri(host, username, password, auth_source, extra_args):
    if extra_args:
        args = f"{DEFAULT_ARGS}&{extra_args}"
    else:
        args = DEFAULT_ARGS

    if username and password:
        return f"mongodb://{quote_plus(username)}:{quote_plus(password)}@{host}/?{args}"
    return f"mongodb://{host}/?{args}"


def main():
    parser = argparse.ArgumentParser(
        description="Seed inventory MongoDB with test data",
        epilog="Tip: get password from 'terraform output mongodb_root_password_inventory'",
    )
    parser.add_argument("--uri", help="Full MongoDB connection URI (overrides other connection flags)")
    parser.add_argument("--host", default=DEFAULT_HOST, help=f"MongoDB host:port (default: {DEFAULT_HOST})")
    parser.add_argument("--username", help="MongoDB username (default: none)")
    parser.add_argument("--password", help="MongoDB password")
    parser.add_argument("--auth-source", default=DEFAULT_AUTH_SOURCE, help=f"Auth database (default: {DEFAULT_AUTH_SOURCE})")
    args = parser.parse_args()

    try:
        from pymongo import MongoClient
    except ImportError:
        sys.exit("pymongo is required. Install with: pip install pymongo")

    uri = args.uri or build_uri(args.host, args.username, args.password, args.auth_source, None)
    client = MongoClient(uri, serverSelectionTimeoutMS=10000)

    try:
        client.admin.command("ping")
    except Exception as e:
        sys.exit(f"Failed to connect to MongoDB: {e}\nURI: {uri!r}")

    db = client["misarch_inventory"]

    for coll in ["warehouses", "products", "stock"]:
        db[coll].delete_many({})

    wh_ids = [db.warehouses.insert_one(w).inserted_id for w in WAREHOUSES]
    print(f"Inserted {len(wh_ids)} warehouses")

    prod_ids = [db.products.insert_one(p).inserted_id for p in PRODUCTS]
    print(f"Inserted {len(prod_ids)} products")

    stock_count = 0
    for prod_id in prod_ids:
        for wh_id in wh_ids:
            db.stock.insert_one({
                "productId": prod_id,
                "warehouseId": wh_id,
                "quantity": 1000,
                "reservedQuantity": 0,
            })
            stock_count += 1

    print(f"Inserted {stock_count} stock records")
    client.close()
    print("Done.")


if __name__ == "__main__":
    main()
