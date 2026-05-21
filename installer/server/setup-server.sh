#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# NeoOptimize RMM — Mini Server Setup
# Installs: Nginx, SSL, download server, systemd services
# Run as: sudo bash setup-server.sh
# ═══════════════════════════════════════════════════════════════════

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RMM_ROOT="${RMM_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
CERT_DIR="$RMM_ROOT/certs"
RELEASE_DIR="$RMM_ROOT/release"
DOWNLOADS_DIR="/opt/neooptimize-rmm/downloads"
HOST_IP=$(hostname -I | awk '{print $1}')

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC}   $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERR]${NC}  $1"; exit 1; }

echo -e "${CYAN}"
cat << 'BANNER'
  ███╗   ██╗███████╗ ██████╗ ██████╗ ██████╗ ████████╗██╗███╗   ███╗██╗███████╗███████╗
  ████╗  ██║██╔════╝██╔═══██╗██╔══██╗██╔══██╗╚══██╔══╝██║████╗ ████║██║╚══███╔╝██╔════╝
  ██╔██╗ ██║█████╗  ██║   ██║██████╔╝██████╔╝   ██║   ██║██╔████╔██║██║  ███╔╝ █████╗
  ██║╚██╗██║██╔══╝  ██║   ██║██╔═══╝ ██╔══██╗   ██║   ██║██║╚██╔╝██║██║ ███╔╝  ██╔══╝
  ██║ ╚████║███████╗╚██████╔╝██║     ██║  ██║   ██║   ██║██║ ╚═╝ ██║██║███████╗███████╗
  ╚═╝  ╚═══╝╚══════╝ ╚═════╝ ╚═╝     ╚═╝  ╚═╝   ╚═╝   ╚═╝╚═╝     ╚═╝╚═╝╚══════╝╚══════╝
                              RMM Mini Server Setup v1.0
BANNER
echo -e "${NC}"

[ "$(id -u)" -ne 0 ] && error "Run as root: sudo bash $0"

info "Host IP detected: $HOST_IP"

# ─── 1. Install nginx ─────────────────────────────────────────────
info "Installing nginx and SSL tooling..."
apt-get update -q && apt-get install -y -q nginx openssl
success "Nginx installed"

# ─── 2. Setup directories ─────────────────────────────────────────
mkdir -p "$DOWNLOADS_DIR"
mkdir -p /etc/nginx/ssl/neooptimize

# Copy SSL certs or generate local self-signed certs
if [[ -s "$CERT_DIR/nginx-ssl.crt" && -s "$CERT_DIR/nginx-ssl.key" ]]; then
  cp "$CERT_DIR/nginx-ssl.crt" /etc/nginx/ssl/neooptimize/server.crt
  cp "$CERT_DIR/nginx-ssl.key" /etc/nginx/ssl/neooptimize/server.key
else
  warn "No SSL certificate found in $CERT_DIR; generating a local self-signed certificate."
  openssl req -x509 -nodes -days 365 \
    -newkey rsa:2048 \
    -keyout /etc/nginx/ssl/neooptimize/server.key \
    -out /etc/nginx/ssl/neooptimize/server.crt \
    -subj "/CN=$HOST_IP" >/dev/null 2>&1
fi
chmod 600 /etc/nginx/ssl/neooptimize/server.key

# Copy release files
[ -f "$RELEASE_DIR/NeoOptimize-Client-Setup.exe" ] && \
  cp "$RELEASE_DIR/NeoOptimize-Client-Setup.exe" "$DOWNLOADS_DIR/"
[ -f "$RELEASE_DIR/NeoOptimize.Agent.signed.exe" ] && \
  cp "$RELEASE_DIR/NeoOptimize.Agent.signed.exe" "$DOWNLOADS_DIR/NeoOptimize.Agent.exe"

success "Directories and certs configured"

# ─── 3. Write nginx config ────────────────────────────────────────
info "Writing nginx configuration..."

