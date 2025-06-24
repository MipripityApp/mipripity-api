import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:crypto/crypto.dart';

// Function to hash passwords using SHA-256
String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

// Secret key for JWT signing (use a secure value in production)
const String jwtSecret = String.fromEnvironment('JWT_SECRET', defaultValue: 'your_secure_secret_key_here');


bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

bool _isProtectedRoute(String path) {
  final publicRoutes = [
    '/auth/login',
    '/auth/register',
    '/auth/verify',
    '/users',  // Make POST to /users (registration) public
    '/',
  ];
  
  // Check if the path exactly matches any public route
  if (publicRoutes.contains(path)) {
    return false;
  }
  
  // Check if it's a POST request to /users (registration)
  if (path == '/users') {
    return false;
  }
  
  return true;
}

// Helper function to log user activity
Future<void> _logUserActivity(
  PostgreSQLConnection db,
  int userId,
  String activityType,
  String description, {
  Map<String, dynamic>? metadata,
  String? ipAddress,
  String? userAgent,
}) async {
  try {
    await db.query(
      '''INSERT INTO user_activity_log 
         (user_id, activity_type, activity_description, metadata, ip_address, user_agent) 
         VALUES (@user_id, @activity_type, @description, @metadata, @ip_address, @user_agent)''',
      substitutionValues: {
        'user_id': userId,
        'activity_type': activityType,
        'description': description,
        'metadata': metadata != null ? jsonEncode(metadata) : null,
        'ip_address': ipAddress,
        'user_agent': userAgent,
      },
    );
  } catch (e) {
    print('Error logging user activity: $e');
  }
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

  // Root endpoint
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
  router.post('/users', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      // Validate required fields
      if (data['email'] == null || data['password'] == null) {
        return Response(400, 
          body: jsonEncode({'error': 'Email and password required'}), 
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Check if user already exists
      final existing = await db.query(
        'SELECT id FROM users WHERE email = @e', 
        substitutionValues: {'e': data['email']}
      );
      
      if (existing.isNotEmpty) {
        return Response(409, 
          body: jsonEncode({'error': 'User already exists'}), 
          headers: {'Content-Type': 'application/json'}
        );
      }

      final hashedPassword = hashPassword(data['password']);

      final result = await db.query(
        '''INSERT INTO users (email, password, first_name, last_name, phone_number, whatsapp_link, created_at, updated_at) 
           VALUES (@e, @p, @f, @l, @ph, @w, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP) 
           RETURNING id, email, first_name, last_name, phone_number, whatsapp_link, created_at''',
        substitutionValues: {
          'e': data['email'],
          'p': hashedPassword,
          'f': data['first_name'] ?? '',
          'l': data['last_name'] ?? '',
          'ph': data['phone_number'] ?? '',
          'w': data['whatsapp_link'] ?? '',
        },
      );

      final user = result.first.toColumnMap();
      final userId = user['id'] as int;

      // Create default user settings
      await db.query(
        'INSERT INTO user_settings (user_id) VALUES (@user_id)',
        substitutionValues: {'user_id': userId},
      );

      // Log registration activity
      await _logUserActivity(
        db, 
        userId, 
        'registration', 
        'User registered successfully',
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      return Response.ok(
        jsonEncode({'success': true, 'user': user}), 
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Registration error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': 'Registration failed'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Login user
  router.post('/auth/login', (Request req) async {
    try {
      final payload = await req.readAsString();
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

      final results = await db.query(
        '''SELECT id, email, password, first_name, last_name, phone_number, whatsapp_link, 
           avatar_url, account_status, last_login 
           FROM users WHERE email = @email''',
        substitutionValues: {'email': data['email']},
      );

      if (results.isEmpty) {
        return Response(401, 
          body: jsonEncode({
            'success': false,
            'error': 'User not found'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final user = results.first.toColumnMap();
      
      // Check account status
      if (user['account_status'] != 'active') {
        return Response(403, 
          body: jsonEncode({
            'success': false,
            'error': 'Account is ${user['account_status']}'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }

      if (verifyPassword(data['password'], user['password'] as String)) {
        // Update last login
        await db.query(
          'UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = @id',
          substitutionValues: {'id': user['id']},
        );

        // Log login activity
        await _logUserActivity(
          db, 
          user['id'] as int, 
          'login', 
          'User logged in successfully',
          ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
          userAgent: req.headers['user-agent'],
        );

        // Remove password from user object
        user.remove('password');
        
        return Response.ok(
          jsonEncode({
            'success': true,
            'user': user
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      return Response(401, 
        body: jsonEncode({
          'success': false,
          'error': 'Invalid password'
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

  // Get all users (admin endpoint)
  router.get('/users', (Request req) async {
    final results = await db.query('SELECT id, email, first_name, last_name, phone_number, whatsapp_link, avatar_url, account_status, created_at, last_login FROM users');
    final users = results.map((row) => row.toColumnMap()).toList();
    return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });

  // Get user by email
  router.get('/users/email/:email', (Request req, String email) async {
    try {
      final results = await db.query(
        '''SELECT id, email, first_name, last_name, phone_number, whatsapp_link, 
           avatar_url, created_at, last_login, account_status 
           FROM users WHERE email = @email''',
        substitutionValues: {'email': email},
      );

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final user = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'user': user}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Get user by email error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': 'Database error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Get user by ID
  router.get('/users/:id', (Request req, String id) async {
    try {
      final results = await db.query(
        '''SELECT id, email, first_name, last_name, phone_number, whatsapp_link, 
           avatar_url, created_at, last_login, account_status 
           FROM users WHERE id = @id''',
        substitutionValues: {'id': int.parse(id)},
      );

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final user = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'user': user}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Get user by ID error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': 'Database error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 1. Get user settings
  router.get('/users/:id/settings', (Request req, String id) async {
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
  router.put('/users/:id/settings', (Request req, String id) async {
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

      // Log settings update activity
      await _logUserActivity(
        db, 
        userId, 
        'settings_update', 
        'User settings updated',
        metadata: data,
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

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

  // 3. Update user profile
  router.put('/users/:id/profile', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      // Build dynamic update query based on provided fields
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'user_id': userId};

      if (data.containsKey('first_name')) {
        updateFields.add('first_name = @first_name');
        substitutionValues['first_name'] = data['first_name'];
      }
      if (data.containsKey('last_name')) {
        updateFields.add('last_name = @last_name');
        substitutionValues['last_name'] = data['last_name'];
      }
      if (data.containsKey('phone_number')) {
        updateFields.add('phone_number = @phone_number');
        substitutionValues['phone_number'] = data['phone_number'];
      }
      if (data.containsKey('whatsapp_link')) {
        updateFields.add('whatsapp_link = @whatsapp_link');
        substitutionValues['whatsapp_link'] = data['whatsapp_link'];
      }
      if (data.containsKey('avatar_url')) {
        updateFields.add('avatar_url = @avatar_url');
        substitutionValues['avatar_url'] = data['avatar_url'];
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
        UPDATE users 
        SET ${updateFields.join(', ')} 
        WHERE id = @user_id
        RETURNING id, email, first_name, last_name, phone_number, whatsapp_link, avatar_url, updated_at
      ''';

      final results = await db.query(query, substitutionValues: substitutionValues);

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Log profile update activity
      await _logUserActivity(
        db, 
        userId, 
        'profile_update', 
        'User profile updated',
        metadata: data,
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      final updatedUser = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'user': updatedUser}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Update user profile error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 4. Update notification preferences
  router.put('/users/:id/notifications', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      // Build dynamic update query for notification preferences only
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'user_id': userId};

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
      if (data.containsKey('notification_sound')) {
        updateFields.add('notification_sound = @notification_sound');
        substitutionValues['notification_sound'] = data['notification_sound'];
      }
      if (data.containsKey('notification_vibration')) {
        updateFields.add('notification_vibration = @notification_vibration');
        substitutionValues['notification_vibration'] = data['notification_vibration'];
      }

      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'No notification preferences to update'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Add updated_at timestamp
      updateFields.add('updated_at = CURRENT_TIMESTAMP');

      final query = '''
        UPDATE user_settings 
        SET ${updateFields.join(', ')} 
        WHERE user_id = @user_id
        RETURNING push_notifications, email_notifications, sms_notifications, in_app_notifications, notification_sound, notification_vibration, updated_at
      ''';

      final results = await db.query(query, substitutionValues: substitutionValues);

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User settings not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Log notification preferences update activity
      await _logUserActivity(
        db, 
        userId, 
        'notification_preferences_update', 
        'Notification preferences updated',
        metadata: data,
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      final updatedNotifications = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'notifications': updatedNotifications}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Update notification preferences error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 5. Update security settings
  router.put('/users/:id/security', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      // Build dynamic update query for security settings only
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'user_id': userId};

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
      if (data.containsKey('auto_logout_minutes')) {
        updateFields.add('auto_logout_minutes = @auto_logout_minutes');
        substitutionValues['auto_logout_minutes'] = data['auto_logout_minutes'];
      }

      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'No security settings to update'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Add updated_at timestamp
      updateFields.add('updated_at = CURRENT_TIMESTAMP');

      final query = '''
        UPDATE user_settings 
        SET ${updateFields.join(', ')} 
        WHERE user_id = @user_id
        RETURNING two_factor_auth, biometric_auth, location_tracking, auto_logout_minutes, updated_at
      ''';

      final results = await db.query(query, substitutionValues: substitutionValues);

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User settings not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Log security settings update activity
      await _logUserActivity(
        db, 
        userId, 
        'security_settings_update', 
        'Security settings updated',
        metadata: data,
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      final updatedSecurity = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'security': updatedSecurity}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Update security settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 6. Get user activity log
  router.get('/users/:id/activity', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      
      // Get query parameters for pagination
      final limit = int.tryParse(req.url.queryParameters['limit'] ?? '50') ?? 50;
      final offset = int.tryParse(req.url.queryParameters['offset'] ?? '0') ?? 0;
      final activityType = req.url.queryParameters['type'];

      String query = '''
        SELECT id, activity_type, activity_description, metadata, ip_address, created_at
        FROM user_activity_log 
        WHERE user_id = @user_id
      ''';
      
      final substitutionValues = <String, dynamic>{'user_id': userId};

      if (activityType != null && activityType.isNotEmpty) {
        query += ' AND activity_type = @activity_type';
        substitutionValues['activity_type'] = activityType;
      }

      query += ' ORDER BY created_at DESC LIMIT @limit OFFSET @offset';
      substitutionValues['limit'] = limit;
      substitutionValues['offset'] = offset;

      final results = await db.query(query, substitutionValues: substitutionValues);

      // Get total count for pagination
      String countQuery = 'SELECT COUNT(*) FROM user_activity_log WHERE user_id = @user_id';
      final countSubstitutionValues = <String, dynamic>{'user_id': userId};
      
      if (activityType != null && activityType.isNotEmpty) {
        countQuery += ' AND activity_type = @activity_type';
        countSubstitutionValues['activity_type'] = activityType;
      }

      final countResults = await db.query(countQuery, substitutionValues: countSubstitutionValues);
      final totalCount = countResults.first[0] as int;

      final activities = results.map((row) => row.toColumnMap()).toList();

      return Response.ok(
        jsonEncode({
          'success': true, 
          'activities': activities,
          'pagination': {
            'total': totalCount,
            'limit': limit,
            'offset': offset,
            'hasMore': (offset + limit) < totalCount,
          }
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Get user activity log error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // 7. Update last login
  router.put('/users/:id/last-login', (Request req, String id) async {
    try {
      final userId = int.parse(id);

      final results = await db.query(
        '''UPDATE users 
           SET last_login = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP 
           WHERE id = @user_id
           RETURNING id, last_login''',
        substitutionValues: {'user_id': userId},
      );

      if (results.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Log last login update activity
      await _logUserActivity(
        db, 
        userId, 
        'last_login_update', 
        'Last login timestamp updated',
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      final updatedUser = results.first.toColumnMap();
      return Response.ok(
        jsonEncode({'success': true, 'user': updatedUser}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Update last login error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Change password endpoint
  router.put('/users/:id/password', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      if (data['current_password'] == null || data['new_password'] == null) {
        return Response.badRequest(
          body: jsonEncode({'success': false, 'error': 'Current password and new password are required'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Verify current password
      final userResults = await db.query(
        'SELECT password FROM users WHERE id = @user_id',
        substitutionValues: {'user_id': userId},
      );

      if (userResults.isEmpty) {
        return Response.notFound(
          jsonEncode({'success': false, 'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final currentHashedPassword = userResults.first[0] as String;
      if (!verifyPassword(data['current_password'], currentHashedPassword)) {
        return Response(401,
          body: jsonEncode({'success': false, 'error': 'Current password is incorrect'}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      // Update password
      final newHashedPassword = hashPassword(data['new_password']);
      await db.query(
        'UPDATE users SET password = @password, updated_at = CURRENT_TIMESTAMP WHERE id = @user_id',
        substitutionValues: {
          'password': newHashedPassword,
          'user_id': userId,
        },
      );

      // Log password change activity
      await _logUserActivity(
        db, 
        userId, 
        'password_change', 
        'Password changed successfully',
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Password updated successfully'}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Change password error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Logout endpoint (for logging activity)
  router.post('/auth/logout/:id', (Request req, String id) async {
    try {
      final userId = int.parse(id);

      // Log logout activity
      await _logUserActivity(
        db, 
        userId, 
        'logout', 
        'User logged out',
        ipAddress: req.headers['x-forwarded-for'] ?? req.headers['x-real-ip'],
        userAgent: req.headers['user-agent'],
      );

      return Response.ok(
        jsonEncode({'success': true, 'message': 'Logged out successfully'}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Logout error: $e');
      return Response.internalServerError(
        body: jsonEncode({'success': false, 'error': e.toString()}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // PROPERTY ENDPOINTS

  // Get all properties (returns JSON)
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

  // GET /properties/property_id
  router.get('/properties/:id', (Request req, String id) async {
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

  // CORS middleware
  Response _cors(Response response) => response.change(
    headers: {
      ...response.headers,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    },
  );

  // Handle CORS preflight requests
  router.options('/<path|.*>', (Request req) {
    return Response.ok('', headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    });
  });

  // Create the handler with CORS middleware and route protection
  final handler = Pipeline()
      .addMiddleware((Handler innerHandler) {
        return (Request request) async {
          if (request.method == 'OPTIONS') {
            return _cors(Response.ok(''));
          }
          
          // Implement route protection
          if (_isProtectedRoute(request.url.path)) {
            // Check for authentication token (implement proper JWT validation in production)
            final authHeader = request.headers['authorization'];
            if (authHeader == null || !authHeader.startsWith('Bearer ')) {
              return _cors(Response(401,
                body: jsonEncode({'error': 'Authentication required'}),
                headers: {'Content-Type': 'application/json'}
              ));
            }
            
            // Here you would validate the token
            // For now, we're just checking that it exists
          }
          
          final response = await innerHandler(request);
          return _cors(response);
        };
      })
      .addHandler(router);

  // Start the server
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await HttpServer.bind('0.0.0.0', port);
  print('Server running on port $port');
  
  await server.forEach((HttpRequest request) async {
    // Convert HttpHeaders to Map<String, String>
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    
    final response = await handler(Request(
      request.method,
      request.uri,
      body: request,
      headers: headers,
    ));
    
    request.response.statusCode = response.statusCode;
    response.headers.forEach((name, value) {
      request.response.headers.set(name, value);
    });
    
    await response.read().forEach(request.response.add);
    await request.response.close();
  });
}