#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# NeoOptimize Client Installer — Build Script
# Compiles NSIS installer from source on Linux
# ═══════════════════════════════════════════════════════════════════

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
RELEASE_DIR="$ROOT_DIR/release"
UI_WRAPPER_EXE="$ROOT_DIR/wrapper/NeoOptimizeUIWrapper/publish/win-x64/NeoOptimizeUIWrapper.exe"
OPTIMIZER_EXE="${OPTIMIZER_EXE:-$UI_WRAPPER_EXE}"
AGENT_EXE="${AGENT_EXE:-}"
CODESIGN_PFX="${CODESIGN_PFX:-$ROOT_DIR/certs/codesign.pfx}"
CODESIGN_PASS="${CODESIGN_PASS:-}"
CODESIGN_NAME="${CODESIGN_NAME:-Zenthralix Lab}"
CODESIGN_URL="${CODESIGN_URL:-https://neooptimize.local}"
CODESIGN_TIMESTAMP_URL="${CODESIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}"
PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE:-$ROOT_DIR/server/keys/signing.pub.pem}"
BUILD_TMP_DIR="${BUILD_TMP_DIR:-$(mktemp -d /tmp/neooptimize-build.XXXXXX)}"

cleanup_build_tmp() {
  rm -rf "$BUILD_TMP_DIR"
}
trap cleanup_build_tmp EXIT

sign_binary() {
  local input="$1"
  local output="$2"
  local product="$3"

  if [[ ! -f "$CODESIGN_PFX" || -z "$CODESIGN_PASS" ]]; then
    echo "[WARN] Code-signing skipped for $product. Set CODESIGN_PFX and CODESIGN_PASS."
    return 0
  fi
  if ! command -v osslsigncode >/dev/null 2>&1; then
    echo "[WARN] osslsigncode not found; code-signing skipped for $product."
    return 0
  fi

  echo "[SIGN] $product"
  if ! osslsigncode sign \
      -pkcs12 "$CODESIGN_PFX" \
      -pass "$CODESIGN_PASS" \
      -n "$product" \
      -i "$CODESIGN_URL" \
      -t "$CODESIGN_TIMESTAMP_URL" \
      -in "$input" \
      -out "$output"; then
    echo "[WARN] Timestamped signing failed; retrying without timestamp."
    osslsigncode sign \
      -pkcs12 "$CODESIGN_PFX" \
      -pass "$CODESIGN_PASS" \
      -n "$product" \
      -i "$CODESIGN_URL" \
      -in "$input" \
      -out "$output"
  fi
}

echo "╔══════════════════════════════════════════════════╗"
echo "║     NeoOptimize Client Installer Builder         ║"
echo "╚══════════════════════════════════════════════════╝"

# 1. Rebuild agent for Windows
mkdir -p "$ROOT_DIR/installer/client/bin"
echo "[1/5] Building Windows agent..."
if [[ -n "$AGENT_EXE" && -s "$AGENT_EXE" ]]; then
  cp "$AGENT_EXE" "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe"
else
  AGENT_PUBLISH_DIR="$BUILD_TMP_DIR/agent-publish"
  mkdir -p "$AGENT_PUBLISH_DIR"
  dotnet publish "$ROOT_DIR/agent/NeoOptimize.Agent.csproj" \
    -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:PublishReadyToRun=false \
    -p:BaseIntermediateOutputPath="$BUILD_TMP_DIR/agent-obj/" \
    -p:BaseOutputPath="$BUILD_TMP_DIR/agent-bin/" \
    -o "$AGENT_PUBLISH_DIR" \
    --nologo --verbosity minimal
  cp "$AGENT_PUBLISH_DIR/NeoOptimize.Agent.exe" \
     "$ROOT_DIR/installer/client/bin/"
fi

