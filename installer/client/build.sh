#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# NeoOptimize Installer — Build Script
# Compiles NSIS installer from source on Linux
# ═══════════════════════════════════════════════════════════════════

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
RELEASE_ROOT="$ROOT_DIR/release"
RELEASE_DIR="$RELEASE_ROOT/windows"
UI_WRAPPER_EXE="$ROOT_DIR/wrapper/NeoOptimizeUIWrapper/publish/win-x64/NeoOptimizeUIWrapper.exe"
RUST_UI_DIR="$ROOT_DIR/client-nextgen"
RUST_UI_TARGET="${RUST_UI_TARGET:-x86_64-pc-windows-gnu}"
RUST_UI_EXE="${RUST_UI_EXE:-$RUST_UI_DIR/src-tauri/target/$RUST_UI_TARGET/release/neooptimize.exe}"
WEBVIEW2_LOADER_DLL="${WEBVIEW2_LOADER_DLL:-}"
USE_RUST_UI="${USE_RUST_UI:-1}"
BUILD_RUST_UI="${BUILD_RUST_UI:-1}"
ALLOW_LEGACY_UI="${ALLOW_LEGACY_UI:-0}"
OPTIMIZER_EXE="${OPTIMIZER_EXE:-}"
AGENT_EXE="${AGENT_EXE:-}"
CODESIGN_PFX="${CODESIGN_PFX:-$ROOT_DIR/certs/codesign.pfx}"
CODESIGN_PASS="${CODESIGN_PASS:-}"
CODESIGN_NAME="${CODESIGN_NAME:-Zenthralix Lab}"
CODESIGN_URL="${CODESIGN_URL:-https://neooptimize.local}"
CODESIGN_TIMESTAMP_URL="${CODESIGN_TIMESTAMP_URL:-http://timestamp.digicert.com}"
PUBLIC_KEY_FILE="${PUBLIC_KEY_FILE:-$ROOT_DIR/client/assets/signing.pub.pem}"
BUILD_TMP_DIR="${BUILD_TMP_DIR:-$(mktemp -d /tmp/neooptimize-build.XXXXXX)}"
PUBLIC_LIGHT="${PUBLIC_LIGHT:-1}"
# Keep the release installer small. The installed Local AI helper downloads the
# official Ollama setup in a hidden background worker on the endpoint.
BUNDLE_OLLAMA_SETUP="${BUNDLE_OLLAMA_SETUP:-0}"
REQUIRE_OLLAMA_SETUP="${REQUIRE_OLLAMA_SETUP:-0}"
OLLAMA_SETUP_URL="${OLLAMA_SETUP_URL:-https://ollama.com/download/OllamaSetup.exe}"
BUNDLE_OLLAMA_MODELS="${BUNDLE_OLLAMA_MODELS:-0}"
REQUIRE_OLLAMA_MODELS="${REQUIRE_OLLAMA_MODELS:-0}"
OLLAMA_MODELS_SOURCE="${OLLAMA_MODELS_SOURCE:-/usr/share/ollama/.ollama/models}"
OLLAMA_BUNDLE_MODELS="${OLLAMA_BUNDLE_MODELS:-neo-light:latest neo:latest}"

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

prepare_rust_ui() {
  if [[ "$USE_RUST_UI" != "1" ]]; then
    return 1
  fi

  if [[ "$BUILD_RUST_UI" != "1" && -s "$RUST_UI_EXE" ]]; then
    OPTIMIZER_EXE="$RUST_UI_EXE"
    echo "[OK] Using existing Rust/Tauri UI: $OPTIMIZER_EXE"
    return 0
  fi

  if [[ "$BUILD_RUST_UI" != "1" ]]; then
    echo "[WARN] Rust UI executable not found and BUILD_RUST_UI=0."
    return 1
  fi

  if [[ ! -d "$RUST_UI_DIR" ]]; then
    echo "[WARN] Rust UI source directory missing: $RUST_UI_DIR"
    return 1
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo "[WARN] npm not found; cannot build Rust/Tauri UI."
    return 1
  fi

  if ! command -v cargo >/dev/null 2>&1; then
    echo "[WARN] cargo/rustc not found; cannot build Rust/Tauri UI. Falling back to legacy launcher."
    return 1
  fi

  echo "[RUST] Building NeoOptimize Rust/Tauri UI..."
  (
    cd "$RUST_UI_DIR"
    NODE_ENV=development npm install --include=dev --no-audit --no-fund || exit 41
    NODE_ENV=production npm run tauri:build -- --target "$RUST_UI_TARGET" --no-bundle --ci || exit 43
  ) || return 1

  if [[ -s "$RUST_UI_EXE" ]]; then
    OPTIMIZER_EXE="$RUST_UI_EXE"
    echo "[OK] Rust/Tauri UI built: $OPTIMIZER_EXE"
    return 0
  fi

  echo "[WARN] Rust/Tauri build finished but executable was not found: $RUST_UI_EXE"
  return 1
}

