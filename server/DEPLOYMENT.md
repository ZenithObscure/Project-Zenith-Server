# Zenith Account Server - Deployment Guide

This guide covers deploying the Zenith Account Server to a VM or production environment.

## DigitalOcean One-Command Bootstrap

For DigitalOcean droplets, use the ready-made deployment bundle:
- `deploy/digitalocean-bootstrap.sh`
- `deploy/README_DIGITALOCEAN.md`

Quick usage on droplet:

```bash
cd /opt/zenith-server
chmod +x deploy/digitalocean-bootstrap.sh
sudo bash deploy/digitalocean-bootstrap.sh --domain api.yourdomain.com --email you@yourdomain.com
```

This configures Docker, UFW, fail2ban, Nginx reverse proxy, and Let's Encrypt HTTPS.

## Quick Start (Docker - Recommended)

### Prerequisites
- Docker and Docker Compose installed
- Port 3000 available (or configure with ZENITH_PORT)

### Deployment

```bash
# Clone or copy the server directory to your VM
cd /path/to/server

# Set a strong JWT secret (IMPORTANT!)
export ZENITH_JWT_SECRET="your-super-secret-key-min-32-chars-recommended"

# Start the server
docker-compose up -d

# Check status
docker-compose logs -f

# Stop the server
docker-compose down
```

### Using Custom Port

```bash
ZENITH_PORT=8080 docker-compose up -d
```

### Persistent Database

The default `docker-compose.yml` stores the SQLite database in `./data/zenith_accounts.db`. This directory is mounted as a volume and persists across restarts.

---

## Traditional Deployment (No Docker)

### Prerequisites
- Dart SDK 3.0.0 or later
- Linux/macOS/Windows

### Setup

```bash
cd /path/to/server

# Install dependencies
dart pub get

# Set environment variables (optional - uses defaults if not set)
export ZENITH_HOST=0.0.0.0
export ZENITH_PORT=3000
export ZENITH_JWT_SECRET="your-super-secret-key"
export ZENITH_DB_PATH=/var/lib/zenith/accounts.db

# Run the server
./run-production.sh
```

---

## Systemd Service (Linux)

For persistent service management on Linux VMs, create a systemd service:

### 1. Create service file

```bash
sudo nano /etc/systemd/system/zenith-account-server.service
```

Paste this content:

```ini
[Unit]
Description=Zenith Account Server
After=network.target

[Service]
Type=simple
User=zenith
WorkingDirectory=/opt/zenith-server
ExecStart=/opt/zenith-server/run-production.sh
Restart=on-failure
RestartSec=10

Environment="ZENITH_HOST=0.0.0.0"
Environment="ZENITH_PORT=3000"
Environment="ZENITH_JWT_SECRET=your-super-secret-key"
Environment="ZENITH_DB_PATH=/var/lib/zenith/accounts.db"

[Install]
WantedBy=multi-user.target
```

### 2. Enable and start service

```bash
# Create user and directories
sudo useradd -m -s /bin/bash zenith
sudo mkdir -p /opt/zenith-server /var/lib/zenith
sudo chown zenith:zenith /opt/zenith-server /var/lib/zenith

# Copy server code
sudo cp -r . /opt/zenith-server/
sudo chown -R zenith:zenith /opt/zenith-server

# Enable service
sudo systemctl daemon-reload
sudo systemctl enable zenith-account-server
sudo systemctl start zenith-account-server

# Check status
sudo systemctl status zenith-account-server

# View logs
sudo journalctl -u zenith-account-server -f
```

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ZENITH_HOST` | `0.0.0.0` | Server binding address |
| `ZENITH_PORT` | `3000` | Server port |
| `ZENITH_JWT_SECRET` | (unsafe default) | JWT signing secret - **MUST SET IN PRODUCTION** |
| `ZENITH_DB_PATH` | `zenith_accounts.db` | SQLite database file path |

### Security Notes

- **JWT Secret**: Generate a strong secret with `openssl rand -base64 32`
- **Database Path**: Use `/var/lib/zenith/accounts.db` on production VMs
- **Host**: Use `127.0.0.1` if behind a reverse proxy, `0.0.0.0` for direct internet access
- **Firewall**: Open only port 3000 (or configured port) to trusted networks

---

## Health Checks

Check if the server is running:

```bash
curl http://localhost:3000/health
# Response: {"status":"ok"}
```

---

## Database Backups

The SQLite database can be backed up while the server is running:

```bash
# Backup
cp /var/lib/zenith/accounts.db /backups/zenith_accounts_$(date +%Y%m%d_%H%M%S).db

# Or with automated cron job
0 2 * * * cp /var/lib/zenith/accounts.db /backups/zenith_accounts_$(date +\%Y\%m\%d_\%H\%M\%S).db
```

---

## Connecting Flutter App to Remote Server

Update the `kAccountServerUrl` in your Flutter app's `lib/main.dart`:

```dart
const String kAccountServerUrl = 'http://your-vm-ip:3000';
```

Or make it configurable via a settings screen.

---

## Testing for Deployment

```bash
# Create account
curl -X POST http://your-vm:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Expected response:
# {"email":"test@example.com","token":"eyJ..."}
```

---

## Troubleshooting

### Server won't start
- Check Dart is installed: `dart --version`
- Check port is available: `lsof -i :3000`
- Check permissions: Database directory must be writable

### Database errors
- Ensure database directory exists and is writable
- Check disk space: `df -h`
- View recent errors: `tail -f /var/log/zenith-account-server.log`

### Connection refused
- Check firewall: `ufw status`
- Allow port: `sudo ufw allow 3000`
- Verify server is listening: `netstat -tlnp | grep 3000`

---

## Production Checklist

- [ ] Generated strong JWT secret (`openssl rand -base64 32`)
- [ ] Set environment variables in systemd service or docker-compose
- [ ] Database directory exists and has proper permissions
- [ ] Firewall configured to allow server port
- [ ] Backups configured for SQLite database
- [ ] Health checks configured and working
- [ ] Flutter app updated with server URL
- [ ] Test account creation and device registration
- [ ] Monitor logs for errors

---

## Updating the Server

```bash
# Pull latest code
git pull origin main

# Rebuild Docker image
docker-compose build --no-cache

# Restart service
docker-compose restart

# Or for systemd:
sudo systemctl restart zenith-account-server
```

---

## Support

For issues, check:
- Server logs for error messages
- `/var/lib/zenith/accounts.db` exists and is readable
- Network connectivity to VM from client devices
- JWT secret is set correctly

