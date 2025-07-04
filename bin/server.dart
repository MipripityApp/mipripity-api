import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:mipripity_api/cac_verification.dart'; // Import CAC verification handler
import 'package:crypto/crypto.dart';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

// Model for Poll Property - properties users can vote on suggested uses
class PollProperty {
  final String id;
  final String title;
  final String location;
  final String imageUrl;
  final List<Map<String, dynamic>> suggestions; // Each suggestion has name and votes

  PollProperty({
    required this.id,
    required this.title,
    required this.location,
    required this.imageUrl,
    required this.suggestions,
  });

  factory PollProperty.fromJson(Map<String, dynamic> json) {
    final suggestionsList = (json['suggestions'] as List)
        .map((suggestion) => suggestion as Map<String, dynamic>)
        .toList();

    return PollProperty(
      id: json['id'],
      title: json['title'],
      location: json['location'],
      imageUrl: json['image_url'] ?? json['imageUrl'] ?? '',
      suggestions: suggestionsList,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'location': location,
      'image_url': imageUrl,
      'suggestions': suggestions,
    };
  }
}

class Investment {
  final String id;
  final String title;
  final String location;
  final String description;
  final String realtorName;
  final String realtorImage;
  final int minInvestment;
  final String expectedReturn;
  final String duration;
  final int investors;
  final int remainingAmount;
  final int totalAmount;
  final List<String> images;   
  final List<String> features;  

  Investment({
    required this.id,
    required this.title,
    required this.location,
    required this.description,
    required this.realtorName,
    required this.realtorImage,
    required this.minInvestment,
    required this.expectedReturn,
    required this.duration,
    required this.investors,
    required this.remainingAmount,
    required this.totalAmount,
    required this.images,
    required this.features,
  });

  factory Investment.fromJson(Map<String, dynamic> json) {
  return Investment(
    id: json['id'],
    title: json['title'],
    location: json['location'],
    description: json['description'],
    realtorName: json['realtorName'],
    realtorImage: json['realtorImage'],
    minInvestment: json['minInvestment'],
    expectedReturn: json['expectedReturn'],
    duration: json['duration'],
    investors: json['investors'],
    remainingAmount: json['remainingAmount'],
    totalAmount: json['totalAmount'],
    images: (json['images'] as List).map((e) => e.toString()).toList(),
    features: (json['features'] as List).map((e) => e.toString()).toList(),
  );
}


Map<String, dynamic> toJson() {
  return {
    'id': id,
    'title': title,
    'location': location,
    'description': description,
    'realtorName': realtorName,
    'realtorImage': realtorImage,
    'minInvestment': minInvestment,
    'expectedReturn': expectedReturn,
    'duration': duration,
    'investors': investors,
    'remainingAmount': remainingAmount,
    'totalAmount': totalAmount,
    'images': images,
    'features': features,
  };
}

}

