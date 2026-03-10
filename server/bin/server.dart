import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:sqlite3/sqlite3.dart';

// Configuration from environment variables
final String _host = Platform.environment['ZENITH_HOST'] ?? '0.0.0.0';
final int _port =
    int.tryParse(Platform.environment['ZENITH_PORT'] ?? '3000') ?? 3000;
final String _jwtSecret = Platform.environment['ZENITH_JWT_SECRET'] ??
    'zenith-super-secret-key-change-in-production';
final String _dbPath =
    Platform.environment['ZENITH_DB_PATH'] ?? 'zenith_accounts.db';
late Database _db;

void main() async {
  // Initialize database
  _initializeDatabase();

  final router = Router();

  // Health check endpoint
  router.get('/health', (Request request) {
    return Response.ok(jsonEncode({'status': 'ok'}),
        headers: {'Content-Type': 'application/json'});
  });

  // User signup
  router.post('/auth/signup', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || password == null || password.length < 6) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Email and password (6+ chars) required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check if user exists
      final existingUser = _db.prepare('SELECT id FROM users WHERE email = ?');
      final result = existingUser.select([email]);
      existingUser.dispose();

      if (result.isNotEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'User already exists'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Hash password with SHA256 (simple implementation)
      final passwordHash = sha256.convert(password.codeUnits).toString();

      // Create user
      final stmt = _db.prepare(
        'INSERT INTO users (email, password_hash, created_at) VALUES (?, ?, ?)',
      );
      stmt.execute([email, passwordHash, DateTime.now().toIso8601String()]);
      stmt.dispose();

      // Generate JWT token
      final token = _generateToken(email);

      return Response.ok(
        jsonEncode({
          'email': email,
          'token': token,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  });

  // User login
  router.post('/auth/login', (Request request) async {
    try {
      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final email = data['email'] as String?;
      final password = data['password'] as String?;

      if (email == null || password == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Email and password required'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Check user
      final stmt =
          _db.prepare('SELECT password_hash FROM users WHERE email = ?');
      final result = stmt.select([email]);
      stmt.dispose();

      if (result.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      final passwordHash = result.first['password_hash'] as String;
      final inputHash = sha256.convert(password.codeUnits).toString();

      if (passwordHash != inputHash) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid credentials'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Generate JWT token
      final token = _generateToken(email);

      return Response.ok(
        jsonEncode({
          'email': email,
          'token': token,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  });

  // Register a device
  router.post('/devices/register', (Request request) async {
    try {
      final token = _extractToken(request);
      if (token == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Missing auth token'}),
        );
      }

      final email = _verifyToken(token);
      if (email == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Invalid token'}),
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['deviceId'] as String?;
      final deviceName = data['deviceName'] as String?;
      final cpuCores = data['cpuCores'] as int?;
      final ramGb = data['ramGb'] as int?;
      final modelId = data['modelId'] as String?;

      if (deviceId == null || deviceName == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Upsert device
      final stmt = _db.prepare('''
        INSERT OR REPLACE INTO devices (user_id, device_id, device_name, cpu_cores, ram_gb, model_id, last_seen)
        SELECT id, ?, ?, ?, ?, ?, ? FROM users WHERE email = ?
      ''');
      stmt.execute([
        deviceId,
        deviceName,
        cpuCores ?? 0,
        ramGb ?? 0,
        modelId,
        DateTime.now().toIso8601String(),
        email,
      ]);
      stmt.dispose();

      return Response.ok(
        jsonEncode({'status': 'registered'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  });

  // List devices for a user
  router.get('/devices/list', (Request request) async {
    try {
      final token = _extractToken(request);
      if (token == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Missing auth token'}),
        );
      }

      final email = _verifyToken(token);
      if (email == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Invalid token'}),
        );
      }

      // Get devices for this user
      final stmt = _db.prepare('''
        SELECT device_id, device_name, cpu_cores, ram_gb, model_id, endpoint, last_seen
        FROM devices
        WHERE user_id = (SELECT id FROM users WHERE email = ?)
        AND datetime(last_seen) > datetime('now', '-5 minutes')
        ORDER BY last_seen DESC
      ''');
      final results = stmt.select([email]);
      stmt.dispose();

      final devices = results.map((row) {
        return {
          'deviceId': row['device_id'],
          'deviceName': row['device_name'],
          'cpuCores': row['cpu_cores'],
          'ramGb': row['ram_gb'],
          'modelId': row['model_id'],
          'endpoint': row['endpoint'],
          'lastSeen': row['last_seen'],
        };
      }).toList();

      return Response.ok(
        jsonEncode({'devices': devices}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  });

  // Update device endpoint
  router.post('/devices/update-endpoint', (Request request) async {
    try {
      final token = _extractToken(request);
      if (token == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Missing auth token'}),
        );
      }

      final email = _verifyToken(token);
      if (email == null) {
        return Response.unauthorized(
          jsonEncode({'error': 'Invalid token'}),
        );
      }

      final body = await request.readAsString();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceId = data['deviceId'] as String?;
      final endpoint = data['endpoint'] as String?;

      if (deviceId == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing deviceId'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Update device endpoint
      final stmt = _db.prepare('''
        UPDATE devices
        SET endpoint = ?, last_seen = ?
        WHERE device_id = ? AND user_id = (SELECT id FROM users WHERE email = ?)
      ''');
      stmt.execute([
        endpoint,
        DateTime.now().toIso8601String(),
        deviceId,
        email,
      ]);
      stmt.dispose();

      return Response.ok(
        jsonEncode({'status': 'updated'}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
      );
    }
  });

  final app = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(_corsMiddleware())
      .addHandler(router.call);

  final server = await shelf_io.serve(app, _host, _port);
  print(
      'Zenith Account Server running on http://${server.address.host}:${server.port}');
  print('Database: $_dbPath');
}

void _initializeDatabase() {
  try {
    _db = sqlite3.open(_dbPath);

    // Create users table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        email TEXT UNIQUE NOT NULL,
        password_hash TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // Create devices table
    _db.execute('''
      CREATE TABLE IF NOT EXISTS devices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        device_name TEXT NOT NULL,
        cpu_cores INTEGER DEFAULT 0,
        ram_gb INTEGER DEFAULT 0,
        model_id TEXT,
        endpoint TEXT,
        last_seen TEXT NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
        UNIQUE(user_id, device_id)
      )
    ''');

    print('Database initialized successfully');
  } catch (e) {
    print('Error initializing database: \$e');
    rethrow;
  }
}

String _generateToken(String email) {
  final jwt = JWT({
    'email': email,
    'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'exp':
        (DateTime.now().add(Duration(days: 30)).millisecondsSinceEpoch ~/ 1000),
  });
  return jwt.sign(SecretKey(_jwtSecret));
}

String? _verifyToken(String token) {
  try {
    final jwt = JWT.verify(token, SecretKey(_jwtSecret));
    return jwt.payload['email'] as String?;
  } catch (e) {
    return null;
  }
}

String? _extractToken(Request request) {
  final authHeader = request.headers['authorization'];
  if (authHeader == null) return null;
  if (!authHeader.startsWith('Bearer ')) return null;
  return authHeader.substring(7);
}

Middleware _corsMiddleware() {
  return (innerHandler) {
    return (request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, Authorization',
        });
      }

      final response = await innerHandler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
    };
  };
}
