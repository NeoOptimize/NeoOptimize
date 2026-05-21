#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER_DIR="$ROOT_DIR/server"
DASHBOARD_DIR="$ROOT_DIR/dashboard"

PASS=0
WARN=0
FAIL=0

ok() { printf '[PASS] %s\n' "$*"; PASS=$((PASS + 1)); }
warn() { printf '[WARN] %s\n' "$*"; WARN=$((WARN + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAIL=$((FAIL + 1)); }

have() {
  command -v "$1" >/dev/null 2>&1
}

check_file() {
  [ -f "$1" ] && ok "found $1" || fail "missing $1"
}

echo "NeoOptimize doctor"
echo "Root: $ROOT_DIR"
echo

check_file "$SERVER_DIR/package.json"
check_file "$SERVER_DIR/schema.sql"
check_file "$SERVER_DIR/.env.example"
check_file "$DASHBOARD_DIR/package.json"
check_file "$ROOT_DIR/agent/NeoOptimize.Agent.csproj"

if have node; then
  NODE_MAJOR="$(node -p "Number(process.versions.node.split('.')[0])" 2>/dev/null || echo 0)"
  if [ "$NODE_MAJOR" -ge 20 ]; then
    ok "Node $(node --version)"
  else
    warn "Node $(node --version) is below 20; scripts will use npx node@20 fallback"
  fi
else
  warn "node not found; install Node 20+ or allow npx node@20 fallback"
fi

have npm && ok "npm $(npm --version)" || fail "npm not found"
have dotnet && ok "dotnet $(dotnet --version)" || warn "dotnet not found; Windows agent build unavailable"
have python3 && ok "python3 $(python3 --version 2>&1)" || warn "python3 not found; AI engine unavailable"

if [ -f "$SERVER_DIR/.env" ]; then
  if awk -F= '
    /^(POSTGRES_PASSWORD|JWT_SECRET|SIGNING_KEY_PASSPHRASE)=/ {
      value = substr($0, index($0, "=") + 1)
      if (value == "" || value ~ /^CHANGE_ME/ || value ~ /^YOUR_/ || value ~ /openssl_rand/) {
        bad = 1
      }
    }
    END { exit bad ? 0 : 1 }
  ' "$SERVER_DIR/.env"; then
    fail "server/.env required secrets still contain placeholders"
  else
    ok "server/.env required secrets look set"
  fi

  if grep -Eq '^(SUPABASE_SERVICE_KEY|HF_TOKEN|E2B_API_KEY|GEMINI_API_KEY|TELEGRAM_BOT_TOKEN|DUCKDNS_TOKEN)=YOUR_|^(SUPABASE_SERVICE_KEY|HF_TOKEN|E2B_API_KEY|GEMINI_API_KEY|TELEGRAM_BOT_TOKEN|DUCKDNS_TOKEN)=$' "$SERVER_DIR/.env"; then
    warn "optional integrations contain empty/placeholders; disabled until configured"
  fi
else
  warn "server/.env missing; run scripts/bootstrap-env.sh"
fi

if [ -f "$SERVER_DIR/keys/signing.priv.pem" ] && [ -f "$SERVER_DIR/keys/signing.pub.pem" ]; then
  ok "server signing keys exist"
else
  warn "server signing keys missing; run npm run keygen in server/"
fi

if have pg_isready; then
  pg_isready -q && ok "PostgreSQL reachable" || warn "PostgreSQL not reachable"
else
  warn "pg_isready not found"
fi

if have redis-cli; then
  redis-cli ping >/dev/null 2>&1 && ok "Redis reachable" || warn "Redis not reachable"
else
  warn "redis-cli not found"
fi

if find "$ROOT_DIR" -maxdepth 4 \
  \( -path "$ROOT_DIR/dist" -o -path "$ROOT_DIR/dist/*" \) -prune -o \
  \( -name node_modules -o -name bin -o -name obj -o -name release -o -name archive -o -path "$DASHBOARD_DIR/dist" \) -print | grep -q .; then
  warn "generated/cache folders exist; run cleanup before packaging"
else
  ok "no generated/cache folders found in first 4 levels"
fi

echo
echo "Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail"
[ "$FAIL" -eq 0 ]
