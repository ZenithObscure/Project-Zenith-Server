# DigitalOcean Deployment (Recommended)

Use this guide to deploy Zenith Account Server on a fresh Ubuntu droplet.

This deployment supports two modes:
- `--no-tls` for IP-only deployment (no domain required)
- `--domain ... --email ...` for HTTPS deployment with Let's Encrypt

## 1. Create Droplet

- Ubuntu 22.04 LTS
- Size: Basic 1 vCPU / 1-2 GB RAM
- Auth: SSH key (recommended)
- Add domain A record to droplet IP (e.g. `api.yourdomain.com`)

## 2. Deploy Method

Choose one:

### Method A: Copy local files (rsync)

From your local machine:

```bash
rsync -az --delete server/ root@YOUR_DROPLET_IP:/opt/zenith-server/
```

### Method B: Clone from GitHub on droplet (easier updates)

SSH into droplet and run:

```bash
ssh root@YOUR_DROPLET_IP
mkdir -p /opt/zenith-server
```

Then run installer (replace `owner/repo`):

```bash
cd /opt
curl -fsSL https://raw.githubusercontent.com/owner/repo/main/server/deploy/install-from-github.sh -o install-from-github.sh
chmod +x install-from-github.sh

# IP-only mode (no domain)
sudo bash install-from-github.sh --repo owner/repo --branch main --no-tls
```

Or for HTTPS mode:

```bash
sudo bash install-from-github.sh \
  --repo owner/repo \
  --branch main \
  --domain api.yourdomain.com \
  --email you@yourdomain.com
```

## 3. Run Bootstrap Script

SSH into droplet:

```bash
ssh root@YOUR_DROPLET_IP
cd /opt/zenith-server
chmod +x deploy/digitalocean-bootstrap.sh
sudo bash deploy/digitalocean-bootstrap.sh \
  --domain api.yourdomain.com \
  --email you@yourdomain.com
```

If you do not have a domain yet, use IP-only mode:

```bash
sudo bash deploy/digitalocean-bootstrap.sh --no-tls
```

What this script does:
- Installs Docker + Compose
- Enables UFW (ports 22/80/443 for TLS mode, or 22/3000 for no-TLS mode)
- Enables fail2ban + unattended-upgrades
- Generates `.env` with strong JWT secret if missing
- Starts server via Docker Compose
- Configures Nginx reverse proxy (TLS mode)
- Issues Let's Encrypt certificate and redirects HTTP -> HTTPS (TLS mode)

## 4. Verify

TLS mode:

```bash
curl https://api.yourdomain.com/health
# {"status":"ok"}
```

No-TLS mode:

```bash
curl http://YOUR_DROPLET_IP:3000/health
# {"status":"ok"}
```

## 5. Connect App

In Zenith sign-in screen:
- TLS mode: `Account server URL`: `https://api.yourdomain.com`
- No-TLS mode: `Account server URL`: `http://YOUR_DROPLET_IP:3000`

## Operations

```bash
# logs
cd /opt/zenith-server
docker compose logs -f

# restart
cd /opt/zenith-server
docker compose restart

# update deployment
cd /opt/zenith-server
git pull   # if using git
# or re-rsync from local machine

docker compose up -d --build
```

## Backups

Database path in container is persisted to host:
- Host path: `/opt/zenith-server/data/zenith_accounts.db`

Example daily backup cron:

```bash
sudo mkdir -p /var/backups/zenith
sudo crontab -e
# Add:
# 0 2 * * * cp /opt/zenith-server/data/zenith_accounts.db /var/backups/zenith/zenith_accounts_$(date +\%Y\%m\%d_\%H\%M\%S).db
```

## Notes

- Keep `ZENITH_JWT_SECRET` private and never commit `.env`.
- If certbot fails, confirm DNS has propagated and port 80 is reachable.
- If you change domain, re-run certbot with the new domain.
- No-TLS mode is fine for temporary setup; move to HTTPS once domain is ready.