# 2. Sign agent exe when a real signing certificate is supplied
echo "[2/5] Signing agent executable..."
if [[ -f "$CODESIGN_PFX" && -n "$CODESIGN_PASS" ]]; then
  sign_binary \
    "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe" \
    "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe.signed" \
    "NeoOptimize RMM Agent"
  mv "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe.signed" \
     "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe"
else
  echo "[WARN] Code-signing skipped. Set CODESIGN_PFX and CODESIGN_PASS to sign release binaries."
fi

# 3. Copy optimizer UI wrapper
echo "[3/5] Building and copying NeoOptimize UI launcher..."
if [[ "$OPTIMIZER_EXE" == "$UI_WRAPPER_EXE" || ! -s "$OPTIMIZER_EXE" ]]; then
  WRAPPER_PUBLISH_DIR="$BUILD_TMP_DIR/wrapper-publish"
  mkdir -p "$WRAPPER_PUBLISH_DIR"
  dotnet publish "$ROOT_DIR/wrapper/NeoOptimizeUIWrapper/NeoOptimizeUIWrapper.csproj" \
    -c Release -r win-x64 --self-contained true \
    -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
    -p:PublishReadyToRun=false \
    -p:BaseIntermediateOutputPath="$BUILD_TMP_DIR/wrapper-obj/" \
    -p:BaseOutputPath="$BUILD_TMP_DIR/wrapper-bin/" \
    -o "$WRAPPER_PUBLISH_DIR" \
    --nologo --verbosity minimal
  OPTIMIZER_EXE="$WRAPPER_PUBLISH_DIR/NeoOptimizeUIWrapper.exe"
fi

if [ -s "$OPTIMIZER_EXE" ]; then
  cp "$OPTIMIZER_EXE" "$ROOT_DIR/installer/client/bin/NeoOptimize.exe"
  if [[ -f "$CODESIGN_PFX" && -n "$CODESIGN_PASS" ]]; then
    sign_binary \
      "$ROOT_DIR/installer/client/bin/NeoOptimize.exe" \
      "$ROOT_DIR/installer/client/bin/NeoOptimize.exe.signed" \
      "NeoOptimize UI Launcher"
    mv "$ROOT_DIR/installer/client/bin/NeoOptimize.exe.signed" \
       "$ROOT_DIR/installer/client/bin/NeoOptimize.exe"
  fi
else
  echo "[ERROR] NeoOptimize UI launcher not found. Set OPTIMIZER_EXE=/path/to/NeoOptimizeUIWrapper.exe before building."
  exit 1
fi

# 4. Copy modules and lib
echo "[4/5] Bundling UI, modules, AI configs, and agent runtime..."

for file in \
  NeoOptimize.UI.ps1 \
  NeoOptimize.ps1 \
  NeoOptimize.UpdateManager.ps1 \
  NeoOptimize.AIAgent.ps1 \
  NeoOptimize.Cloud.ps1 \
  NeoOptimize.VoiceCommand.ps1 \
  NeoOptimizeAgent.ps1 \
  LAUNCH.bat \
  QuickStart.bat \
  CREATE_RESTORE_POINT.ps1 \
  ai_engine.py \
  VERSION.txt; do
  if [[ -s "$ROOT_DIR/client/$file" ]]; then
    cp "$ROOT_DIR/client/$file" "$ROOT_DIR/installer/client/$file"
  fi
done

mkdir -p \
  "$ROOT_DIR/installer/client/modules" \
  "$ROOT_DIR/installer/client/lib" \
  "$ROOT_DIR/installer/client/assets" \
  "$ROOT_DIR/installer/client/config" \
  "$ROOT_DIR/installer/client/models" \
  "$ROOT_DIR/installer/client/datasets" \
  "$ROOT_DIR/installer/client/docs" \
  "$ROOT_DIR/installer/client/skills" \
  "$ROOT_DIR/installer/client/mcp" \
  "$ROOT_DIR/installer/client/tools"

