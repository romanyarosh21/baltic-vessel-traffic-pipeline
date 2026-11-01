"""Load daily Danish AIS files (zip or csv) into raw.ais_messages.

Idempotent: the rows of one source file are replaced in a single
transaction, so loading a file twice never creates duplicates.
Incremental: raw.load_log remembers which files finished, and a finished
file is skipped unless --force is given.
"""
import argparse
import csv
import io
import os
import time
import zipfile
from contextlib import contextmanager
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

UPSERT_LOG = """
    INSERT INTO raw.load_log (source_file, status, rows_loaded, rows_skipped)
    VALUES (%s, %s, %s, %s)
    ON CONFLICT (source_file) DO UPDATE
    SET status = EXCLUDED.status,
        rows_loaded = EXCLUDED.rows_loaded,
        rows_skipped = EXCLUDED.rows_skipped,
        loaded_at = now()
"""


def connect() -> psycopg.Connection:
    load_dotenv(PROJECT_ROOT / ".env")
    return psycopg.connect(
        host="localhost",
        port=5432,
        dbname=os.environ["POSTGRES_DB"],
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        autocommit=True,
    )


@contextmanager
def open_csv(path: Path):
    """Yield (csv file name, text stream) for a .csv or a .zip with one csv."""
    if path.suffix.lower() == ".zip":
        with zipfile.ZipFile(path) as archive:
            members = [n for n in archive.namelist() if n.lower().endswith(".csv")]
            if len(members) != 1:
                raise ValueError(f"{path.name}: expected one CSV, found {len(members)}")
            with archive.open(members[0]) as binary:
                text = io.TextIOWrapper(
                    binary, encoding="utf-8", errors="replace", newline=""
                )
                yield Path(members[0]).name, text
    else:
        with open(path, newline="", encoding="utf-8", errors="replace") as text:
            yield path.name, text


def find_inputs(path: Path) -> list[Path]:
    if path.is_file():
        return [path]
    if path.is_dir():
        return sorted(list(path.glob("*.zip")) + list(path.glob("*.csv")))
    raise SystemExit(f"Not found: {path}")


def already_loaded(conn: psycopg.Connection, source_file: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM raw.load_log WHERE source_file = %s AND status = 'complete'",
        (source_file,),
    ).fetchone()
    return row is not None


def load_file(
    conn: psycopg.Connection, path: Path, limit: int | None, force: bool
) -> tuple[int, int]:
    with open_csv(path) as (source_file, text):
        if not force and already_loaded(conn, source_file):
            print(f"Skip {source_file}: already loaded")
            return 0, 0

        started = time.time()
        loaded = 0
        skipped = 0
        target = ", ".join(COLUMNS + ["source_file"])

        # One transaction per file: data and log entry succeed or fail together.
        with conn.transaction(), conn.cursor() as cur:
            cur.execute(
                "DELETE FROM raw.ais_messages WHERE source_file = %s", (source_file,)
            )
            print(f"{source_file}: removed {cur.rowcount} old rows")

            reader = csv.reader(text)
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
                    if loaded % 2_000_000 == 0:
                        print(f"  {loaded:,} rows...")
                    if limit and loaded >= limit:
                        break

            status = "partial" if limit and loaded >= limit else "complete"
            cur.execute(UPSERT_LOG, (source_file, status, loaded, skipped))

        seconds = time.time() - started
        print(
            f"{source_file}: {status}, loaded {loaded:,} rows, "
            f"skipped {skipped:,} malformed, in {seconds:.1f}s"
        )
        return loaded, skipped


def main() -> None:
    parser = argparse.ArgumentParser(description="Load daily AIS files into Postgres")
    parser.add_argument(
        "path", type=Path, help="a .zip or .csv file, or a folder with daily files"
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="load only the first N rows of each file (testing; file is marked partial)",
    )
    parser.add_argument(
        "--force", action="store_true", help="reload files already marked complete"
    )
    args = parser.parse_args()

    files = find_inputs(args.path)
    if not files:
        raise SystemExit(f"No .zip or .csv files in {args.path}")

    total_loaded = 0
    total_skipped = 0
    with connect() as conn:
        for file in files:
            loaded, skipped = load_file(conn, file, args.limit, args.force)
            total_loaded += loaded
            total_skipped += skipped
    print(
        f"Done: {len(files)} file(s) checked, {total_loaded:,} rows loaded, "
        f"{total_skipped:,} malformed rows skipped"
    )


if __name__ == "__main__":
    main()