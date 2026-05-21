#!/usr/bin/env python3
"""
Deploy the NeoOptimize self-healing Windows agent package to a lab VM over WinRM.

Prerequisite on the Linux host:
    python3 -m pip install --user pywinrm

Prerequisite inside the Windows VM:
    Run tools/Enable-NeoOptimizeWinRM.ps1 as Administrator.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import pathlib
import socket
import sys
import time
import zipfile
import hashlib

ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_PACKAGE = ROOT / "release" / "agent_win64_self_healing_20260519.zip"
DEFAULT_SERVER_URL = "http://192.168.122.1:3000"
DEFAULT_SERVICE_NAME = "NeoOptimize RMM Agent"
DEFAULT_INSTALL_DIR = r"C:\Program Files\NeoOptimize\Agent"
DEFAULT_REMOTE_ROOT = r"C:\ProgramData\NeoOptimize\deploy"
DEFAULT_PUBLIC_KEY = ROOT / "server" / "keys" / "signing.pub.pem"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Deploy NeoOptimize Windows agent via WinRM.")
    parser.add_argument("--host", required=True, help="Windows VM IP or hostname, for example 192.168.122.152")
    parser.add_argument("--user", required=True, help="Windows username, for example Administrator")
    parser.add_argument("--password", default=os.getenv("NEO_WINRM_PASSWORD"), help="Windows password, or env NEO_WINRM_PASSWORD")
    parser.add_argument("--package", default=str(DEFAULT_PACKAGE), help="Agent zip package path")
    parser.add_argument("--server-url", default=DEFAULT_SERVER_URL, help="RMM server URL written to appsettings.json")
    parser.add_argument("--install-dir", default=DEFAULT_INSTALL_DIR, help="Remote install directory")
    parser.add_argument("--remote-root", default=DEFAULT_REMOTE_ROOT, help="Remote staging directory")
    parser.add_argument("--service-name", default=DEFAULT_SERVICE_NAME, help="Windows service name")
    parser.add_argument("--public-key", default=str(DEFAULT_PUBLIC_KEY), help="Expected server signing.pub.pem for hash verification")
    parser.add_argument("--transport", default="basic", choices=["basic", "ntlm", "kerberos", "credssp"], help="WinRM transport")
    parser.add_argument("--scheme", default="http", choices=["http", "https"], help="WinRM scheme")
    parser.add_argument("--port", type=int, default=5985, help="WinRM port")
    parser.add_argument("--chunk-size", type=int, default=384 * 1024, help="Upload chunk size in bytes")
    parser.add_argument("--enable-lab-commands", action="store_true", help="Set Safety.EnableLabCommands=true")
    parser.add_argument("--skip-upload", action="store_true", help="Use an already uploaded package at remote-root")
    parser.add_argument("--run-smoke", action="store_true", help="Run local RMM runtime-smoke harness after deploy")
    parser.add_argument("--run-rollback", action="store_true", help="Run local RMM rollback harness after smoke")
    parser.add_argument("--hostname", default="", help="RMM hostname selector for harness, defaults to remote host")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.password:
        print("Missing password. Pass --password or set NEO_WINRM_PASSWORD.", file=sys.stderr)
        return 2

    package = pathlib.Path(args.package).resolve()
    if not package.exists():
        print(f"Package not found: {package}", file=sys.stderr)
        return 2
    if not zipfile.is_zipfile(package):
        print(f"Package is not a zip file: {package}", file=sys.stderr)
        return 2
    public_key = pathlib.Path(args.public_key).resolve()
    expected_pub_hash = sha256_file(public_key) if public_key.exists() else ""
    if not expected_pub_hash:
        print(f"[WARN] Expected public key not found: {public_key}. Signing-key match cannot be verified.")

    if not port_open(args.host, args.port, timeout=3):
        print(f"WinRM port {args.port} is not reachable on {args.host}. Run Enable-NeoOptimizeWinRM.ps1 in the VM first.", file=sys.stderr)
        return 2

    try:
        import winrm  # type: ignore
    except ImportError:
        print(
            "pywinrm is not installed. Install it with:\n"
            "  python3 -m pip install --user pywinrm\n",
            file=sys.stderr,
        )
        return 2

    endpoint = f"{args.scheme}://{args.host}:{args.port}/wsman"
    print(f"[+] Connecting to {endpoint} as {args.user} ({args.transport})")
    session = winrm.Session(endpoint, auth=(args.user, args.password), transport=args.transport)

    remote_zip = join_win(args.remote_root, package.name)
    run_ps_checked(session, rf"New-Item -Path '{ps_quote(args.remote_root)}' -ItemType Directory -Force | Out-Null")

    if not args.skip_upload:
        upload_file(session, package, remote_zip, args.chunk_size)

    deploy_result = run_remote_deploy(session, args, remote_zip)
    if expected_pub_hash:
        deploy_result["expected_signing_pub_sha256"] = expected_pub_hash
        deploy_result["signing_key_match"] = (
            deploy_result.get("signing_pub_sha256", "").lower() == expected_pub_hash.lower()
        )
        if not deploy_result["signing_key_match"]:
            print("[WARN] Remote signing.pub.pem does not match server signing key. E2E safety commands will be rejected.")
    print(json.dumps(deploy_result, indent=2))

    if args.run_smoke:
        hostname = args.hostname or deploy_result.get("hostname") or args.host
        run_local_harness("runtime-smoke", hostname, timeout=90)
        if args.run_rollback:
            run_local_harness("rollback", hostname, timeout=180)

    return 0


def upload_file(session: "winrm.Session", local_path: pathlib.Path, remote_path: str, chunk_size: int) -> None:
    total = local_path.stat().st_size
    print(f"[+] Uploading {local_path.name} ({total:,} bytes) to {remote_path}")

    run_ps_checked(
        session,
        rf"""
