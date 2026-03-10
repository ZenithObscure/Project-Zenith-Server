#!/bin/bash

# Zenith Account Server - Setup Helper
# This script helps generate secure configuration and deploy to a VM

set -e

echo "🚀 Zenith Account Server - Setup Helper"
echo ""

# 1. Generate JWT Secret
echo "1️⃣  Generate JWT Secret"
echo "------------------------"

JWT_SECRET=$(openssl rand -base64 32 2>/dev/null || echo "error")

if [ "$JWT_SECRET" = "error" ]; then
    echo "⚠️  openssl not found. Install it or generate a secret manually."
    JWT_SECRET="change-me-$(date +%s)"
else
    echo "Generated JWT Secret:"
    echo "  $JWT_SECRET"
    echo ""
fi

# 2. Create .env file
echo "2️⃣  Create .env configuration"
echo "------------------------------"

if [ -f ".env" ]; then
    echo "ℹ️  .env already exists. Skipping..."
else
    cp .env.example .env
    # Use | as delimiter to avoid issues with / in base64 strings
    sed -i "s|ZENITH_JWT_SECRET=.*|ZENITH_JWT_SECRET=$JWT_SECRET|" .env
    echo "✅ Created .env with generated secret"
fi

echo ""

# 3. Show deployment options
echo "3️⃣  Deployment Options"
echo "---------------------"
echo ""
echo "Option A: Docker (Recommended)"
echo "  docker-compose up -d"
echo ""
echo "Option B: Direct (requires Dart SDK)"
echo "  dart pub get"
echo "  ./run-production.sh"
echo ""
echo "Option C: Systemd Service (Linux)"
echo "  See DEPLOYMENT.md for instructions"
echo ""

# 4. Show testing
echo "4️⃣  Test the server"
echo "-------------------"
echo ""
echo "Health check:"
echo "  curl http://localhost:3000/health"
echo ""
echo "Create account:"
echo "  curl -X POST http://localhost:3000/auth/signup \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"email\":\"test@example.com\",\"password\":\"password123\"}'"
echo ""

# 5. VM deployment info
echo "5️⃣  Deploying to VM"
echo "-------------------"
echo ""
echo "Steps:"
echo "  1. Set up VM (Ubuntu 22.04 recommended)"
echo "  2. Install Docker: apt-get install docker.io docker-compose"
echo "  3. Copy server directory to VM"
echo "  4. Update .env with ZENITH_JWT_SECRET (use generated secret above)"
echo "  5. Run: docker-compose up -d"
echo ""
echo "Configuration for Flutter app (lib/main.dart):"
echo "  const String kAccountServerUrl = 'http://YOUR-VM-IP:3000';"
echo ""

echo "✅ Setup complete!"
echo ""
echo "📖 For more details, see DEPLOYMENT.md"