echo "╔══════════════════════════════════════════════════╗"
echo "║          NeoOptimize Installer Builder           ║"
echo "╚══════════════════════════════════════════════════╝"

# 1. Public source builds the standalone NeoOptimize client and does not bundle
# the private backend endpoint connector.
mkdir -p "$ROOT_DIR/installer/client/bin"
echo "[1/5] Preparing standalone client package..."
if [[ "$PUBLIC_LIGHT" == "1" ]]; then
  rm -f "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe"
  echo "[SKIP] Public source package does not bundle the endpoint sync agent."
elif [[ -n "$AGENT_EXE" && -s "$AGENT_EXE" ]]; then
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
if [[ "$PUBLIC_LIGHT" == "1" ]]; then
  echo "[SKIP] No bundled endpoint sync agent to sign."
elif [[ -f "$CODESIGN_PFX" && -n "$CODESIGN_PASS" ]]; then
  sign_binary \
    "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe" \
    "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe.signed" \
    "NeoOptimize Endpoint Sync Agent"
  mv "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe.signed" \
     "$ROOT_DIR/installer/client/bin/NeoOptimize.Agent.exe"
else
  echo "[WARN] Code-signing skipped. Set CODESIGN_PFX and CODESIGN_PASS to sign release binaries."
fi

# 3. Build/copy optimizer native UI
echo "[3/5] Preparing NeoOptimize native UI..."
if [[ -n "$OPTIMIZER_EXE" && -s "$OPTIMIZER_EXE" ]]; then
  echo "[OK] Using explicit OPTIMIZER_EXE: $OPTIMIZER_EXE"
elif prepare_rust_ui; then
  :
elif [[ "$ALLOW_LEGACY_UI" == "1" ]]; then
  echo "[WARN] Rust/Tauri UI unavailable. Building legacy .NET launcher as fallback."
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
else
  echo "[ERROR] Rust/Tauri UI build failed and ALLOW_LEGACY_UI=0. Refusing to publish the legacy UI."
  exit 1
fi

if [ -s "$OPTIMIZER_EXE" ]; then
  cp "$OPTIMIZER_EXE" "$ROOT_DIR/installer/client/bin/NeoOptimize.exe"

  # Tauri Windows builds dynamically load WebView2Loader.dll from the
  # executable directory. Without this file the app installs successfully but
  # fails at launch with "WebView2Loader.dll was not found".
  if [[ -z "$WEBVIEW2_LOADER_DLL" ]]; then
    candidate="$(dirname "$OPTIMIZER_EXE")/WebView2Loader.dll"
    if [[ -s "$candidate" ]]; then
      WEBVIEW2_LOADER_DLL="$candidate"
    fi
  fi
  if [[ -z "$WEBVIEW2_LOADER_DLL" ]]; then
    candidate="$RUST_UI_DIR/src-tauri/target/x86_64-pc-windows-gnu/release/WebView2Loader.dll"
    if [[ -s "$candidate" ]]; then
      WEBVIEW2_LOADER_DLL="$candidate"
    fi
  fi
  if [[ -n "$WEBVIEW2_LOADER_DLL" && -s "$WEBVIEW2_LOADER_DLL" ]]; then
    cp "$WEBVIEW2_LOADER_DLL" "$ROOT_DIR/installer/client/bin/WebView2Loader.dll"
    echo "[OK] Bundled WebView2 loader: $WEBVIEW2_LOADER_DLL"
  else
    rm -f "$ROOT_DIR/installer/client/bin/WebView2Loader.dll"
    echo "[WARN] WebView2Loader.dll not found. Windows Tauri UI may fail to launch."
  fi

  if [[ -f "$CODESIGN_PFX" && -n "$CODESIGN_PASS" ]]; then
    sign_binary \
      "$ROOT_DIR/installer/client/bin/NeoOptimize.exe" \
      "$ROOT_DIR/installer/client/bin/NeoOptimize.exe.signed" \
      "NeoOptimize UI Launcher"
    mv "$ROOT_DIR/installer/client/bin/NeoOptimize.exe.signed" \
       "$ROOT_DIR/installer/client/bin/NeoOptimize.exe"
  fi