$path = '{ps_quote(remote_path)}'
$dir = Split-Path -Parent $path
New-Item -Path $dir -ItemType Directory -Force | Out-Null
if (Test-Path $path) {{ Remove-Item -Path $path -Force }}
[System.IO.File]::WriteAllBytes($path, [byte[]]::new(0))
""",
    )

    sent = 0
    with local_path.open("rb") as handle:
        while True:
            chunk = handle.read(chunk_size)
            if not chunk:
                break
            encoded = base64.b64encode(chunk).decode("ascii")
            run_ps_checked(
                session,
                rf"""
$path = '{ps_quote(remote_path)}'
$bytes = [Convert]::FromBase64String('{encoded}')
$stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
try {{ $stream.Write($bytes, 0, $bytes.Length) }} finally {{ $stream.Dispose() }}
""",
            )
            sent += len(chunk)
            print(f"    uploaded {sent:,}/{total:,} bytes", end="\r", flush=True)
    print()


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def run_remote_deploy(session: "winrm.Session", args: argparse.Namespace, remote_zip: str) -> dict:
    enable_lab = "$true" if args.enable_lab_commands else "$false"
    script = rf"""
$ErrorActionPreference = "Stop"
$PackageZip = '{ps_quote(remote_zip)}'
$InstallDir = '{ps_quote(args.install_dir)}'
$RemoteRoot = '{ps_quote(args.remote_root)}'
$ServerUrl = '{ps_quote(args.server_url)}'
$ServiceName = '{ps_quote(args.service_name)}'
$EnableLabCommands = {enable_lab}

function Get-PropValue {{
    param($Object, [string]$Name, $Default = $null)
    if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name) {{
        return $Object.$Name
    }}
    return $Default
}}

function Normalize-Config {{
    param($OldConfig)
    $telemetry = Get-PropValue $OldConfig "Telemetry" $null
    if ($null -eq $telemetry) {{
        $telemetry = [ordered]@{{
            CollectDeviceCapabilities = $true
            CollectApproxLocation = $false
            CollectVerboseDiagnostics = $false
        }}
    }}
    $safety = Get-PropValue $OldConfig "Safety" $null
    if ($null -eq $safety) {{ $safety = [ordered]@{{}} }}
    $safety | Add-Member -NotePropertyName EnableLabCommands -NotePropertyValue $EnableLabCommands -Force
    if (-not ($safety.PSObject.Properties.Name -contains "SecureStorePath")) {{
        $safety | Add-Member -NotePropertyName SecureStorePath -NotePropertyValue "%ProgramData%\NeoOptimize\SecureStore" -Force
    }}
    if (-not ($safety.PSObject.Properties.Name -contains "CrashLoopThreshold")) {{
        $safety | Add-Member -NotePropertyName CrashLoopThreshold -NotePropertyValue 2 -Force
    }}

    [ordered]@{{
        ServerUrl = $(if ([string]::IsNullOrWhiteSpace($ServerUrl)) {{ Get-PropValue $OldConfig "ServerUrl" "http://192.168.122.1:3000" }} else {{ $ServerUrl.TrimEnd("/") }})
        ApiKey = Get-PropValue $OldConfig "ApiKey" ""
        EnrollmentToken = Get-PropValue $OldConfig "EnrollmentToken" ""
        AllowInsecureTls = [bool](Get-PropValue $OldConfig "AllowInsecureTls" $false)
        Telemetry = $telemetry
        Safety = $safety
    }}
}}

$existingConfigPath = Join-Path $InstallDir "appsettings.json"
$oldConfig = $null
if (Test-Path $existingConfigPath) {{
    try {{ $oldConfig = Get-Content -Raw -Path $existingConfigPath | ConvertFrom-Json }} catch {{ $oldConfig = $null }}
}}

