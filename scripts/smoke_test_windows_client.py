from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib import request

import psycopg


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Smoke test NeoOptimize Windows client against live backend and Supabase.")
    parser.add_argument("--backend-url", default="https://neooptimize-neooptimize.hf.space/", help="NeoOptimize backend base URL.")
    parser.add_argument("--db-url", default=os.getenv("SUPABASE_DB_URL"), help="Supabase PostgreSQL connection string.")
    parser.add_argument(
        "--service-dll",
        default=r"d:\NeoOptimize\client_windows\NeoOptimize\src\NeoOptimize.Service\bin\Debug\net8.0\NeoOptimize.Service.dll",
        help="Path to NeoOptimize.Service.dll when running framework-dependent builds.",
    )
    parser.add_argument(
        "--service-exe",
        default=None,
        help="Path to NeoOptimize.Service.exe for self-contained publish outputs.",
    )
    parser.add_argument(
        "--app-exe",
        default=r"d:\NeoOptimize\client_windows\NeoOptimize\src\NeoOptimize.App\bin\Debug\net8.0-windows\NeoOptimize.App.exe",
        help="Path to NeoOptimize.App.exe",
    )
    parser.add_argument("--timeout-seconds", type=int, default=120, help="Timeout per major stage.")
    return parser.parse_args()


def post_json(base_url: str, path: str, payload: dict[str, Any]) -> tuple[int, dict[str, Any]]:
    req = request.Request(
        base_url.rstrip("/") + path,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json", "Accept": "application/json"},
        method="POST",
    )
    with request.urlopen(req, timeout=90) as response:
        return response.status, json.loads(response.read().decode("utf-8"))


def wait_for_file(path: Path, timeout_seconds: int) -> dict[str, Any]:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8"))
        time.sleep(1)
    raise TimeoutError(f"Timed out waiting for file: {path}")


def wait_for_command_completion(conn: psycopg.Connection, client_id: str, timeout_seconds: int) -> tuple[str, str | None]:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        with conn.cursor() as cur:
            cur.execute(
                """
                select status, error_message
                from public.remote_commands
                where client_id = %s
                order by requested_at desc nulls last, completed_at desc nulls last, claimed_at desc nulls last
                limit 1
                """,
                (client_id,),
            )
            row = cur.fetchone()
        if row and row[0] in {"completed", "failed", "cancelled"}:
            return row[0], row[1]
        time.sleep(2)
    raise TimeoutError("Timed out waiting for remote command completion.")


def wait_for_client_rows(conn: psycopg.Connection, client_id: str, timeout_seconds: int) -> dict[str, int]:
    deadline = time.time() + timeout_seconds
    while time.time() < deadline:
        with conn.cursor() as cur:
            cur.execute("select count(*) from public.telemetry_logs where client_id = %s", (client_id,))
            telemetry_count = cur.fetchone()[0]
            cur.execute("select count(*) from public.system_health where client_id = %s", (client_id,))
            health_count = cur.fetchone()[0]
        if telemetry_count > 0 and health_count > 0:
            return {"telemetry_count": telemetry_count, "health_count": health_count}
        time.sleep(2)
    raise TimeoutError("Timed out waiting for telemetry and health rows.")


def start_process(command: list[str], cwd: Path, env: dict[str, str], log_path: Path) -> subprocess.Popen[str]:
    log_file = log_path.open("w", encoding="utf-8")
    return subprocess.Popen(
        command,
        cwd=str(cwd),
        env=env,
        stdout=log_file,
        stderr=subprocess.STDOUT,
        text=True,
    )


def stop_process(process: subprocess.Popen[str], timeout_seconds: int = 15) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=timeout_seconds)


def read_registration_client_id(payload: dict[str, Any]) -> str:
    return payload.get("clientId") or payload.get("ClientId")


