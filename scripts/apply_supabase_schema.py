from __future__ import annotations

import argparse
import os
from pathlib import Path
import sys

from dotenv import load_dotenv

try:
    import psycopg
except ImportError as exc:
    raise SystemExit(
        "psycopg belum terpasang. Jalankan: pip install -r scripts/requirements-supabase.txt"
    ) from exc

DEFAULT_SCHEMA_FILE = Path("database/migrations/202603100001_initial_neooptimasi.sql")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply NeoOptimasi Supabase schema to a PostgreSQL database.",
    )
    parser.add_argument(
        "--db-url",
        default=os.getenv("SUPABASE_DB_URL"),
        help="PostgreSQL connection string. Bisa juga lewat env SUPABASE_DB_URL.",
    )
    parser.add_argument(
        "--schema-file",
        default=str(DEFAULT_SCHEMA_FILE),
        help="Path file SQL yang akan dieksekusi.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Hanya validasi file SQL tanpa mengeksekusinya.",
    )
    return parser.parse_args()


def main() -> int:
    load_dotenv()
    args = parse_args()

    schema_path = Path(args.schema_file)
    if not schema_path.exists():
        raise SystemExit(f"Schema file tidak ditemukan: {schema_path}")

    sql = schema_path.read_text(encoding="utf-8")
    if not sql.strip():
        raise SystemExit(f"Schema file kosong: {schema_path}")

    print(f"Schema file: {schema_path}")

    if args.dry_run:
        print("Dry run selesai. SQL file valid secara dasar dan siap dieksekusi.")
        return 0

    if not args.db_url:
        raise SystemExit(
            "DB URL tidak ditemukan. Set SUPABASE_DB_URL atau kirim --db-url postgresql://..."
        )

    print("Connecting to database...")
    with psycopg.connect(args.db_url, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)

    print("Schema applied successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