rsync -a --delete "$ROOT_DIR/client/assets/"   "$ROOT_DIR/installer/client/assets/"
rsync -a --delete "$ROOT_DIR/client/config/"   "$ROOT_DIR/installer/client/config/"
rsync -a --delete "$ROOT_DIR/client/models/"   "$ROOT_DIR/installer/client/models/"
rsync -a --delete "$ROOT_DIR/client/datasets/" "$ROOT_DIR/installer/client/datasets/"
rsync -a --delete "$ROOT_DIR/client/docs/"     "$ROOT_DIR/installer/client/docs/"
rsync -a --delete "$ROOT_DIR/client/skills/"   "$ROOT_DIR/installer/client/skills/"
rsync -a --delete "$ROOT_DIR/client/mcp/"      "$ROOT_DIR/installer/client/mcp/"
rsync -a --delete "$ROOT_DIR/client/tools/"    "$ROOT_DIR/installer/client/tools/"

# Agent-only modules such as 17_NeoOptimizeUpdate.ps1 are bundled first.
# Client modules/lib are the safety-reviewed source of truth and intentionally
# overwrite same-named legacy agent modules.
rsync -a --delete "$ROOT_DIR/agent/modules/"  "$ROOT_DIR/installer/client/modules/"
rsync -a "$ROOT_DIR/client/modules/"          "$ROOT_DIR/installer/client/modules/"
rsync -a --delete "$ROOT_DIR/agent/lib/"      "$ROOT_DIR/installer/client/lib/"
rsync -a "$ROOT_DIR/client/lib/"              "$ROOT_DIR/installer/client/lib/"

if [[ ! -s "$PUBLIC_KEY_FILE" ]]; then
  echo "[ERROR] signing.pub.pem not found. Run server keygen first or set PUBLIC_KEY_FILE=/path/to/signing.pub.pem."
  exit 1
fi
cp "$PUBLIC_KEY_FILE" "$ROOT_DIR/installer/client/signing.pub.pem"
cp "$PUBLIC_KEY_FILE" "$ROOT_DIR/installer/client/assets/signing.pub.pem"
cp "$ROOT_DIR/agent/NeoOptimize_Uninstaller.ps1" "$ROOT_DIR/installer/client/NeoOptimize_Uninstaller.ps1"

# Create assets dir if missing
mkdir -p "$ROOT_DIR/installer/client/assets"
[ ! -f "$ROOT_DIR/installer/client/assets/icon.ico" ] && \
  convert -size 256x256 xc:#00c6ff "$ROOT_DIR/installer/client/assets/icon.ico" 2>/dev/null || true

# Create LICENSE
[ ! -f "$ROOT_DIR/installer/client/LICENSE.txt" ] && cat > "$ROOT_DIR/installer/client/LICENSE.txt" << 'LICENSE'
NeoOptimize Software License
Copyright (c) 2025 Zenthralix Technologies
All rights reserved.
This software is proprietary and may only be used by authorized personnel.
LICENSE

# 5. Compile NSIS
echo "[5/5] Compiling NSIS installer..."
cd "$ROOT_DIR/installer/client"
makensis installer.nsi

mkdir -p "$RELEASE_DIR"
mv NeoOptimize.exe "$RELEASE_DIR/"

if [[ -f "$CODESIGN_PFX" && -n "$CODESIGN_PASS" ]]; then
  sign_binary \
    "$RELEASE_DIR/NeoOptimize.exe" \
    "$RELEASE_DIR/NeoOptimize.exe.signed" \
    "NeoOptimize Client Setup" && \
  mv "$RELEASE_DIR/NeoOptimize.exe.signed" \
     "$RELEASE_DIR/NeoOptimize.exe"
fi

# Copy to web server for download
cp "$RELEASE_DIR/NeoOptimize.exe" /opt/neooptimize-rmm/downloads/ 2>/dev/null || true

echo ""
echo "✅ Build complete!"
echo "   Installer: $RELEASE_DIR/NeoOptimize.exe"
ls -lh "$RELEASE_DIR/"