def main() -> int:
    args = parse_args()
    if not args.db_url:
        raise SystemExit("Missing --db-url or SUPABASE_DB_URL")

    backend_url = args.backend_url
    service_exe = Path(args.service_exe) if args.service_exe else None
    service_dll = Path(args.service_dll)
    app_exe = Path(args.app_exe)

    if service_exe is not None:
        if not service_exe.exists():
            raise SystemExit(f"Service EXE not found: {service_exe}")
        service_command = [str(service_exe)]
        service_working_dir = service_exe.parent
    else:
        if not service_dll.exists():
            raise SystemExit(f"Service DLL not found: {service_dll}")
        service_command = ["dotnet", str(service_dll)]
        service_working_dir = service_dll.parent

    if not app_exe.exists():
        raise SystemExit(f"App EXE not found: {app_exe}")

    temp_root = Path(tempfile.mkdtemp(prefix="neooptimize-smoke-"))
    service_registration = temp_root / "service-registration.json"
    app_registration = temp_root / "app-registration.json"
    service_log = temp_root / "service.log"
    app_log = temp_root / "app.log"

    conn = psycopg.connect(args.db_url)
    conn.autocommit = True

    service_process: subprocess.Popen[str] | None = None
    app_process: subprocess.Popen[str] | None = None

    try:
        base_env = os.environ.copy()
        base_env.update(
            {
                "NeoOptimize__BackendBaseUrl": backend_url,
                "NeoOptimize__TelemetryIntervalSeconds": "5",
                "NeoOptimize__HealthIntervalMinutes": "1",
                "NeoOptimize__CommandPollIntervalSeconds": "5",
                "NeoOptimize__SmartBoosterIntervalMinutes": "1",
                "NeoOptimize__IntegrityIntervalHours": "1",
            }
        )

        service_env = base_env | {
            "NeoOptimize__AppVersion": "0.2.1-service-smoke",
            "NeoOptimize__RegistrationStatePath": str(service_registration),
        }
        service_process = start_process(service_command, service_working_dir, service_env, service_log)
        service_registration_payload = wait_for_file(service_registration, args.timeout_seconds)
        service_client_id = read_registration_client_id(service_registration_payload)
        if not service_client_id:
            raise RuntimeError("Service registration file did not contain clientId.")

        initial_rows = wait_for_client_rows(conn, service_client_id, args.timeout_seconds)
        status, queued = post_json(
            backend_url,
            "/api/v1/commands/enqueue",
            {
                "client_id": service_client_id,
                "source": "system",
                "command_name": "health_check",
                "payload": {"smoke_test": True},
                "priority": 90,
            },
        )
        if status != 202:
            raise RuntimeError(f"Unexpected enqueue status: {status}")

        command_status, command_error = wait_for_command_completion(conn, service_client_id, args.timeout_seconds)
        if command_status != "completed":
            raise RuntimeError(f"Remote command failed: {command_status} {command_error}")

        stop_process(service_process)
        service_process = None

        app_env = base_env | {
            "NeoOptimize__AppVersion": "0.2.1-app-smoke",
            "NeoOptimize__RegistrationStatePath": str(app_registration),
        }
        app_process = start_process([str(app_exe)], app_exe.parent, app_env, app_log)
        app_registration_payload = wait_for_file(app_registration, args.timeout_seconds)
        app_client_id = read_registration_client_id(app_registration_payload)
        if not app_client_id:
            raise RuntimeError("App registration file did not contain clientId.")

        time.sleep(15)
        if app_process.poll() is not None:
            raise RuntimeError(f"NeoOptimize.App exited unexpectedly with code {app_process.returncode}")

        app_rows = wait_for_client_rows(conn, app_client_id, args.timeout_seconds)

        with conn.cursor() as cur:
            cur.execute("select count(*) from public.telemetry_logs where client_id = %s", (service_client_id,))
            service_telemetry = cur.fetchone()[0]
            cur.execute("select count(*) from public.system_health where client_id = %s", (service_client_id,))
            service_health = cur.fetchone()[0]
            cur.execute(
                "select status from public.remote_commands where id = %s",
                (queued["command_id"],),
            )
            queued_status = cur.fetchone()[0]
            cur.execute("select count(*) from public.clients where id = %s", (app_client_id,))
            app_client_count = cur.fetchone()[0]

        summary = {
            "service_client_id": service_client_id,
            "service_rows": initial_rows,
            "service_telemetry_after": service_telemetry,
            "service_health_after": service_health,
            "queued_command_id": queued["command_id"],
            "queued_command_status": queued_status,
            "app_client_id": app_client_id,
            "app_client_row_count": app_client_count,
            "app_rows": app_rows,
            "service_log": str(service_log),
            "app_log": str(app_log),
            "temp_root": str(temp_root),
        }
        print(json.dumps(summary, indent=2))
        return 0
    finally:
        if app_process is not None:
            stop_process(app_process)
        if service_process is not None:
            stop_process(service_process)
        conn.close()
        if Path(service_log).exists():
            print("-- service log tail --")
            print("\n".join(Path(service_log).read_text(encoding="utf-8", errors="ignore").splitlines()[-20:]))
        if Path(app_log).exists():
            print("-- app log tail --")
            print("\n".join(Path(app_log).read_text(encoding="utf-8", errors="ignore").splitlines()[-20:]))


if __name__ == "__main__":
    sys.exit(main())
