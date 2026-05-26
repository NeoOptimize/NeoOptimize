#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
APP_DIR="$ROOT_DIR/client-nextgen"
TAURI_DIR="$APP_DIR/src-tauri"
RELEASE_DIR="$ROOT_DIR/release/linux"
STAGE_DIR="${STAGE_DIR:-$(mktemp -d /tmp/neooptimize-linux.XXXXXX)}"
APP_STAGE="$STAGE_DIR/NeoOptimize"
BUILD_LINUX_UI="${BUILD_LINUX_UI:-1}"

cleanup() {
  rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

export PATH="$HOME/.cargo/bin:$PATH"

echo "╔══════════════════════════════════════════════════╗"
echo "║       NeoOptimize Linux Package Builder          ║"
echo "╚══════════════════════════════════════════════════╝"

if ! command -v npm >/dev/null 2>&1; then
  echo "[ERROR] npm is required."
  exit 1
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "[ERROR] cargo/rustc is required."
  exit 1
fi

echo "[1/4] Preparing Rust/Tauri Linux UI binary..."
if [[ "$BUILD_LINUX_UI" == "1" || ! -s "$TAURI_DIR/target/release/neooptimize" ]]; then
  (
    cd "$APP_DIR"
    npm install --no-audit --no-fund || exit 41
    npm run tauri:build -- --no-bundle --ci || exit 42
  )
else
  echo "[OK] Using existing Linux UI binary: $TAURI_DIR/target/release/neooptimize"
fi

echo "[2/4] Staging Linux runtime..."
mkdir -p "$APP_STAGE"
cp "$TAURI_DIR/target/release/neooptimize" "$APP_STAGE/NeoOptimize"
chmod +x "$APP_STAGE/NeoOptimize"

for dir in assets config docs knowledge skills mcp modules-linux; do
  if [[ -d "$ROOT_DIR/client/$dir" ]]; then
    mkdir -p "$APP_STAGE/$dir"
    rsync -a --delete "$ROOT_DIR/client/$dir/" "$APP_STAGE/$dir/"
  fi
done

mkdir -p "$APP_STAGE/tools"
cp "$ROOT_DIR/tools/generate_linux_optimization_corpus.py" "$APP_STAGE/tools/" 2>/dev/null || true

cat > "$APP_STAGE/README-LINUX.txt" <<'TXT'
NeoOptimize Linux package

Run:
  ./NeoOptimize

Linux support is separate from the Windows optimizer engine.
This package uses the Rust UI and Linux modules under modules-linux/.
Write actions are advisory/approval-only; diagnostics are safe by default.
TXT

cat > "$APP_STAGE/neooptimize.desktop" <<'TXT'
[Desktop Entry]
Type=Application
Name=NeoOptimize
Comment=AI-empowered local monitoring and maintenance
Exec=NeoOptimize
Terminal=false
Categories=System;Utility;
TXT

echo "[3/4] Creating tarball..."
mkdir -p "$RELEASE_DIR"
tar -C "$STAGE_DIR" -czf "$RELEASE_DIR/NeoOptimize-linux-x86_64.tar.gz" NeoOptimize
sha256sum "$RELEASE_DIR/NeoOptimize-linux-x86_64.tar.gz" | sed 's# .*/#  #' > "$RELEASE_DIR/NeoOptimize-linux-x86_64.tar.gz.sha256"

echo "[4/4] Done."
ls -lh "$RELEASE_DIR"
