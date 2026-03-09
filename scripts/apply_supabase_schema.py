from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import sys
from urllib import error, request

from dotenv import load_dotenv

DEFAULT_SCHEMA_FILE = Path("database/migrations/202603100001_initial_neooptimasi.sql")
MANAGEMENT_API_BASE = "https://api.supabase.com/v1/projects"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Apply NeoOptimasi Supabase schema via PostgreSQL or Supabase Management API.",
    )
    parser.add_argument(
        "--db-url",
        default=os.getenv("SUPABASE_DB_URL"),
        help="PostgreSQL connection string. Bisa juga lewat env SUPABASE_DB_URL.",
    )
    parser.add_argument(
        "--management-token",
        default=os.getenv("SUPABASE_ACCESS_TOKEN"),
        help="Supabase Personal Access Token untuk Management API.",
    )
    parser.add_argument(
        "--project-ref",
        default=os.getenv("SUPABASE_PROJECT_REF"),
        help="Project ref Supabase. Jika kosong, akan dicoba dari SUPABASE_URL.",
    )
    parser.add_argument(
        "--supabase-url",
        default=os.getenv("SUPABASE_URL"),
        help="URL project Supabase untuk infer project ref jika perlu.",
    )
    parser.add_argument(
        "--mode",
        choices=["auto", "db", "management"],
        default="auto",
        help="Pilih metode apply schema. Default: auto.",
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


def infer_project_ref(project_ref: str | None, supabase_url: str | None) -> str | None:
    if project_ref:
        return project_ref.strip()

    if not supabase_url:
        return None

    match = re.match(r"https://([A-Za-z0-9-]+)\.supabase\.co/?", supabase_url.strip())
    return match.group(1) if match else None


def load_sql(schema_file: str) -> tuple[Path, str]:
    schema_path = Path(schema_file)
    if not schema_path.exists():
        raise SystemExit(f"Schema file tidak ditemukan: {schema_path}")

    sql = schema_path.read_text(encoding="utf-8")
    if not sql.strip():
        raise SystemExit(f"Schema file kosong: {schema_path}")

    return schema_path, sql


def apply_via_db(db_url: str, sql: str) -> None:
    try:
        import psycopg
    except ImportError as exc:
        raise SystemExit(
            "psycopg belum terpasang. Jalankan: pip install -r scripts/requirements-supabase.txt"
        ) from exc

    print("Connecting to PostgreSQL...")
    with psycopg.connect(db_url, autocommit=True) as connection:
        with connection.cursor() as cursor:
            cursor.execute(sql)

    print("Schema applied successfully via PostgreSQL.")


def apply_via_management_api(management_token: str, project_ref: str, sql: str) -> None:
    payload = json.dumps({"query": sql}).encode("utf-8")
    endpoint = f"{MANAGEMENT_API_BASE}/{project_ref}/database/query"
    headers = {
        "Authorization": f"Bearer {management_token}",
        "Content-Type": "application/json",
        "Accept": "application/json",
    }
    req = request.Request(endpoint, data=payload, headers=headers, method="POST")

    try:
        with request.urlopen(req, timeout=180) as response:
            body = response.read().decode("utf-8", errors="ignore")
    except error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="ignore")
        hint = ""
        if exc.code == 401:
            hint = " Pastikan token yang dipakai adalah Supabase Personal Access Token, bukan service_role JWT."
        raise SystemExit(
            f"Management API request gagal ({exc.code}): {body[:500]}{hint}"
        ) from exc
    except error.URLError as exc:
        raise SystemExit(f"Management API tidak bisa dihubungi: {exc}") from exc

    print("Schema applied successfully via Supabase Management API.")
    if body:
        print(body[:500])


def main() -> int:
    load_dotenv()
    args = parse_args()
    schema_path, sql = load_sql(args.schema_file)

    print(f"Schema file: {schema_path}")

    if args.dry_run:
        print("Dry run selesai. SQL file valid secara dasar dan siap dieksekusi.")
        return 0

    project_ref = infer_project_ref(args.project_ref, args.supabase_url)
    can_use_db = bool(args.db_url)
    can_use_management = bool(args.management_token and project_ref)

    if args.mode == "db":
        if not args.db_url:
            raise SystemExit("Mode db dipilih tetapi SUPABASE_DB_URL / --db-url tidak tersedia.")
        apply_via_db(args.db_url, sql)
        return 0

    if args.mode == "management":
        if not args.management_token:
            raise SystemExit(
                "Mode management dipilih tetapi SUPABASE_ACCESS_TOKEN / --management-token tidak tersedia."
            )
        if not project_ref:
            raise SystemExit(
                "Mode management dipilih tetapi project ref tidak tersedia. Set SUPABASE_PROJECT_REF atau SUPABASE_URL."
            )
        apply_via_management_api(args.management_token, project_ref, sql)
        return 0

    if can_use_db:
        apply_via_db(args.db_url, sql)
        return 0

    if can_use_management:
        apply_via_management_api(args.management_token, project_ref, sql)
        return 0

    raise SystemExit(
        "Kredensial apply schema tidak ditemukan. Sediakan salah satu:\n"
        "1. SUPABASE_DB_URL / --db-url postgresql://...\n"
        "2. SUPABASE_ACCESS_TOKEN + SUPABASE_PROJECT_REF (atau SUPABASE_URL) untuk Management API."
    )


if __name__ == "__main__":
    sys.exit(main())
