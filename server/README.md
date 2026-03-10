# Zenith Account Server

The central authentication and device discovery service for the Zenith ecosystem. Manages user accounts, device registration, and coordinates multi-device inference.

## Features

- **User Authentication**: Email/password signup and login with JWT tokens
- **Device Registry**: Devices auto-register on sign-in, discoverable by other devices on same account
- **Secure API**: All endpoints require JWT authentication (except auth endpoints)
- **SQLite Database**: Persistent storage for users and devices
- **CORS Support**: Accessible from web and mobile clients
- **Production-Ready**: Environment-variable configuration, Docker support, systemd integration

## Quick Start

### Option 1: Docker (Recommended)

```bash
cd server
./setup.sh                # Generates JWT secret and .env file
docker-compose up -d
```

### Option 2: Direct (requires Dart SDK 3.0+)

```bash
cd server
dart pub get
./run-production.sh
```

### Option 3: Custom Port

```bash
docker-compose -f docker-compose.yml up -d -e ZENITH_PORT=8080
```

## Configuration

All server settings use environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ZENITH_HOST` | `0.0.0.0` | Server binding address |
| `ZENITH_PORT` | `3000` | Server port |
| `ZENITH_JWT_SECRET` | `zenith-super-secret...` | **MUST** set in production |
| `ZENITH_DB_PATH` | `zenith_accounts.db` | SQLite database path |

### Generate JWT Secret

```bash
openssl rand -base64 32
```

## API Endpoints

### Authentication

**POST /auth/signup**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```
Response: `{"email": "user@example.com", "token": "eyJ..."}`

**POST /auth/login**
```json
{
  "email": "user@example.com",
  "password": "password123"
}
```

### Device Management

**POST /devices/register**
- Requires: `Authorization: Bearer <token>`
- Body:
```json
{
  "deviceId": "zenith-1234567890",
  "deviceName": "My Laptop",
  "cpuCores": 8,
  "ramGb": 16,
  "modelId": "phi-3-mini"
}
```

**GET /devices/list**
- Requires: `Authorization: Bearer <token>`
- Returns: List of user's devices (active in last 5 minutes)

**POST /devices/update-endpoint**
- Requires: `Authorization: Bearer <token>`
- Body:
```json
{
  "deviceId": "zenith-1234567890",
  "endpoint": "http://192.168.1.100:8080"
}
```

### Health

**GET /health**
- No authentication required
- Response: `{"status":"ok"}`

## Testing

```bash
# Health check
curl http://localhost:3000/health

# Create account
curl -X POST http://localhost:3000/auth/signup \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Login
curl -X POST http://localhost:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"password123"}'

# Register device (with token from signup/login)
TOKEN="eyJ..."
curl -X POST http://localhost:3000/devices/register \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"test-1","deviceName":"Test","cpuCores":4,"ramGb":8}'
```

## Flutter Integration

Update `lib/main.dart` in the main app:

```dart
const String kAccountServerUrl = 'http://your-vm-ip:3000';
```

Or set via environment at build time:

```bash
flutter run --dart-define ZENITH_SERVER_URL=http://192.168.1.100:3000
```

## Deployment Guides

- **Docker**: See [DEPLOYMENT.md](./DEPLOYMENT.md) - Docker Compose section
- **Linux VM (systemd)**: See [DEPLOYMENT.md](./DEPLOYMENT.md) - Systemd Service section
- **Raw Dart**: See [DEPLOYMENT.md](./DEPLOYMENT.md) - Traditional Deployment section

## Database

The server uses SQLite for data persistence. Database file location is configurable via `ZENITH_DB_PATH`.

## Security Notes

- Passwords are hashed with SHA256 (production should add salt)
- JWT tokens expire after 30 days
- All device endpoints require valid JWT token
- Enable HTTPS in production (reverse proxy with nginx or caddy)
- Use strong `ZENITH_JWT_SECRET` (min 32 characters)
- Database should be backed up regularly

## Troubleshooting

**Server won't start**
- Check Dart is installed: `dart --version`
- Check port is available: `lsof -i :3000`
- Check logs in Docker: `docker-compose logs`

**"database is locked"**
- Close other connections to the database
- Check if another server instance is running

**JWT token errors**
- Verify `ZENITH_JWT_SECRET` matches between server and client
- Check token hasn't expired (30-day limit)

**CORS errors**
- Server supports all origins by default
- If behind reverse proxy, ensure CORS headers are passed through

## Files

- `bin/server.dart` - Main server code
- `pubspec.yaml` - Dart dependencies
- `Dockerfile` - Container image definition
- `docker-compose.yml` - Container orchestration
- `run-production.sh` - Production startup script
- `setup.sh` - Quick setup helper
- `.env.example` - Configuration template
- `DEPLOYMENT.md` - Detailed deployment guide

## Development

```bash
# Install dependencies
dart pub get

# Font code
dart format bin/

# Analyze
dart analyze

# Run server
dart run bin/server.dart
```

## Production Notes

- Use strong JWT secret (generated via `./setup.sh`)
- Enable HTTPS in production (reverse proxy or load balancer)
- Set up automated database backups
- Monitor server logs for errors
- For high traffic, consider scaling with multiple instances behind a load balancer
- Add device verification/pairing codes
- Deploy on VPS or cloud platform
