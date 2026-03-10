#!/usr/bin/env bash
set -euo pipefail

# Clone Zenith server code from GitHub and run systemd bootstrap on a DigitalOcean droplet.
#
# Usage examples:
#   sudo bash install-from-github.sh --repo owner/repo --branch main --no-tls
#   sudo bash install-from-github.sh --repo https://github.com/owner/repo.git --domain api.example.com --email you@example.com
#
# Notes:
# - Supports server code at repo root OR repo path: server/
# - This script clones repo to /opt/zenith-src and syncs /opt/zenith-server
# - Uses systemd service instead of Docker

REPO=""
BRANCH="main"
DOMAIN=""
EMAIL=""
NO_TLS="false"
SRC_DIR="/opt/zenith-src"
APP_DIR="/opt/zenith-server"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      REPO="$2"
      shift 2
      ;;
    --branch)
      BRANCH="$2"
      shift 2
      ;;
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --email)
      EMAIL="$2"
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

if [[ -z "$REPO" ]]; then
  echo "Usage: sudo bash install-from-github.sh --repo owner/repo [--branch main] [--no-tls | --domain ... --email ...]"
  exit 1
fi

if [[ "$NO_TLS" != "true" && ( -z "$DOMAIN" || -z "$EMAIL" ) ]]; then
  echo "Provide either --no-tls or both --domain and --email"
  exit 1
fi

if [[ "$REPO" != https://* && "$REPO" != git@* ]]; then
  REPO="https://github.com/$REPO.git"
fi

echo "[1/5] Install git + rsync"
apt-get update -y
apt-get install -y git rsync

echo "[2/5] Clone repository"
rm -rf "$SRC_DIR"
git clone --depth 1 --branch "$BRANCH" "$REPO" "$SRC_DIR"

SERVER_SRC_DIR=""
if [[ -f "$SRC_DIR/pubspec.yaml" ]]; then
  SERVER_SRC_DIR="$SRC_DIR"
elif [[ -f "$SRC_DIR/server/pubspec.yaml" ]]; then
  SERVER_SRC_DIR="$SRC_DIR/server"
else
  echo "Could not find pubspec.yaml in repo root or server/ subdirectory."
  exit 1
fi

echo "[3/5] Sync server files"
mkdir -p "$APP_DIR"
rsync -az --delete "$SERVER_SRC_DIR/" "$APP_DIR/"

if [[ ! -x "$APP_DIR/deploy/digitalocean-systemd-bootstrap.sh" ]]; then
  chmod +x "$APP_DIR/deploy/digitalocean-systemd-bootstrap.sh"
fi

echo "[4/5] Run bootstrap"
cd "$APP_DIR"
if [[ "$NO_TLS" == "true" ]]; then
  bash deploy/digitalocean-systemd-bootstrap.sh --no-tls
else
  bash deploy/digitalocean-systemd-bootstrap.sh --domain "$DOMAIN" --email "$EMAIL"
fi

echo "[5/5] Done"
printf '%s\n' "Deployment completed from GitHub repository: $REPO"
