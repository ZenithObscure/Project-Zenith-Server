#!/bin/bash

# Zenith Account Server - Production Startup Script
# Usage: ./run-production.sh [OPTIONS]
#
# Environment variables:
#   ZENITH_HOST         - Server host (default: 0.0.0.0)
#   ZENITH_PORT         - Server port (default: 3000)
#   ZENITH_JWT_SECRET   - JWT signing secret (MUST set in production!)
#   ZENITH_DB_PATH      - Path to SQLite database (default: zenith_accounts.db)

set -e

# Change to script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Default values
ZENITH_HOST="${ZENITH_HOST:-0.0.0.0}"
ZENITH_PORT="${ZENITH_PORT:-3000}"
ZENITH_DB_PATH="${ZENITH_DB_PATH:-zenith_accounts.db}"

# Warn if using default JWT secret
if [ -z "$ZENITH_JWT_SECRET" ]; then
    echo "⚠️  WARNING: Using default JWT secret. Set ZENITH_JWT_SECRET environment variable in production!"
    ZENITH_JWT_SECRET="zenith-super-secret-key-change-in-production"
fi

# Create database directory if it doesn't exist
DB_DIR=$(dirname "$ZENITH_DB_PATH")
if [ "$DB_DIR" != "." ] && [ ! -d "$DB_DIR" ]; then
    mkdir -p "$DB_DIR"
    echo "📁 Created database directory: $DB_DIR"
fi

# Print configuration
echo "🚀 Starting Zenith Account Server"
echo "  Host: $ZENITH_HOST"
echo "  Port: $ZENITH_PORT"
echo "  Database: $ZENITH_DB_PATH"
echo ""

# Export environment variables and run server
export ZENITH_HOST
export ZENITH_PORT
export ZENITH_JWT_SECRET
export ZENITH_DB_PATH

dart run bin/server.dart