else
  echo "[ERROR] NeoOptimize native UI not found. Set OPTIMIZER_EXE=/path/to/NeoOptimize.exe or install Rust/Cargo to build client-nextgen."
  exit 1
fi

# 4. Copy modules and lib
echo "[4/5] Bundling UI, modules, AI configs, skills, and tools..."

for file in \
  NeoOptimize.UI.ps1 \
  NeoOptimize.ps1 \
  NeoOptimize.UpdateManager.ps1 \
  NeoOptimize.AIAgent.ps1 \
  NeoOptimize.AgenticRunner.ps1 \
  NeoOptimize.Tray.ps1 \
  NeoOptimize.Cloud.ps1 \
  NeoOptimize.VoiceCommand.ps1 \
  NeoOptimizeAgent.ps1 \
  NeoOptimize.Launcher.ps1 \
  LAUNCH.bat \
  QuickStart.bat \
  CREATE_RESTORE_POINT.ps1 \
  README_ZENTHRALIX_LAB.txt \
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
  "$ROOT_DIR/installer/client/knowledge" \
  "$ROOT_DIR/installer/client/skills" \
  "$ROOT_DIR/installer/client/mcp" \
  "$ROOT_DIR/installer/client/tools"

rsync -a --delete "$ROOT_DIR/client/assets/"   "$ROOT_DIR/installer/client/assets/"
rsync -a --delete "$ROOT_DIR/client/config/"   "$ROOT_DIR/installer/client/config/"
rsync -a --delete "$ROOT_DIR/client/models/"   "$ROOT_DIR/installer/client/models/"
rsync -a --delete "$ROOT_DIR/client/datasets/" "$ROOT_DIR/installer/client/datasets/"
rsync -a --delete "$ROOT_DIR/client/docs/"     "$ROOT_DIR/installer/client/docs/"
rsync -a --delete "$ROOT_DIR/client/knowledge/" "$ROOT_DIR/installer/client/knowledge/"
rsync -a --delete "$ROOT_DIR/client/skills/"   "$ROOT_DIR/installer/client/skills/"
rsync -a --delete "$ROOT_DIR/client/mcp/"      "$ROOT_DIR/installer/client/mcp/"
rsync -a --delete "$ROOT_DIR/client/tools/"    "$ROOT_DIR/installer/client/tools/"

rm -rf "$ROOT_DIR/installer/client/endpoint-agent"

if [[ "$BUNDLE_OLLAMA_SETUP" == "1" ]]; then
  OLLAMA_STAGED="$ROOT_DIR/installer/client/tools/OllamaSetup.exe"
  OLLAMA_SOURCE="$ROOT_DIR/client/tools/OllamaSetup.exe"
  if [[ -s "$OLLAMA_SOURCE" ]]; then
    cp "$OLLAMA_SOURCE" "$OLLAMA_STAGED"
  elif command -v curl >/dev/null 2>&1; then
    echo "[AI] Downloading OllamaSetup.exe for Local AI bootstrap..."
    if curl -L --fail --retry 3 --connect-timeout 20 "$OLLAMA_SETUP_URL" -o "$OLLAMA_STAGED"; then
      sha256sum "$OLLAMA_STAGED" | sed 's# .*/#  #' > "$OLLAMA_STAGED.sha256"
      echo "[OK] Bundled Ollama installer: $OLLAMA_STAGED"
    else
      rm -f "$OLLAMA_STAGED" "$OLLAMA_STAGED.sha256"
      if [[ "$REQUIRE_OLLAMA_SETUP" == "1" ]]; then
        echo "[ERROR] Could not download OllamaSetup.exe and REQUIRE_OLLAMA_SETUP=1."
        exit 1
      fi
      echo "[WARN] Could not download OllamaSetup.exe. Local AI Setup will download it on endpoint."
    fi
  elif [[ "$REQUIRE_OLLAMA_SETUP" == "1" ]]; then
    echo "[ERROR] curl not found and REQUIRE_OLLAMA_SETUP=1."
    exit 1
  else
    echo "[WARN] curl not found. Local AI Setup will download Ollama on endpoint."
  fi
