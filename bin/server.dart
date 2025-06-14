import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:crypto/crypto.dart';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

void main() async {
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
    final payload = await req.readAsString();
    final data = jsonDecode(payload);

    final email = data['email'];
    final password = data['password'];

    final results = await db.mappedResultsQuery('SELECT * FROM users WHERE email = @e', substitutionValues: {'e': email});
    if (results.isEmpty) {
      return Response(401, body: jsonEncode({'error': 'Invalid credentials'}), headers: {'Content-Type': 'application/json'});
    }

    final user = results.first['users'];
    if (!verifyPassword(password, user?['password'])) {
      return Response(401, body: jsonEncode({'error': 'Invalid credentials'}), headers: {'Content-Type': 'application/json'});
    }

    // Remove password from response
    user?.remove('password');
    return Response.ok(jsonEncode({'success': true, 'user': user}), headers: {'Content-Type': 'application/json'});
  });

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

    router.all('/<ignored|.*>', (Request req) {
  return Response.notFound(jsonEncode({'error': 'Route not found: ${req.url}'}), headers: {'Content-Type': 'application/json'});
  });

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

  Response _cors(Response response) => response.change(
  headers: {
    ...response.headers,
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
  },
);

final handler = Pipeline()
    .addMiddleware(logRequests())
    .addMiddleware((innerHandler) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          return _cors(Response.ok(''));
        }
        final response = await innerHandler(request);
        return _cors(response);
      };
    })
    .addHandler(router);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
}