#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(node -p "require('$ROOT_DIR/server/package.json').version")"
STAMP="$(date +%Y%m%d_%H%M%S)"
PACKAGE_NAME="NeoOptimize-${VERSION}-src-${STAMP}"
OUT_DIR="$ROOT_DIR/dist"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$OUT_DIR"

rsync -a --delete \
  --exclude-from="$ROOT_DIR/.distignore" \
  "$ROOT_DIR/" "$TMP_DIR/$PACKAGE_NAME/"

tar -C "$TMP_DIR" -czf "$OUT_DIR/$PACKAGE_NAME.tar.gz" "$PACKAGE_NAME"
sha256sum "$OUT_DIR/$PACKAGE_NAME.tar.gz" > "$OUT_DIR/$PACKAGE_NAME.tar.gz.sha256"

echo "$OUT_DIR/$PACKAGE_NAME.tar.gz"
echo "$OUT_DIR/$PACKAGE_NAME.tar.gz.sha256"
