#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const root = process.cwd();
const releaseDir = path.join(root, 'release');
const stageDir = path.join(releaseDir, 'NeoMonitor-Installer');
const appDir = path.join(stageDir, 'app');
const monitorSrcDir = path.join(root, 'monitor');

function rmrf(target) {
  if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
}

function ensureDir(target) {
  if (!fs.existsSync(target)) fs.mkdirSync(target, { recursive: true });
}

function copyRecursive(src, dest) {
  const stat = fs.statSync(src);
  if (stat.isDirectory()) {
    ensureDir(dest);
    for (const name of fs.readdirSync(src)) {
      copyRecursive(path.join(src, name), path.join(dest, name));
    }
    return;
  }
  ensureDir(path.dirname(dest));
  fs.copyFileSync(src, dest);
}

function writeText(filePath, text) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, text, 'utf-8');
}

function getRootDeps() {
  const raw = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf-8'));
  const deps = raw.dependencies || {};
  return {
    express: deps.express || '^4.21.2',
    'body-parser': deps['body-parser'] || '^1.20.3',
    cors: deps.cors || '^2.8.5'
  };
}

function buildInstaller() {
  rmrf(stageDir);
  ensureDir(appDir);

  copyRecursive(path.join(monitorSrcDir, 'server.js'), path.join(appDir, 'server.js'));
  copyRecursive(path.join(monitorSrcDir, 'public'), path.join(appDir, 'public'));
  copyRecursive(path.join(monitorSrcDir, 'README.md'), path.join(appDir, 'README.md'));

  const deps = getRootDeps();
  const appPkg = {
    name: 'neomonitor-server',
    version: '1.0.0',
    private: true,
    type: 'module',
    description: 'NeoMonitor remote control server for NeoOptimize agents',
    main: 'server.js',
    scripts: {
      start: 'node server.js'
    },
    dependencies: deps
  };
  writeText(path.join(appDir, 'package.json'), `${JSON.stringify(appPkg, null, 2)}\n`);
  writeText(
    path.join(appDir, '.env.example'),
    [
      'NEOMONITOR_HOST=0.0.0.0',
      'NEOMONITOR_PORT=4411',
      'NEOMONITOR_ADMIN_TOKEN=change-this-admin-token',
      'NEOMONITOR_AUTO_REGISTER=1',
      ''
    ].join('\n')
  );

  const installPs1 = `
param(
  [string]$InstallDir = "$env:ProgramFiles\\NeoMonitor",
  [string]$MonitorHost = "0.0.0.0",
  [string]$MonitorPort = "4411",
  [string]$AdminToken = ""
)

$ErrorActionPreference = "Stop"

function Ensure-Command([string]$name) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if (-not $cmd) {
    throw "Required command not found: $name. Please install Node.js LTS first."
  }
}

Ensure-Command "node"
Ensure-Command "npm"

if ([string]::IsNullOrWhiteSpace($AdminToken)) {
  $AdminToken = [guid]::NewGuid().ToString("N")
}

if (Test-Path $InstallDir) {
  Remove-Item -Recurse -Force $InstallDir
}
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null

Copy-Item -Recurse -Force "$PSScriptRoot\\app\\*" "$InstallDir\\"

Push-Location $InstallDir
try {
  npm install --omit=dev --no-audit --no-fund
}
finally {
  Pop-Location
}

$envLines = @(
  "NEOMONITOR_HOST=$MonitorHost"
  "NEOMONITOR_PORT=$MonitorPort"
  "NEOMONITOR_ADMIN_TOKEN=$AdminToken"
  "NEOMONITOR_AUTO_REGISTER=1"
)
$envLines -join [Environment]::NewLine | Set-Content -Path "$InstallDir\\.env" -Encoding UTF8

$startCmd = @"
@echo off
setlocal
cd /d "$InstallDir"
node server.js
"@
Set-Content -Path "$InstallDir\\Start-NeoMonitor.cmd" -Value $startCmd -Encoding ASCII

try {
  New-NetFirewallRule -DisplayName "NeoMonitor $MonitorPort" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $MonitorPort -ErrorAction Stop | Out-Null
}
catch {
  Write-Host "Firewall rule skipped: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "NeoMonitor installed to: $InstallDir"
Write-Host "Host: $MonitorHost  Port: $MonitorPort"
Write-Host "Admin token: $AdminToken"
Write-Host "Start server: $InstallDir\\Start-NeoMonitor.cmd"
Write-Host ""
Write-Host "IMPORTANT: Keep admin token secret."
`;
  writeText(path.join(stageDir, 'install-neomonitor.ps1'), installPs1.trimStart());

  const uninstallPs1 = `
param(
  [string]$InstallDir = "$env:ProgramFiles\\NeoMonitor",
  [string]$MonitorPort = "4411"
)

$ErrorActionPreference = "Continue"

if (Test-Path $InstallDir) {
  Remove-Item -Recurse -Force $InstallDir
}

try {
  Get-NetFirewallRule -DisplayName "NeoMonitor $MonitorPort" -ErrorAction SilentlyContinue | Remove-NetFirewallRule -ErrorAction SilentlyContinue
}
catch {}

Write-Host "NeoMonitor removed from: $InstallDir"
`;
  writeText(path.join(stageDir, 'uninstall-neomonitor.ps1'), uninstallPs1.trimStart());

  const installCmd = `@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-neomonitor.ps1" %*
`;
  writeText(path.join(stageDir, 'install-neomonitor.cmd'), installCmd);

  const readme = `
# NeoMonitor Installer

This package installs NeoMonitor as a standalone Node.js service directory.

## Quick Install (Windows, PowerShell as Administrator)

\`\`\`powershell
cd <this-folder>
.\\install-neomonitor.ps1 -MonitorHost 0.0.0.0 -MonitorPort 4411 -AdminToken "<strong-token>"
\`\`\`

Or double click \`install-neomonitor.cmd\`.

## After Install

- Server folder: \`%ProgramFiles%\\NeoMonitor\`
- Start command: \`%ProgramFiles%\\NeoMonitor\\Start-NeoMonitor.cmd\`
- Admin token is stored in \`%ProgramFiles%\\NeoMonitor\\.env\`

## Pair with NeoOptimize agents

Set NeoOptimize monitor URL to your public NeoMonitor endpoint:
\`http://<server-ip-or-domain>:4411\`

Use About page button: \`APPLY RECOMMENDED REMOTE\` so client enables monitor + verbose diagnostics automatically.
`;
  writeText(path.join(stageDir, 'README.md'), readme.trimStart());

  const zipPath = path.join(releaseDir, 'NeoMonitor-Installer.zip');
  if (fs.existsSync(zipPath)) fs.unlinkSync(zipPath);
  execFileSync(
    'powershell',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      `Compress-Archive -Path '${stageDir}\\*' -DestinationPath '${zipPath}' -Force`
    ],
    { stdio: 'inherit' }
  );

  console.log(`[monitor-installer] created: ${zipPath}`);
}

try {
  buildInstaller();
} catch (err) {
  console.error(`[monitor-installer] failed: ${String(err?.message || err)}`);
  process.exit(1);
}