$extractDir = Join-Path $RemoteRoot ("agent_" + (Get-Date -Format "yyyyMMdd_HHmmss"))
New-Item -Path $extractDir -ItemType Directory -Force | Out-Null
Expand-Archive -Path $PackageZip -DestinationPath $extractDir -Force
$sourceDir = Get-ChildItem -Path $extractDir -Directory | Select-Object -First 1
if ($null -eq $sourceDir) {{ $sourceDir = Get-Item $extractDir }}

$exe = Join-Path $sourceDir.FullName "NeoOptimize.Agent.exe"
if (-not (Test-Path $exe)) {{ throw "NeoOptimize.Agent.exe not found in package." }}
$pub = Join-Path $sourceDir.FullName "signing.pub.pem"
if (-not (Test-Path $pub)) {{ throw "signing.pub.pem not found in package." }}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($service) {{
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}}

New-Item -Path $InstallDir -ItemType Directory -Force | Out-Null
Copy-Item -Path (Join-Path $sourceDir.FullName "NeoOptimize.Agent.exe") -Destination (Join-Path $InstallDir "NeoOptimize.Agent.exe") -Force
foreach ($folder in @("modules", "lib")) {{
    $src = Join-Path $sourceDir.FullName $folder
    if (Test-Path $src) {{
        $dst = Join-Path $InstallDir $folder
        if (Test-Path $dst) {{ Remove-Item -Path $dst -Recurse -Force }}
        Copy-Item -Path $src -Destination $InstallDir -Recurse -Force
    }}
}}
foreach ($file in @("signing.pub.pem", "NeoOptimize_Uninstaller.ps1")) {{
    $src = Join-Path $sourceDir.FullName $file
    if (Test-Path $src) {{ Copy-Item -Path $src -Destination (Join-Path $InstallDir $file) -Force }}
}}

$config = Normalize-Config -OldConfig $oldConfig
$config | ConvertTo-Json -Depth 8 | Set-Content -Path $existingConfigPath -Encoding UTF8

$exeTarget = Join-Path $InstallDir "NeoOptimize.Agent.exe"
if (-not $service) {{
    New-Service -Name $ServiceName `
        -BinaryPathName "`"$exeTarget`"" `
        -DisplayName "NeoOptimize RMM Agent" `
        -Description "Authorized NeoOptimize remote monitoring and maintenance agent." `
        -StartupType Automatic | Out-Null
}} else {{
    sc.exe config $ServiceName binPath= "`"$exeTarget`"" start= auto | Out-Null
}}

Start-Service -Name $ServiceName
Start-Sleep -Seconds 2
$status = Get-Service -Name $ServiceName

$result = [ordered]@{{
    ok = $true
    hostname = $env:COMPUTERNAME
    service = $ServiceName
    service_status = $status.Status.ToString()
    install_dir = $InstallDir
    exe_sha256 = (Get-FileHash -Path $exeTarget -Algorithm SHA256).Hash.ToLowerInvariant()
    signing_pub_sha256 = (Get-FileHash -Path (Join-Path $InstallDir "signing.pub.pem") -Algorithm SHA256).Hash.ToLowerInvariant()
    server_url = $config.ServerUrl
    api_key_preserved = -not [string]::IsNullOrWhiteSpace([string]$config.ApiKey)
    lab_commands_enabled = [bool]$config.Safety.EnableLabCommands
}}
$result | ConvertTo-Json -Depth 8
"""
    output = run_ps_checked(session, script)
    return parse_last_json(output)


def run_local_harness(mode: str, hostname: str, timeout: int) -> None:
    import subprocess

    command = [
        "node",
        str(ROOT / "tools" / "Invoke-AgentSafetyE2E.js"),
        "--mode",
        mode,
        "--hostname",
        hostname,
        "--timeout",
        str(timeout),
    ]
    print(f"[+] Running {' '.join(command)}")
    subprocess.run(command, cwd=ROOT, check=True)


def run_ps_checked(session: "winrm.Session", script: str) -> str:
    result = session.run_ps(script)
    stdout = result.std_out.decode("utf-8", errors="replace")
    stderr = result.std_err.decode("utf-8", errors="replace")
    if result.status_code != 0:
        raise RuntimeError(f"WinRM PowerShell failed with code {result.status_code}\nSTDOUT:\n{stdout}\nSTDERR:\n{stderr}")
    return stdout.strip()


def parse_last_json(output: str) -> dict:
    lines = [line.strip() for line in output.splitlines() if line.strip()]
    for index in range(len(lines)):
        candidate = "\n".join(lines[index:])
        try:
            return json.loads(candidate)
        except json.JSONDecodeError:
            continue
    raise RuntimeError(f"Could not parse JSON from remote output:\n{output}")


def port_open(host: str, port: int, timeout: int) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def join_win(left: str, right: str) -> str:
    return left.rstrip("\\/") + "\\" + right


def ps_quote(value: str) -> str:
    return str(value).replace("'", "''")


if __name__ == "__main__":
    raise SystemExit(main())