fi

rm -rf "$ROOT_DIR/installer/client/tools/ollama-models"
if [[ "$BUNDLE_OLLAMA_MODELS" == "1" ]]; then
  echo "[AI] Staging offline Ollama models: $OLLAMA_BUNDLE_MODELS"
  node "$ROOT_DIR/tools/stage-ollama-models.js" \
    --source "$OLLAMA_MODELS_SOURCE" \
    --dest "$ROOT_DIR/installer/client/tools/ollama-models/models" \
    --models "$OLLAMA_BUNDLE_MODELS"
else
  echo "[AI] Offline Ollama model bundle disabled. Set BUNDLE_OLLAMA_MODELS=1 to include neo-light:latest and neo:latest."
  if [[ "$REQUIRE_OLLAMA_MODELS" == "1" ]]; then
    echo "[ERROR] REQUIRE_OLLAMA_MODELS=1 but BUNDLE_OLLAMA_MODELS is disabled."
    exit 1
  fi
fi

# Windows packages must not carry Linux tuning artifacts. Linux has its own
# tarball release with separate safety policy and corpus files.
rm -f "$ROOT_DIR/installer/client/config/NeoOptimize.LinuxSafety.json"
rm -f "$ROOT_DIR/installer/client/knowledge/linux-optimization-corpus.jsonl"
rm -f "$ROOT_DIR/installer/client/knowledge/linux-optimization-corpus.manifest.json"
find "$ROOT_DIR/installer/client/tools" -type f -name '*.sh' -delete

WINDOWS_MODEL_CONFIG="$ROOT_DIR/installer/client/config/NeoOptimize.ModelAgent.json"
if [[ -s "$WINDOWS_MODEL_CONFIG" ]]; then
  node -e '
    const fs = require("fs")
    const file = process.argv[1]
    const cfg = JSON.parse(fs.readFileSync(file, "utf8"))
    const corpus = cfg.corpus || {}
    for (const key of ["additional_paths", "additional_manifest_paths"]) {
      if (Array.isArray(corpus[key])) {
        corpus[key] = corpus[key].filter((item) => !String(item).toLowerCase().includes("linux-optimization-corpus"))
      }
    }
    cfg.corpus = corpus
    fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + "\n")
  ' "$WINDOWS_MODEL_CONFIG"
fi

# Public packages use the source tree as the single source of truth so stale
# agent artifacts cannot reappear in the optimizer bundle.
rsync -a --delete "$ROOT_DIR/client/modules/" "$ROOT_DIR/installer/client/modules/"
rm -rf "$ROOT_DIR/installer/client/modules-linux"
rsync -a --delete "$ROOT_DIR/client/lib/"     "$ROOT_DIR/installer/client/lib/"

if [[ ! -s "$PUBLIC_KEY_FILE" ]]; then
  echo "[ERROR] signing.pub.pem not found. Run server keygen first or set PUBLIC_KEY_FILE=/path/to/signing.pub.pem."
  exit 1
fi
cp "$PUBLIC_KEY_FILE" "$ROOT_DIR/installer/client/signing.pub.pem"
cp "$PUBLIC_KEY_FILE" "$ROOT_DIR/installer/client/assets/signing.pub.pem"

echo "[4/5] Verifying public bundle payload..."
node "$ROOT_DIR/tools/verify-public-bundle.js" \
  --client "$ROOT_DIR/client" \
  --staged "$ROOT_DIR/installer/client"

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
    "NeoOptimize Setup" && \
  mv "$RELEASE_DIR/NeoOptimize.exe.signed" \
     "$RELEASE_DIR/NeoOptimize.exe"
fi

(cd "$ROOT_DIR" && sha256sum "release/windows/NeoOptimize.exe") > "$RELEASE_DIR/NeoOptimize.exe.sha256"

mkdir -p "$ROOT_DIR/program"
cp "$RELEASE_DIR/NeoOptimize.exe" "$ROOT_DIR/program/NeoOptimize.exe"
(cd "$ROOT_DIR" && sha256sum "program/NeoOptimize.exe") > "$ROOT_DIR/program/NeoOptimize.exe.sha256"

echo ""
echo "✅ Build complete!"
echo "   Installer: $RELEASE_DIR/NeoOptimize.exe"
echo "   Local mirror: $ROOT_DIR/program/NeoOptimize.exe"
ls -lh "$RELEASE_DIR/"
