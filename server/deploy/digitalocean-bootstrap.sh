#!/usr/bin/env bash
set -euo pipefail

# Zenith Account Server bootstrap for Ubuntu 22.04+ on DigitalOcean.
# Run as root or with sudo.
# Usage:
#   sudo bash deploy/digitalocean-bootstrap.sh --domain api.example.com --email you@example.com
#   sudo bash deploy/digitalocean-bootstrap.sh --no-tls

DOMAIN=""
EMAIL=""
APP_DIR="/opt/zenith-server"
SSH_PORT="22"
NO_TLS="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      EMAIL="$2"
      shift 2
      ;;
    --app-dir)
      APP_DIR="$2"
      shift 2
      ;;
    --ssh-port)
      SSH_PORT="$2"
      shift 2
      ;;
    --no-tls)
      NO_TLS="true"
      shift 1
      ;;
    *)
      echo "Unknown arg: $1"
      exit 1
      ;;
  esac
done

if [[ "$NO_TLS" != "true" && ( -z "$DOMAIN" || -z "$EMAIL" ) ]]; then
  echo "Usage: sudo bash deploy/digitalocean-bootstrap.sh --domain api.example.com --email you@example.com"
  echo "   or: sudo bash deploy/digitalocean-bootstrap.sh --no-tls"
  exit 1
fi

echo "[1/9] Install base packages"
apt-get update -y
apt-get install -y ca-certificates curl gnupg lsb-release ufw fail2ban unattended-upgrades nginx jq

echo "[2/9] Install Docker Engine + Compose plugin"
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker

echo "[3/9] Configure firewall"
ufw default deny incoming
ufw default allow outgoing
ufw allow "$SSH_PORT"/tcp
if [[ "$NO_TLS" == "true" ]]; then
  ufw allow 3000/tcp
else
  ufw allow 80/tcp
  ufw allow 443/tcp
fi
ufw --force enable

echo "[4/9] Enable basic host hardening services"
systemctl enable --now fail2ban
systemctl enable --now unattended-upgrades

echo "[5/9] Prepare app directory"
mkdir -p "$APP_DIR"
mkdir -p "$APP_DIR/data"

if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
  cat <<EOF
App files not found at $APP_DIR.
Copy your server files there first, e.g.:
  rsync -az server/ root@<droplet-ip>:$APP_DIR/
Then re-run this script.
EOF
  exit 1
fi

echo "[6/9] Create production .env if missing"
if [[ ! -f "$APP_DIR/.env" ]]; then
  JWT_SECRET=$(openssl rand -base64 48)
  cat > "$APP_DIR/.env" <<EOF
ZENITH_HOST=0.0.0.0
ZENITH_PORT=3000
ZENITH_JWT_SECRET=$JWT_SECRET
ZENITH_DB_PATH=/app/data/zenith_accounts.db
EOF
fi

echo "[7/9] Launch Zenith account server with Docker"
cd "$APP_DIR"
docker compose up -d --build

echo "[8/9] Configure Nginx reverse proxy"
if [[ "$NO_TLS" == "true" ]]; then
  echo "[8/9] Skipping Nginx + TLS (--no-tls mode)"
  echo "[9/9] Server exposed directly on port 3000"
else
  cat > /etc/nginx/sites-available/zenith-account-server <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  ln -sf /etc/nginx/sites-available/zenith-account-server /etc/nginx/sites-enabled/zenith-account-server
  rm -f /etc/nginx/sites-enabled/default
  nginx -t
  systemctl reload nginx

  echo "[9/9] Install certbot and issue TLS certificate"
  apt-get install -y certbot python3-certbot-nginx
  certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect
fi

echo
printf '%s\n' "Bootstrap complete."
if [[ "$NO_TLS" == "true" ]]; then
  SERVER_IP=$(curl -s http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address || true)
  if [[ -z "$SERVER_IP" ]]; then
    printf '%s\n' "Health check: http://<droplet-ip>:3000/health"
    printf '%s\n' "App URL for Zenith sign-in: http://<droplet-ip>:3000"
  else
    printf '%s\n' "Health check: http://$SERVER_IP:3000/health"
    printf '%s\n' "App URL for Zenith sign-in: http://$SERVER_IP:3000"
  fi
else
  printf '%s\n' "Health check: https://$DOMAIN/health"
  printf '%s\n' "App URL for Zenith sign-in: https://$DOMAIN"
fi
printf '%s\n' "Docker logs:  cd $APP_DIR && docker compose logs -f"
