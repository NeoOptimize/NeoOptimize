#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="$(mktemp)"

cleanup() {
  rm -f "$MANIFEST"
}
trap cleanup EXIT

section() {
  printf '\n== %s ==\n' "$*"
}

run() {
  printf '+'
  printf ' %q' "$@"
  printf '\n'
  "$@"
}

section "Shell syntax"
while IFS= read -r script; do
  run bash -n "$script"
done < <(find "$ROOT_DIR" -maxdepth 2 -type f -name '*.sh' | sort)

section "Server checks"
(
  cd "$ROOT_DIR/server"
  run npm ci
  run npm run audit:prod
  run npm test
)

section "Dashboard checks"
(
  cd "$ROOT_DIR/dashboard"
  run npm ci
  run npm audit --omit=dev --audit-level=high
  run npm run build
)

section "Agent build"
if command -v dotnet >/dev/null 2>&1; then
  run dotnet build "$ROOT_DIR/agent/NeoOptimize.Agent.csproj" --configuration Release
else
  printf '[WARN] dotnet not found; skipping Windows agent build\n'
fi

section "Doctor"
run "$ROOT_DIR/scripts/doctor.sh"

section "Package"
mapfile -t package_output < <("$ROOT_DIR/scripts/package-release.sh")
printf '%s\n' "${package_output[@]}"

PACKAGE_PATH="${package_output[0]:-}"
SHA_PATH="${package_output[1]:-}"

if [ -z "$PACKAGE_PATH" ] || [ ! -f "$PACKAGE_PATH" ]; then
  printf '[FAIL] source package was not created\n' >&2
  exit 1
fi

if [ -z "$SHA_PATH" ] || [ ! -f "$SHA_PATH" ]; then
  printf '[FAIL] source package checksum was not created\n' >&2
  exit 1
fi

section "Artifact safety"
tar -tzf "$PACKAGE_PATH" > "$MANIFEST"

if ! grep -Eq '^[^/]+/server/\.env\.example$' "$MANIFEST"; then
  printf '[FAIL] server/.env.example is missing from source package\n' >&2
  exit 1
fi

if grep -En '^[^/]+/(\.env|server/\.env)$|^[^/]+/server/\.local-|^[^/]+/(server|agent)/keys/|/(node_modules|dist|release|archive|backup|reports|logs|bin|obj)/|[.](log|pid|tmp|zip|tar[.]gz|iso|exe|pdb)$' "$MANIFEST"; then
  printf '[FAIL] source package contains generated files or local secrets\n' >&2
  exit 1
fi

printf '[PASS] source package manifest is clean\n'
sha256sum -c "$SHA_PATH"