cat > /etc/nginx/sites-available/neooptimize << NGINX
# ═══════════════════════════════════════════════════════════
# NeoOptimize RMM — Nginx Reverse Proxy + File Server
# ═══════════════════════════════════════════════════════════

# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name $HOST_IP _;
    return 301 https://\$host\$request_uri;
}

# ─── HTTPS Main Server (Dashboard + API) ────────────────────
server {
    listen 443 ssl http2;
    server_name $HOST_IP _;

    # SSL
    ssl_certificate     /etc/nginx/ssl/neooptimize/server.crt;
    ssl_certificate_key /etc/nginx/ssl/neooptimize/server.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256;
    ssl_prefer_server_ciphers off;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 1d;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Gzip compression
    gzip on;
    gzip_types text/plain application/json application/javascript text/css;

    # ─── Dashboard (React SPA) ─────────────────────────────
    location / {
        root   /opt/neooptimize-rmm/dashboard;
        try_files \$uri \$uri/ /index.html;

        # Cache static assets
        location ~* \.(js|css|png|jpg|ico|svg|woff2)$ {
            expires 7d;
            add_header Cache-Control "public, immutable";
        }
    }

    # ─── API Proxy ─────────────────────────────────────────
    location /api/ {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
        client_max_body_size 10m;
    }

    # ─── WebSocket Proxy ───────────────────────────────────
    location /ws/ {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_set_header   X-Real-IP  \$remote_addr;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}

# ─── Download Server (port 8080, HTTP only) ─────────────────
server {
    listen 8080;
    server_name $HOST_IP _;

    root $DOWNLOADS_DIR;
    autoindex on;
    autoindex_exact_size off;
    autoindex_localtime on;

    add_header X-Content-Type-Options nosniff;
    add_header Content-Disposition "attachment";

    location ~ \.exe$ {
        add_header Content-Type application/octet-stream;
        add_header Content-Disposition "attachment";
    }

    location ~ \.zip$ {
        add_header Content-Type application/zip;
        add_header Content-Disposition "attachment";
    }

    # Rate limit downloads
    limit_rate 10m;
}
NGINX

# Enable site
ln -sf /etc/nginx/sites-available/neooptimize /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
success "Nginx configured with SSL"

# ─── 4. Build Dashboard ───────────────────────────────────────────
info "Building dashboard..."
cd "$RMM_ROOT/dashboard"
npm run build --silent
mkdir -p /opt/neooptimize-rmm/dashboard
cp -r dist/. /opt/neooptimize-rmm/dashboard/
success "Dashboard built and deployed"

# ─── 5. Restart RMM Server ────────────────────────────────────────
info "Restarting RMM server..."
systemctl restart neooptimize-rmm 2>/dev/null || \
  (cd "$RMM_ROOT/server" && pm2 restart neooptimize-rmm 2>/dev/null || true)
success "RMM server restarted"

# ─── 6. Configure firewall ────────────────────────────────────────
info "Opening firewall ports..."
ufw allow 80/tcp   comment 'HTTP redirect'       2>/dev/null || true
ufw allow 443/tcp  comment 'HTTPS Dashboard'     2>/dev/null || true
ufw allow 8080/tcp comment 'Download server'     2>/dev/null || true
ufw allow 3000/tcp comment 'RMM API (internal)'  2>/dev/null || true
success "Firewall ports opened"

# ─── Done ─────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║            NeoOptimize RMM is LIVE!                  ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  🌐 Dashboard:    ${CYAN}https://$HOST_IP${NC}"
echo -e "  📡 API:          ${CYAN}https://$HOST_IP/api/v1${NC}"
echo -e "  📦 Downloads:    ${CYAN}http://$HOST_IP:8080${NC}"
echo -e "  🖥  Client Inst:  ${CYAN}http://$HOST_IP:8080/NeoOptimize-Client-Setup.exe${NC}"
echo ""
echo -e "  ${YELLOW}Note: Browser will show SSL warning (self-signed cert).${NC}"
echo -e "  ${YELLOW}To bypass: click 'Advanced' → 'Proceed'.${NC}"
echo ""
