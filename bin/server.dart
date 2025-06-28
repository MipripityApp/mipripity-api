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

  // Get all users (admin endpoint)
  router.get('/users', (Request req) async {
    final results = await db.query('SELECT id, email, first_name, last_name, phone_number, whatsapp_link, avatar_url, account_status, created_at, last_login FROM users');
    final users = results.map((row) => _convertDateTimes(row.toColumnMap())).toList();
    return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });

  // Register user
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
      final data = jsonDecode(payload);

      // Validate input
      if (data['email'] == null || data['password'] == null) {
        return Response(400, 
          body: jsonEncode({
            'success': false,
            'error': 'Email and password are required'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final email = data['email'];
      final password = data['password'];

      final results = await db.mappedResultsQuery(
        'SELECT * FROM users WHERE email = @e',
        substitutionValues: {'e': email}
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

      final user = results.first['users'];
      if (!verifyPassword(password, user?['password'])) {
        return Response(401,
          body: jsonEncode({
            'success': false,
            'error': 'Invalid email or password'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Remove sensitive data
      user?.remove('password');
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'user': user
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Login error: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'success': false,
          'error': 'An unexpected error occurred'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Get user by ID - FIXED: More specific route pattern
  router.get('/users/id/<id>', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final results = await db.mappedResultsQuery(
        '''SELECT id, email, first_name, last_name, phone_number, whatsapp_link, 
           avatar_url, created_at, last_login, account_status 
           FROM users WHERE id = @id''',
        substitutionValues: {'id': userId},
      );

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final user = _convertDateTimes(results.first['users'] ?? {});
      return Response.ok(
        jsonEncode(user),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      print('Get user by ID error: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Invalid user ID format'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Get user by email - FIXED: More specific route pattern
  router.get('/users/email/<email>', (Request req, String email) async {
    final results = await db.mappedResultsQuery(
      '''SELECT id, email, first_name, last_name, phone_number, whatsapp_link, 
        avatar_url, created_at, last_login, account_status 
        FROM users WHERE email = @email''',
      substitutionValues: {'email': email},
    );

    if (results.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'User not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }

    final user = _convertDateTimes(results.first['users'] ?? {});
    return Response.ok(
      jsonEncode(user),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // 1. Get user settings
  router.get('/users/<id>/settings', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      
      final results = await db.query(
        'SELECT * FROM user_settings WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );

      if (results.isEmpty) {
        // Create default settings if none exist
        await db.query(
          'INSERT INTO user_settings (user_id) VALUES (@user_id)',
          substitutionValues: {'user_id': userId},
        );
        
        // Fetch the newly created settings
        final newResults = await db.query(
          'SELECT * FROM user_settings WHERE user_id = @user_id',
          substitutionValues: {'user_id': userId},
        );
        
        final settings = newResults.first.toColumnMap();
        return Response.ok(
          jsonEncode({'success': true, 'settings': settings}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final settings = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'settings': settings}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Get user settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 2. Update user settings
  router.put('/users/<id>/settings', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      // Build dynamic update query based on provided fields
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'user_id': userId};

      // Notification preferences
      if (data.containsKey('push_notifications')) {
        updateFields.add('push_notifications = @push_notifications');
        substitutionValues['push_notifications'] = data['push_notifications'];
      }
      if (data.containsKey('email_notifications')) {
        updateFields.add('email_notifications = @email_notifications');
        substitutionValues['email_notifications'] = data['email_notifications'];
      }
      if (data.containsKey('sms_notifications')) {
        updateFields.add('sms_notifications = @sms_notifications');
        substitutionValues['sms_notifications'] = data['sms_notifications'];
      }
      if (data.containsKey('in_app_notifications')) {
        updateFields.add('in_app_notifications = @in_app_notifications');
        substitutionValues['in_app_notifications'] = data['in_app_notifications'];
      }

      // App preferences
      if (data.containsKey('theme_preference')) {
        updateFields.add('theme_preference = @theme_preference');
        substitutionValues['theme_preference'] = data['theme_preference'];
      }
      if (data.containsKey('language_preference')) {
        updateFields.add('language_preference = @language_preference');
        substitutionValues['language_preference'] = data['language_preference'];
      }
      if (data.containsKey('currency_preference')) {
        updateFields.add('currency_preference = @currency_preference');
        substitutionValues['currency_preference'] = data['currency_preference'];
      }
      if (data.containsKey('distance_unit')) {
        updateFields.add('distance_unit = @distance_unit');
        substitutionValues['distance_unit'] = data['distance_unit'];
      }
      if (data.containsKey('date_format')) {
        updateFields.add('date_format = @date_format');
        substitutionValues['date_format'] = data['date_format'];
      }

      // Security settings
      if (data.containsKey('two_factor_auth')) {
        updateFields.add('two_factor_auth = @two_factor_auth');
        substitutionValues['two_factor_auth'] = data['two_factor_auth'];
      }
      if (data.containsKey('biometric_auth')) {
        updateFields.add('biometric_auth = @biometric_auth');
        substitutionValues['biometric_auth'] = data['biometric_auth'];
      }
      if (data.containsKey('location_tracking')) {
        updateFields.add('location_tracking = @location_tracking');
        substitutionValues['location_tracking'] = data['location_tracking'];
      }

      // Privacy settings
      if (data.containsKey('profile_visibility')) {
        updateFields.add('profile_visibility = @profile_visibility');
        substitutionValues['profile_visibility'] = data['profile_visibility'];
      }
      if (data.containsKey('show_email')) {
        updateFields.add('show_email = @show_email');
        substitutionValues['show_email'] = data['show_email'];
      }
      if (data.containsKey('show_phone')) {
        updateFields.add('show_phone = @show_phone');
        substitutionValues['show_phone'] = data['show_phone'];
      }

      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'No valid fields to update'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Add updated_at timestamp
      updateFields.add('updated_at = CURRENT_TIMESTAMP');

      final query = '''
        UPDATE user_settings 
        SET ${updateFields.join(', ')} 
        WHERE user_id = @user_id
        RETURNING *
      ''';

      final results = await db.query(query, substitutionValues: substitutionValues);

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User settings not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final updatedSettings = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'settings': updatedSettings}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Update user settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Get all properties (returns JSON)
  router.get('/properties', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties');
    final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
    return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  // Create property
  router.post('/properties', (Request req) async {
    final payload = await req.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));

    // Validate required fields
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

  // GET /properties/property_id
  router.get('/properties/<id>', (Request req, String id) async {
    List<Map<String, Map<String, dynamic>>> results = [];
    // Try integer id first
    try {
      results = await db.mappedResultsQuery(
        'SELECT * FROM properties WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
    } catch (_) {
      // If not integer, try property_id
      results = await db.mappedResultsQuery(
        'SELECT * FROM properties WHERE property_id = @property_id',
        substitutionValues: {'property_id': id},
      );
    }
    if (results.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'Property not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    final property = _convertDateTimes(results.first['properties'] ?? {});
    return Response.ok(
      jsonEncode(property),
      headers: {'Content-Type': 'application/json'},
    );
  });

  // CORS helper function
  Response _cors(Response response) => response.change(
    headers: {
      ...response.headers,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    },
  );

  // Handle 404 routes
  router.all('/<ignored|.*>', (Request req) {
    return Response.notFound(jsonEncode({'error': 'Route not found: ${req.url}'}), headers: {'Content-Type': 'application/json'});
  });

  // Create the handler pipeline
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