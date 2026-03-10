# Zenith Account Server
# Build: docker build -t zenith-account-server .
# Run: docker run -p 3000:3000 -e ZENITH_JWT_SECRET=your-secret zenith-account-server

FROM google/dart:latest

WORKDIR /app

# Copy pubspec files
COPY pubspec.yaml pubspec.lock* ./

# Get dependencies
RUN dart pub get

# Copy server code
COPY bin/ bin/

# Expose server port
EXPOSE 3000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD dart run bin/health_check.dart || exit 1

# Run server
CMD ["dart", "run", "bin/server.dart"]
