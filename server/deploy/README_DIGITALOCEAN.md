# DigitalOcean Deployment (Recommended)

Use this guide to deploy Zenith Account Server on a fresh Ubuntu droplet.

This deployment uses systemd (not Docker) for simplicity. It supports two modes:
- `--no-tls` for IP-only deployment (no domain required)
- `--domain ... --email ...` for HTTPS deployment with Let's Encrypt

## 1. Create Droplet

- Ubuntu 22.04+ LTS
- Size: Basic 1 vCPU / 512 MB RAM (minimum)
- Auth: SSH key (recommended)
- Add domain A record to droplet IP (e.g. `api.yourdomain.com`) if using TLS mode

## 2. Deploy from GitHub (Recommended)

SSH into droplet and run the one-command installer:

```bash
ssh root@YOUR_DROPLET_IP
cd /opt
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/server/deploy/install-from-github.sh -o install-from-github.sh
chmod +x install-from-github.sh
```

**IP-only mode (no domain required):**

```bash
sudo bash install-from-github.sh --repo YOUR_GITHUB_USER/YOUR_REPO --branch main --no-tls
```

**HTTPS mode (requires domain):**

```bash
sudo bash install-from-github.sh \
  --repo YOUR_GITHUB_USER/YOUR_REPO \
  --branch main \
  --domain api.yourdomain.com \
  --email you@yourdomain.com
```

What this does:
- Installs Dart SDK via apt
- Clones your repository
- Runs `dart pub get`
- Generates `.env` with strong JWT secret
- Creates systemd service
- Configures UFW firewall
- Enables fail2ban + unattended-upgrades
- Sets up Nginx + Let's Encrypt (HTTPS mode only)

## 3. Verify Deployment

**No-TLS mode:**
```bash
curl http://YOUR_DROPLET_IP:3000/health
# {"status":"ok"}
```

**TLS mode:**
```bash
curl https://api.yourdomain.com/health
# {"status":"ok"}
```

## 4. Connect Your App

In Zenith sign-in screen:
- **No-TLS mode**: `http://YOUR_DROPLET_IP:3000`
- **TLS mode**: `https://api.yourdomain.com`

## Operations

**Check service status:**
```bash
sudo systemctl status zenith-server
```

**View logs:**
```bash
sudo journalctl -u zenith-server -f
# Or last 50 lines:
sudo journalctl -u zenith-server -n 50
```

**Restart service:**
```bash
sudo systemctl restart zenith-server
```

**Update deployment:**
```bash
cd /opt/zenith-server
git pull  # if you're tracking a git repo
dart pub get
sudo systemctl restart zenith-server
```

## Backups

Database location: `/var/lib/zenith/accounts.db`

Example daily backup cron:

```bash
sudo mkdir -p /var/backups/zenith
sudo crontab -e
```

Add this line:
```
0 2 * * * cp /var/lib/zenith/accounts.db /var/backups/zenith/accounts_$(date +\%Y\%m\%d).db
```

## Notes

- Keep `ZENITH_JWT_SECRET` in `.env` private and never commit it
- If certbot fails, confirm DNS has propagated and port 80 is reachable
- systemd service runs as user `zenith` for security
- No Docker overhead - just a native Dart process
- Service auto-restarts on failure (RestartSec=10)
