import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:crypto/crypto.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

final jwtSecret = Platform.environment['JWT_SECRET'] ?? 
    'yGCUZ7LWl7j-P_ahUlSWoB69bvAZoJVIuu7bTMLik3A=';  
// Add this function
String generateToken(int userId) {
  final jwt = JWT(
    {
      'id': userId,
      'iat': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    },
  );
  return jwt.sign(SecretKey(jwtSecret));
}

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

late final Handler handler;

Future<HttpServer> createServer() async {
  final preferredPorts = [8080, 8081, 8082, 3000, 3001];
  
  for (final port in preferredPorts) {
    try {
      final server = await serve(
        handler, 
        InternetAddress.anyIPv4, 
        port
      );
      print('Server running on http://${server.address.host}:${server.port}');
      return server;
    } catch (e) {
      print('Port $port is in use, trying next port...');
      continue;
    }
  }
  throw 'Unable to start server on any of the preferred ports';
}

Future<void> main() async {
  PostgreSQLConnection db;

  try {
    db = await DatabaseHelper.connect();
    print('Connected to database successfully using configuration from pubspec.yaml');
  } catch (e) {
    print('Failed to connect to the database: $e');
    exit(1);
  }

  final router = Router();

  router.get('/', (Request req) async {
  return Response.ok('Mipripity API is running');
  });
  
  // Helper to convert DateTime fields to string
  Map<String, dynamic> _convertDateTimes(Map<String, dynamic> map) {
    final result = <String, dynamic>{};
    map.forEach((key, value) {
      if (value is DateTime) {
        result[key] = value.toIso8601String();
      } else {
        result[key] = value;
      }
    });
    return result;
  }

  // Register user
  router.get('/users', (Request req) async {
  final results = await db.mappedResultsQuery('SELECT * FROM users');
  final users = results.map((row) => _convertDateTimes(row['users'] ?? {})).toList();
  // Remove password from each user
  for (final user in users) {
    user.remove('password');
  }
  return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });
  router.post('/users', (Request req) async {
    final payload = await req.readAsString();
    final data = jsonDecode(payload);

    // Validate required fields
    if (data['email'] == null || data['password'] == null) {
      return Response(400, body: jsonEncode({'error': 'Email and password required'}), headers: {'Content-Type': 'application/json'});
    }

    // Check if user already exists
    final existing = await db.mappedResultsQuery('SELECT * FROM users WHERE email = @e', substitutionValues: {'e': data['email']});
    if (existing.isNotEmpty) {
      return Response(409, body: jsonEncode({'error': 'User already exists'}), headers: {'Content-Type': 'application/json'});
    }

    final hashedPassword = hashPassword(data['password']);

    final result = await db.query(
      'INSERT INTO users (email, password, first_name, last_name, phone_number, whatsapp_link) VALUES (@e, @p, @f, @l, @ph, @w) RETURNING id, email, first_name, last_name, phone_number, whatsapp_link',
      substitutionValues: {
        'e': data['email'],
        'p': hashedPassword,
        'f': data['first_name'],
        'l': data['last_name'],
        'ph': data['phone_number'],
        'w': data['whatsapp_link'],
      },
    );

    final user = result.first.toColumnMap();
    return Response.ok(jsonEncode({'success': true, 'user': user}), headers: {'Content-Type': 'application/json'});
  });

  // Login user
  router.post('/auth/login', (Request req) async {
  try {
    final payload = await req.readAsString();
    print('Login attempt with payload: $payload'); // Debug log
    
    final data = jsonDecode(payload);
    if (data['email'] == null || data['password'] == null) {
      return Response(400, 
        body: jsonEncode({
          'success': false,
          'error': 'Email and password are required'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final results = await db.mappedResultsQuery(
      'SELECT * FROM users WHERE email = @e',
      substitutionValues: {'e': data['email']}
    );

    if (results.isEmpty) {
      return Response(401,
        body: jsonEncode({
          'success': false,
          'error': 'Invalid email or password'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }

    var user = results.first['users'];
    if (!verifyPassword(data['password'], user?['password'])) {
      return Response(401,
        body: jsonEncode({
          'success': false,
          'error': 'Invalid email or password'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final token = generateToken(user?['id']);
    user = _convertDateTimes(user ?? {});
    user?.remove('password');
    
    print('Login successful for user: ${user?['email']}'); // Debug log
    
    return Response.ok(
      jsonEncode({
        'success': true,
        'token': token,
        'user': user
      }),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Login error: $e'); // Debug log
    return Response.internalServerError(
      body: jsonEncode({
        'success': false,
        'error': 'An unexpected error occurred'
      }),
      headers: {'Content-Type': 'application/json'}
    );
  }
});
  router.post('/auth/verify', (Request req) async {
  final authHeader = req.headers['authorization'];
  if (authHeader == null || !authHeader.startsWith('Bearer ')) {
    return Response(401);
  }

  try {
    final token = authHeader.substring(7);
    JWT.verify(token, SecretKey(jwtSecret));
    return Response.ok(
      jsonEncode({'success': true}),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    return Response(401);
  }
});

  Middleware verifyAuth() {
  return (Handler innerHandler) {
    return (Request request) async {
      final authHeader = request.headers['authorization'];
      if (authHeader == null || !authHeader.startsWith('Bearer ')) {
        return Response(401, 
          body: jsonEncode({
            'success': false,
            'error': 'Authentication required'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }

      try {
        final token = authHeader.substring(7);
        JWT.verify(token, SecretKey(jwtSecret));
        return innerHandler(request);
      } catch (e) {
        return Response(401,
          body: jsonEncode({
            'success': false,
            'error': 'Invalid token'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
    };
  };
}

  // Get all properties (returns JSON)
  router.post('/properties', (Request req) async {
    final payload = await req.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));

    // Validate required fields (update as needed)
    if (!data.containsKey('title') || !data.containsKey('type') || !data.containsKey('location')) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing required fields: title, type, location'}), headers: {'Content-Type': 'application/json'});
    }

    final id = await db.query(
      'INSERT INTO properties (title, type, location) VALUES (@title, @type, @location) RETURNING id',
      substitutionValues: {
        'title': data['title'],
        'type': data['type'],
        'location': data['location'],
      },
    );

    return Response.ok(jsonEncode({'success': true, 'id': id.first[0]}), headers: {'Content-Type': 'application/json'});
  });
  router.get('/properties', (Request req) async {
  final results = await db.mappedResultsQuery('SELECT * FROM properties');
  final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
  return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  router.get('/properties/residential', (Request req) async {
  final results = await db.mappedResultsQuery("SELECT * FROM properties WHERE type = 'residential'");
  final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
  return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  router.get('/properties/commercial', (Request req) async {
  final results = await db.mappedResultsQuery("SELECT * FROM properties WHERE type = 'commercial'");
  final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
  return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  router.get('/properties/land', (Request req) async {
  final results = await db.mappedResultsQuery("SELECT * FROM properties WHERE type = 'land'");
  final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
  return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  router.get('/properties/material', (Request req) async {
  final results = await db.mappedResultsQuery("SELECT * FROM properties WHERE type = 'material'");
  final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
  return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  // GET /properties/:id
  router.get('/properties/:id', (Request req, String id) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties WHERE id = @id', substitutionValues: {'id': int.parse(id)});
    if (results.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'Property not found'}), headers: {'Content-Type': 'application/json'});
    }
    final property = _convertDateTimes(results.first['properties'] ?? {});
    return Response.ok(jsonEncode(property), headers: {'Content-Type': 'application/json'});
  });

  router.post('/properties', (Request req) async {
    final payload = await req.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));

    // Validate required fields (update as needed)
    if (!data.containsKey('title') || !data.containsKey('type') || !data.containsKey('location')) {
      return Response.badRequest(body: jsonEncode({'error': 'Missing required fields: title, type, location'}), headers: {'Content-Type': 'application/json'});
    }

    final id = await db.query(
      'INSERT INTO properties (title, type, location) VALUES (@title, @type, @location) RETURNING id',
      substitutionValues: {
        'title': data['title'],
        'type': data['type'],
        'location': data['location'],
      },
    );

    return Response.ok(jsonEncode({'success': true, 'id': id.first[0]}), headers: {'Content-Type': 'application/json'});
  });

  // Catch-all route for undefined endpoints
  router.all('/<ignored|.*>', (Request req) {
    return Response.notFound(jsonEncode({'error': 'Route not found: ${req.url}'}), headers: {'Content-Type': 'application/json'});
  });

  Response _cors(Response response) => response.change(
    headers: {
      ...response.headers,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    },
  );

  bool _isProtectedRoute(String path, String method) {
    final publicRoutes = [
      '/auth/login',
      '/auth/register',
      '/auth/verify',
      '/users',  // Add this
      '/'
    ];
    // Check if the exact path matches any public route
    if (publicRoutes.contains(path)) {
      return false;
    }
    // Check if it's a registration request
    if (path == '/users' && method == 'POST') {
      return false;
    }
    return true;
  }

  handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware((innerHandler) {
        return (request) async {
          if (request.method == 'OPTIONS') {
            return _cors(Response.ok(''));
          }
          print('Processing ${request.method} ${request.url.path}'); // Debug log
          // Add authentication for protected routes
          if (!_isProtectedRoute(request.url.path, request.method)) {
          final response = await innerHandler(request);
          return _cors(response);
        }
          
          // Verify auth for protected routes
        final response = await verifyAuth()(innerHandler)(request);
        return _cors(response);
      };
    })
    .addHandler(router);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Server running on http://${server.address.host}:${server.port}');
}