#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"
ENV_FILE="$SERVER_DIR/.env"
ENV_EXAMPLE="$SERVER_DIR/.env.example"

rand_hex() {
  openssl rand -hex "${1:-16}"
}

rand_b64() {
  openssl rand -base64 "${1:-48}"
}

replace_line() {
  local key="$1"
  local value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

if [ -f "$ENV_FILE" ]; then
  echo "[i] Existing .env preserved: $ENV_FILE"
  exit 0
fi

if [ ! -f "$ENV_EXAMPLE" ]; then
  echo "[!] Missing template: $ENV_EXAMPLE" >&2
  exit 1
fi

cp "$ENV_EXAMPLE" "$ENV_FILE"

replace_line POSTGRES_PASSWORD "$(rand_hex 16)"
replace_line REDIS_PASSWORD "$(rand_hex 16)"
replace_line JWT_SECRET "$(rand_b64 48)"
replace_line SIGNING_KEY_PASSPHRASE "$(rand_hex 24)"
replace_line OPENFANG_API_KEY "$(rand_hex 32)"
replace_line DASHBOARD_ORIGIN "http://localhost:3000"
replace_line KEY_DIR "$SERVER_DIR/keys"

chmod 600 "$ENV_FILE"

echo "[+] Created secure local env: $ENV_FILE"
echo "[i] Review database settings before running migrations in production."