void main() async {
  PostgreSQLConnection db;

  try {
    db = await DatabaseHelper.connect();
    print('Connected to database successfully using configuration from pubspec.yaml');
    
    // Create poll_properties table if it doesn't exist
    try {
      // Create poll_properties table exactly as described by the schema
      await db.execute('''
        CREATE TABLE IF NOT EXISTS poll_properties (
          id TEXT PRIMARY KEY,
          title TEXT NOT NULL,
          location TEXT NOT NULL,
          image_url TEXT NOT NULL,
          suggestions JSONB DEFAULT '[]'::jsonb,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          poll_user_votes JSONB DEFAULT '[]'::jsonb,
          poll_suggestions JSONB DEFAULT '[]'::jsonb
        )
      ''');
      
      // Create poll_suggestions table if it doesn't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS poll_suggestions (
          id UUID PRIMARY KEY,
          poll_property_id UUID,
          suggestion TEXT NOT NULL,
          votes INTEGER DEFAULT 0,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      
      // Create poll_user_votes table if it doesn't exist
      await db.execute('''
        CREATE TABLE IF NOT EXISTS poll_user_votes (
          id UUID PRIMARY KEY,
          user_id TEXT NOT NULL,
          suggestion TEXT NOT NULL,
          poll_property_id UUID,
          voted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      
      print('Poll properties tables created successfully');
    } catch (e) {
      print('Error creating poll properties tables: $e');
      // Continue anyway as this is not critical for the API to function
    }
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
  // Get user by ID
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
          headers: {'Content-Type': 'application/json'},
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
        body: jsonEncode({'error': 'Invalid user ID format or database error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });
  
  // Poll Properties Endpoints - moved to top level
  // GET /poll_properties - Fetch all poll properties with their suggestions and vote counts
  router.get('/poll_properties', (Request req) async {
    try {
      // Fetch all poll properties
      final pollResults = await db.mappedResultsQuery('''
        SELECT * FROM poll_properties ORDER BY created_at DESC
      ''');
      
      if (pollResults.isEmpty) {
        return Response.ok(
          jsonEncode([]),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final List<Map<String, dynamic>> pollProperties = [];
      
      // Process each poll property
      for (final poll in pollResults) {
        final pollData = _convertDateTimes(poll['poll_properties'] ?? {});
        
        // Ensure we parse JSON fields correctly
        if (pollData['suggestions'] != null && pollData['suggestions'] is String) {
          try {
            pollData['suggestions'] = jsonDecode(pollData['suggestions']);
          } catch (e) {
            print('Error parsing suggestions JSON: $e');
            pollData['suggestions'] = [];
          }
        }
        
        if (pollData['poll_user_votes'] != null && pollData['poll_user_votes'] is String) {
          try {
            pollData['poll_user_votes'] = jsonDecode(pollData['poll_user_votes']);
          } catch (e) {
            print('Error parsing poll_user_votes JSON: $e');
            pollData['poll_user_votes'] = [];
          }
        }
        
        if (pollData['poll_suggestions'] != null && pollData['poll_suggestions'] is String) {
          try {
            pollData['poll_suggestions'] = jsonDecode(pollData['poll_suggestions']);
          } catch (e) {
            print('Error parsing poll_suggestions JSON: $e');
            pollData['poll_suggestions'] = [];
          }
        }
        
        pollProperties.add(pollData);
      }
      
      return Response.ok(
        jsonEncode(pollProperties),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error fetching poll properties: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch poll properties'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });
  
  // POST /poll_properties - Create a new poll property with suggestions
  router.post('/poll_properties', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      // Validate required fields
      if (data['title'] == null || data['location'] == null || data['suggestions'] == null || 
          !data['suggestions'].isNotEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields: title, location, suggestions'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Generate unique ID for the poll property
      final uuid = Uuid();
      final id = uuid.v4();
      
      // Prepare suggestions data
      final List<Map<String, dynamic>> suggestions = [];
      if (data['suggestions'] is List) {
        for (final suggestion in data['suggestions']) {
          if (suggestion is String) {
            suggestions.add({
              'suggestion': suggestion,
              'votes': 0
            });
          } else if (suggestion is Map<String, dynamic> && suggestion.containsKey('suggestion')) {
            suggestions.add({
              'suggestion': suggestion['suggestion'],
              'votes': suggestion['votes'] ?? 0
            });
          }
        }
      }
      
      // Insert the poll property with all JSON fields
      await db.execute('''
        INSERT INTO poll_properties (
          id, 
          title, 
          location, 
          image_url, 
          suggestions, 
          poll_user_votes, 
          poll_suggestions
        )
        VALUES (
          @id, 
          @title, 
          @location, 
          @image_url, 
          @suggestions, 
          @poll_user_votes, 
          @poll_suggestions
        )
      ''', substitutionValues: {
        'id': id,
        'title': data['title'],
        'location': data['location'],
        'image_url': data['image_url'] ?? '',
        'suggestions': jsonEncode(suggestions),
        'poll_user_votes': jsonEncode([]),
        'poll_suggestions': jsonEncode(suggestions),
      });
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'id': id,
          'message': 'Poll property created successfully'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error creating poll property: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create poll property'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });
  
  // POST /poll_properties/:id/vote - Record a vote for a specific suggestion
  router.post('/poll_properties/<id>/vote', (Request req, String id) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      // Validate required fields
      if (data['suggestion'] == null || data['user_id'] == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields: suggestion, user_id'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Fetch the poll property
      final pollResults = await db.mappedResultsQuery(
        'SELECT * FROM poll_properties WHERE id = @id',
        substitutionValues: {'id': id}
      );
      
      if (pollResults.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Poll property not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final pollData = pollResults.first['poll_properties'] ?? {};
      
      // Parse JSON fields
      List<Map<String, dynamic>> suggestions = [];
      List<Map<String, dynamic>> userVotes = [];
      
      if (pollData['suggestions'] != null) {
        try {
          if (pollData['suggestions'] is String) {
            suggestions = List<Map<String, dynamic>>.from(jsonDecode(pollData['suggestions']));
          } else if (pollData['suggestions'] is List) {
            suggestions = List<Map<String, dynamic>>.from(pollData['suggestions']);
          }
        } catch (e) {
          print('Error parsing suggestions: $e');
          suggestions = [];
        }
      }
      
      if (pollData['poll_user_votes'] != null) {
        try {
          if (pollData['poll_user_votes'] is String) {
            userVotes = List<Map<String, dynamic>>.from(jsonDecode(pollData['poll_user_votes']));
          } else if (pollData['poll_user_votes'] is List) {
            userVotes = List<Map<String, dynamic>>.from(pollData['poll_user_votes']);
          }
        } catch (e) {
          print('Error parsing poll_user_votes: $e');
          userVotes = [];
        }
      }
      
      // Check if suggestion exists
      final suggestionExists = suggestions.any((s) => s['suggestion'] == data['suggestion']);
      if (!suggestionExists) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid suggestion for this poll property'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Check if user has already voted
      final existingVoteIndex = userVotes.indexWhere((vote) => vote['user_id'] == data['user_id']);
      String message;
      
      if (existingVoteIndex != -1) {
        // User has already voted
        final previousSuggestion = userVotes[existingVoteIndex]['suggestion'];
        
        if (previousSuggestion == data['suggestion']) {
          return Response.ok(
            jsonEncode({
              'success': true,
              'message': 'You have already voted for this suggestion'
            }),
            headers: {'Content-Type': 'application/json'}
          );
        }
        
        // User is changing their vote - update votes count
        for (int i = 0; i < suggestions.length; i++) {
          if (suggestions[i]['suggestion'] == previousSuggestion) {
            suggestions[i]['votes'] = (suggestions[i]['votes'] ?? 0) - 1;
            if (suggestions[i]['votes'] < 0) suggestions[i]['votes'] = 0;
          }
          
          if (suggestions[i]['suggestion'] == data['suggestion']) {
            suggestions[i]['votes'] = (suggestions[i]['votes'] ?? 0) + 1;
          }
        }
        
        // Update user vote record
        userVotes[existingVoteIndex] = {
          'user_id': data['user_id'],
          'suggestion': data['suggestion'],
          'voted_at': DateTime.now().toIso8601String()
        };
        
        message = 'Vote changed successfully';
      } else {
        // New vote - increment vote count
        for (int i = 0; i < suggestions.length; i++) {
          if (suggestions[i]['suggestion'] == data['suggestion']) {
            suggestions[i]['votes'] = (suggestions[i]['votes'] ?? 0) + 1;
          }
        }
        
        // Add user vote record
        userVotes.add({
          'user_id': data['user_id'],
          'suggestion': data['suggestion'],
          'voted_at': DateTime.now().toIso8601String()
        });
        
        message = 'Vote recorded successfully';
      }
      
      // Update the database with new values
      await db.execute('''
        UPDATE poll_properties 
        SET suggestions = @suggestions,
            poll_user_votes = @poll_user_votes,
            poll_suggestions = @poll_suggestions
        WHERE id = @id
      ''', substitutionValues: {
        'id': id,
        'suggestions': jsonEncode(suggestions),
        'poll_user_votes': jsonEncode(userVotes),
        'poll_suggestions': jsonEncode(suggestions)
      });
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': message
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error recording vote: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to record vote'}),
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

  // Get user settings
  router.get('/users/id/<id>/settings', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      
      final results = await db.mappedResultsQuery(
        'SELECT * FROM user_settings WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );

      if (results.isEmpty) {
        // Create default settings if none exist
        await db.query(
          'INSERT INTO user_settings (user_id) VALUES (@user_id)',
          substitutionValues: {'user_id': userId},
        );
        
        // Fetch the newly created settings using mappedResultsQuery
        final newResults = await db.mappedResultsQuery(
          'SELECT * FROM user_settings WHERE user_id = @user_id',
          substitutionValues: {'user_id': userId},
        );
        
        if (newResults.isEmpty) {
          return Response.internalServerError(
            body: jsonEncode({'error': 'Failed to create default settings'}),
            headers: {'Content-Type': 'application/json'}
          );
        }
        
        final settings = _convertDateTimes(newResults.first['user_settings'] ?? {});
        return Response.ok(
          jsonEncode({'success': true, 'settings': settings}),
          headers: {'Content-Type': 'application/json'}
        );
      }

      final settings = _convertDateTimes(results.first['user_settings'] ?? {});
      return Response.ok(
        jsonEncode({'success': true, 'settings': settings}),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Get user settings error: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Invalid user ID format or database error'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Update user settings
router.put('/users/id/<id>/settings', (Request req, String id) async {
  try {
    final userId = int.parse(id);
    final payload = await req.readAsString();
    final data = jsonDecode(payload) as Map<String, dynamic>;

    if (data.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'No data provided for update'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Check if user exists
    final userExists = await db.mappedResultsQuery(
      'SELECT id FROM users WHERE id = @id',
      substitutionValues: {'id': userId},
    );

    if (userExists.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'User not found'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Check if settings exist, create if not
    final settingsExist = await db.mappedResultsQuery(
      'SELECT user_id FROM user_settings WHERE user_id = @user_id',
      substitutionValues: {'user_id': userId},
    );

    if (settingsExist.isEmpty) {
      await db.query(
        'INSERT INTO user_settings (user_id) VALUES (@user_id)',
        substitutionValues: {'user_id': userId},
      );
    }

    // Build dynamic update query based on provided fields
    final updateFields = <String>[];
    final substitutionValues = <String, dynamic>{'user_id': userId};

    // Add valid fields to update (adjust these based on your user_settings table schema)
    final validFields = [
      'notification_preferences', 'theme', 'language', 'timezone', 
      'privacy_settings', 'email_notifications', 'push_notifications',
      'sms_notifications', 'marketing_emails', 'updated_at'
    ];

    for (final field in validFields) {
      if (data.containsKey(field)) {
        updateFields.add('$field = @$field');
        substitutionValues[field] = data[field];
      }
    }

    if (updateFields.isEmpty) {
      return Response.badRequest(
        body: jsonEncode({'error': 'No valid fields provided for update'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Add updated_at timestamp
    if (!data.containsKey('updated_at')) {
      updateFields.add('updated_at = @updated_at');
      substitutionValues['updated_at'] = DateTime.now().toIso8601String();
    }

    final updateQuery = '''
      UPDATE user_settings 
      SET ${updateFields.join(', ')} 
      WHERE user_id = @user_id
    ''';

    await db.query(updateQuery, substitutionValues: substitutionValues);

    // Fetch and return updated settings
    final results = await db.mappedResultsQuery(
      'SELECT * FROM user_settings WHERE user_id = @user_id',
      substitutionValues: {'user_id': userId},
    );

    if (results.isEmpty) {
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch updated settings'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final settings = _convertDateTimes(results.first['user_settings'] ?? {});
    return Response.ok(
      jsonEncode({'success': true, 'settings': settings, 'message': 'Settings updated successfully'}),
      headers: {'Content-Type': 'application/json'}
    );

  } catch (e) {
    print('Update user settings error: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Invalid data format or database error'}),
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


Future<Response> createInvestment(Request req) async {
  final db = await DatabaseHelper.connect();
  final uuid = Uuid();

  try {
    final body = await req.readAsString();
    final investmentData = jsonDecode(body);

    // Generate a new ID
    final id = uuid.v4();

    // Extract and prepare values
    final investment = Investment.fromJson({
      'id': id,
      ...investmentData,
    });

    await db.execute('''
      INSERT INTO investments (
        id, title, location, description, realtorName, realtorImage,
        minInvestment, expectedReturn, duration, investors,
        remainingAmount, totalAmount, images, features
      ) VALUES (
        @id, @title, @location, @description, @realtorName, @realtorImage,
        @minInvestment, @expectedReturn, @duration, @investors,
        @remainingAmount, @totalAmount, @images, @features
      )
    ''', substitutionValues: {
      'id': investment.id,
      'title': investment.title,
      'location': investment.location,
      'description': investment.description,
      'realtorName': investment.realtorName,
      'realtorImage': investment.realtorImage,
      'minInvestment': investment.minInvestment,
      'expectedReturn': investment.expectedReturn,
      'duration': investment.duration,
      'investors': investment.investors,
      'remainingAmount': investment.remainingAmount,
      'totalAmount': investment.totalAmount,
      'images': jsonEncode(investment.images),
      'features': jsonEncode(investment.features),
    });

    return Response.ok('Investment created successfully');
  } catch (e) {
    return Response.internalServerError(
      body: 'Error creating investment: $e',
    );
  } finally {
    await db.close();
  }
}

Future<Response> fetchInvestments(Request req) async {
  final db = await DatabaseHelper.connect();

  try {
    final results = await db.query('SELECT * FROM investments');
    final investments = results.map((row) {
  final map = Map.fromIterables(
    results.columnDescriptions.map((c) => c.columnName),
    row,
  );

  // Decode JSON arrays from DB back to List<String>
  final images = jsonDecode(map['images'] ?? '[]').cast<String>();
  final features = jsonDecode(map['features'] ?? '[]').cast<String>();

  return Investment(
    id: map['id'],
    title: map['title'],
    location: map['location'],
    description: map['description'],
    realtorName: map['realtorname'],
    realtorImage: map['realtorimage'],
    minInvestment: map['mininvestment'],
    expectedReturn: map['expectedreturn'],
    duration: map['duration'],
    investors: map['investors'],
    remainingAmount: map['remainingamount'],
    totalAmount: map['totalamount'],
    images: images,
    features: features,
  ).toJson();
}).toList();


return Response.ok(jsonEncode(investments), headers: {
  'Content-Type': 'application/json',
});

  } catch (e) {
    return Response.internalServerError(
      body: jsonEncode({'error': 'Error fetching investments: $e'}),
    );
  } finally {
    await db.close();
  }
}

  // Add API endpoint for creating investments
  router.post('/investments', (Request req) async {
    return createInvestment(req);
  });

  // Add API endpoint for fetching investments
  router.get('/investments', (Request req) async {
    return fetchInvestments(req);
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

  // CAC agency verification endpoint
  router.post('/verify-agency', CacVerificationHandler.handleVerifyAgency);

  // New endpoint for voting on poll suggestions without property ID in URL
  router.post('/poll_properties/vote', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);

      final userId = data['user_id'];
      final suggestion = data['suggestion'];

      if (userId == null || suggestion == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing user_id or suggestion'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Step 1: Check if suggestion exists in poll_suggestions
      final suggestionQuery = await db.query(
        'SELECT * FROM poll_suggestions WHERE suggestion = @suggestion',
        substitutionValues: {'suggestion': suggestion},
      );

      if (suggestionQuery.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Invalid suggestion for this poll property'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Step 2: Prevent duplicate votes by checking poll_user_votes
      final voteCheck = await db.query(
        'SELECT * FROM poll_user_votes WHERE user_id = @userId AND suggestion = @suggestion',
        substitutionValues: {
          'userId': userId,
          'suggestion': suggestion,
        },
      );

      if (voteCheck.isNotEmpty) {
        return Response.forbidden(
          jsonEncode({'error': 'You have already voted for this suggestion'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Step 3: Record the vote
      final voteId = Uuid().v4();
      await db.execute(
        'INSERT INTO poll_user_votes (id, user_id, suggestion, voted_at) '
        'VALUES (@id, @userId, @suggestion, NOW())',
        substitutionValues: {
          'id': voteId,
          'userId': userId,
          'suggestion': suggestion,
        },
      );

      // Step 4: Increment vote count
      await db.execute(
        'UPDATE poll_suggestions SET votes = votes + 1 WHERE suggestion = @suggestion',
        substitutionValues: {'suggestion': suggestion},
      );

      return Response.ok(
        jsonEncode({'message': 'Vote recorded successfully'}),
        headers: {'Content-Type': 'application/json'},
      );

    } catch (e) {
      return Response.internalServerError(
        body: jsonEncode({'error': e.toString()}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  });

  // Update the database schema to include new agency verification fields
  try {
    // Check if rc_number and official_agency_name columns already exist
    final columnsExist = await db.mappedResultsQuery("""
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'users' 
        AND column_name IN ('rc_number', 'official_agency_name')
    """);
    
    if (columnsExist.isEmpty) {
      // Add the new columns to store CAC verification data
      await db.execute("""
        ALTER TABLE users 
        ADD COLUMN IF NOT EXISTS rc_number VARCHAR(50),
        ADD COLUMN IF NOT EXISTS official_agency_name VARCHAR(255)
      """);
      print('Added CAC verification columns to users table');
    }
  } catch (e) {
    print('Error updating database schema: $e');
    // Continue anyway, as this is not critical for the API to function
  }

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