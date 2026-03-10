#!/bin/bash
# Zenith Account Server - DigitalOcean Systemd Bootstrap
# For Ubuntu 22.04+ droplets
#
# Usage:
#   sudo bash digitalocean-systemd-bootstrap.sh [--no-tls | --domain example.com --email admin@example.com]
#
# IP-only deployment (HTTP on port 3000):
#   sudo bash digitalocean-systemd-bootstrap.sh --no-tls
#
# Domain deployment (HTTPS with Let's Encrypt):
#   sudo bash digitalocean-systemd-bootstrap.sh --domain api.example.com --email admin@example.com

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVER_DIR="/opt/zenith-server"
DATA_DIR="/var/lib/zenith"
SERVICE_USER="zenith"

TLS_MODE="none"
DOMAIN=""
EMAIL=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --no-tls)
      TLS_MODE="none"
      shift
      ;;
    --domain)
      DOMAIN="$2"
      TLS_MODE="tls"
      shift 2
      ;;
    --email)
      EMAIL="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--no-tls | --domain DOMAIN --email EMAIL]"
      exit 1
      ;;
  esac
done

if [[ "$TLS_MODE" == "tls" ]] && [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "Error: --domain and --email required for TLS mode"
  exit 1
fi

echo "[1/8] Install base packages"
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release ufw fail2ban unattended-upgrades nginx jq

echo "[2/8] Install Dart SDK"
# Add Dart APT repository
apt-get install -y apt-transport-https
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/dart.gpg
echo 'deb [signed-by=/usr/share/keyrings/dart.gpg arch=amd64] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main' | tee /etc/apt/sources.list.d/dart_stable.list
apt-get update
apt-get install -y dart

echo "[3/8] Configure firewall"
ufw --force default deny incoming
ufw --force default allow outgoing
ufw allow 22/tcp
if [[ "$TLS_MODE" == "none" ]]; then
  ufw allow 3000/tcp
else
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
ufw --force enable

echo "[4/8] Enable basic host hardening"
systemctl enable fail2ban
systemctl start fail2ban
systemctl enable unattended-upgrades
systemctl start unattended-upgrades

echo "[5/8] Create service user and directories"
if ! id "$SERVICE_USER" &>/dev/null; then
  useradd --system --no-create-home --shell /bin/false "$SERVICE_USER"
fi
mkdir -p "$DATA_DIR"
mkdir -p "$DATA_DIR/.config"
mkdir -p "$DATA_DIR/.pub-cache"
chown "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR"
chown -R "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR/.config" "$DATA_DIR/.pub-cache"
chown -R "$SERVICE_USER:$SERVICE_USER" "$SERVER_DIR"

echo "[6/8] Install dependencies"
cd "$SERVER_DIR"
sudo -u "$SERVICE_USER" \
  HOME="$DATA_DIR" \
  XDG_CONFIG_HOME="$DATA_DIR/.config" \
  PUB_CACHE="$DATA_DIR/.pub-cache" \
  DART_SUPPRESS_ANALYTICS=true \
  /usr/lib/dart/bin/dart pub get

echo "[7/8] Configure environment"
if [[ ! -f "$SERVER_DIR/.env" ]]; then
  JWT_SECRET=$(openssl rand -base64 32)
  DB_PATH="$DATA_DIR/accounts.db"
  
  cat > "$SERVER_DIR/.env" <<EOF
ZENITH_HOST=0.0.0.0
ZENITH_PORT=3000
ZENITH_JWT_SECRET=$JWT_SECRET
ZENITH_DB_PATH=$DB_PATH
EOF
  
  echo "✓ Created .env with generated JWT secret"
else
  echo "✓ Using existing .env"
fi

echo "[8/8] Install and start systemd service"
cp "$SCRIPT_DIR/zenith-server.service" /etc/systemd/system/
systemctl daemon-reload
systemctl enable zenith-server
systemctl restart zenith-server

# Wait for server to start
sleep 3

# Verify service is running
if systemctl is-active --quiet zenith-server; then
  echo "✓ Zenith server is running"
else
  echo "✗ Service failed to start"
  journalctl -u zenith-server -n 20
  exit 1
fi

if [[ "$TLS_MODE" == "tls" ]]; then
  echo "[TLS] Configure Nginx reverse proxy"
  cat > /etc/nginx/sites-available/zenith <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }
    
    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;
    
    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    
    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

  ln -sf /etc/nginx/sites-available/zenith /etc/nginx/sites-enabled/
  nginx -t
  
  echo "[TLS] Install Certbot"
  apt-get install -y certbot python3-certbot-nginx
  
  echo "[TLS] Obtain Let's Encrypt certificate"
  certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive
  
  systemctl reload nginx
  
  echo ""
  echo "=========================================="
  echo "✓ Deployment complete with HTTPS!"
  echo "=========================================="
  echo ""
  echo "Test with: curl https://$DOMAIN/health"
  echo ""
  echo "Service management:"
  echo "  sudo systemctl status zenith-server"
  echo "  sudo systemctl restart zenith-server"
  echo "  sudo journalctl -u zenith-server -f"
else
  echo ""
  echo "=========================================="
  echo "✓ Deployment complete!"
  echo "=========================================="
  echo ""
  SERVER_IP=$(curl -s ifconfig.me)
  echo "Test with: curl http://$SERVER_IP:3000/health"
  echo ""
  echo "Service management:"
  echo "  sudo systemctl status zenith-server"
  echo "  sudo systemctl restart zenith-server"
  echo "  sudo journalctl -u zenith-server -f"
  echo ""
  echo "Configure app with server URL: http://$SERVER_IP:3000"
fi
