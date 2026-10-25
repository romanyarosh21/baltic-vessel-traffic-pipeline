"""Load one daily Danish AIS CSV file into raw.ais_messages.

Idempotent: rows of the same source file are deleted and reloaded in a
single transaction, so running it twice never creates duplicates.
"""
import argparse
import csv
import os
import time
from pathlib import Path

import psycopg
from dotenv import load_dotenv

COLUMNS = [
    "ts", "type_of_mobile", "mmsi", "latitude", "longitude",
    "navigational_status", "rot", "sog", "cog", "heading", "imo",
    "callsign", "vessel_name", "ship_type", "cargo_type", "width",
    "length", "position_fixing_device", "draught", "destination", "eta",
    "data_source_type", "size_a", "size_b", "size_c", "size_d",
]
PROJECT_ROOT = Path(__file__).resolve().parent.parent


def connect() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")
    return psycopg.connect(
        host="localhost",
        port=5432,
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
    )


def load_file(csv_path: Path, limit: int | None) -> None:
    source_file = csv_path.name
    target = ", ".join(COLUMNS + ["source_file"])
    started = time.time()
    loaded = 0
    skipped = 0

    # The connection commits on success and rolls back on any error.
    with connect() as conn, conn.cursor() as cur:
        cur.execute(
            "DELETE FROM raw.ais_messages WHERE source_file = %s",
            (source_file,),
        )
        print(f"Removed {cur.rowcount} old rows for {source_file}")

        with open(csv_path, newline="", encoding="utf-8", errors="replace") as f:
            reader = csv.reader(f)
            next(reader)  # skip the header line
            with cur.copy(f"COPY raw.ais_messages ({target}) FROM STDIN") as copy:
                for row in reader:
                    if len(row) != len(COLUMNS):
                        skipped += 1
                        continue
                    # An empty field in the CSV becomes NULL in the table.
                    values = [v if v != "" else None for v in row]
                    copy.write_row(values + [source_file])
                    loaded += 1
                    if loaded % 500_000 == 0:
                        print(f"  {loaded:,} rows...")
                    if limit and loaded >= limit:
                        break

    seconds = time.time() - started
    print(f"Loaded {loaded:,} rows, skipped {skipped:,} malformed, in {seconds:.1f}s")


def main() -> None:
    parser = argparse.ArgumentParser(description="Load an AIS CSV into Postgres")
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--limit", type=int, default=None,
                        help="load only the first N rows (for testing)")
    args = parser.parse_args()
    if not args.csv_path.is_file():
        raise SystemExit(f"File not found: {args.csv_path}")
    load_file(args.csv_path, args.limit)


if __name__ == "__main__":
    main()