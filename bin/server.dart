import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';

void main() async {
  // Use the DatabaseHelper to connect to the database with configuration from pubspec.yaml
  PostgreSQLConnection db;

  try {
    db = await DatabaseHelper.connect();
    print('Connected to database successfully using configuration from pubspec.yaml');
  } catch (e) {
    print('Failed to connect to the database: $e');
    print('Please ensure the database credentials are correct in pubspec.yaml or environment variables');
    exit(1);
  }

  final router = Router();

  // Add this root route
  router.get('/', (Request req) async {
    return Response.ok('Mipripity API is running');
  });

  router.get('/ping', (Request req) async {
    return Response.ok('API is live');
  });

  router.get('/users', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM users');
    return Response.ok(results.toString());
  });

  router.post('/users', (Request req) async {
    final payload = await req.readAsString();
    final data = jsonDecode(payload);
    await db.query(
      'INSERT INTO users (name, email) VALUES (@name, @email)',
      substitutionValues: {
        'name': data['name'],
        'email': data['email'],
      },
    );
    return Response.ok(jsonEncode({'status': 'User added'}), headers: {'Content-Type': 'application/json'});
  });
  
  router.get('/properties', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties');
    return Response.ok(results.toString());
  });

  router.get('/properties/residential', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties WHERE type = \'residential\'');
    return Response.ok(results.toString());
  });

  router.get('/properties/commercial', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties WHERE type = \'commercial\'');
    return Response.ok(results.toString());
  });

  router.get('/properties/:id', (Request req, String id) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties WHERE id = @id', substitutionValues: {'id': int.parse(id)});
    if (results.isEmpty) {
      return Response.notFound('Property not found');
    }
    return Response.ok(results.first.toString());
  });

  router.post('/properties', (Request req) async {
    final payload = await req.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));
  
    if (!data.containsKey('name') || !data.containsKey('type') || !data.containsKey('location')) {
      return Response.badRequest(body: 'Missing required fields: name, type, location');
    }

  
    
    // Assuming you have a function to insert property data
    final id = await db.query(
      'INSERT INTO properties (name, type, location) VALUES (@name, @type, @location) RETURNING id',
      substitutionValues: {
        'name': data['name'],
        'type': data['type'],
        'location': data['location'],
      },
    );

    return Response.ok('Property created with ID: ${id.first[0]}');
  });

  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addHandler(router);

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);
  print('Server listening on port ${server.port}');
}
