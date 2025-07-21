import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

String hashPassword(String password) {
  return sha256.convert(utf8.encode(password)).toString();
}

bool verifyPassword(String password, String hash) {
  return hashPassword(password) == hash;
}

// Model for Bid - users can place bids on properties
class Bid {
  final String id;
  final String listingId;
  final String listingTitle;
  final String listingImage;
  final String listingCategory;
  final String listingLocation;
  final double listingPrice;
  final double bidAmount;
  final String status;
  final String createdAt;
  final String? responseMessage;
  final String? responseDate;
  final String? userId;

  Bid({
    required this.id,
    required this.listingId,
    required this.listingTitle,
    required this.listingImage,
    required this.listingCategory,
    required this.listingLocation,
    required this.listingPrice,
    required this.bidAmount,
    required this.status,
    required this.createdAt,
    this.responseMessage,
    this.responseDate,
    this.userId,
  });

  factory Bid.fromJson(Map<String, dynamic> json) {
    return Bid(
      id: json['id'] ?? '',
      listingId: json['listing_id'] ?? '',
      listingTitle: json['listing_title'] ?? '',
      listingImage: json['listing_image'] ?? '',
      listingCategory: json['listing_category'] ?? '',
      listingLocation: json['listing_location'] ?? '',
      listingPrice: (json['listing_price'] is num)
          ? (json['listing_price'] as num).toDouble()
          : double.tryParse(json['listing_price']?.toString() ?? '0') ?? 0.0,
      bidAmount: (json['bid_amount'] is num)
          ? (json['bid_amount'] as num).toDouble()
          : double.tryParse(json['bid_amount']?.toString() ?? '0') ?? 0.0,
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] ?? DateTime.now().toIso8601String(),
      responseMessage: json['response_message'],
      responseDate: json['response_date'],
      userId: json['user_id'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'listing_id': listingId,
      'listing_title': listingTitle,
      'listing_image': listingImage,
      'listing_category': listingCategory,
      'listing_location': listingLocation,
      'listing_price': listingPrice,
      'bid_amount': bidAmount,
      'status': status,
      'created_at': createdAt,
      'response_message': responseMessage,
      'response_date': responseDate,
      'user_id': userId,
    };
  }
}

// Model for Poll Property
class PollProperty {
  final String id;
  final String title;
  final String location;
  final String imageUrl;
  final List<Map<String, dynamic>> suggestions;

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

// Investment Model
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

// Handler for POST /properties endpoint
Future<Response> handlePostProperty(Request request, PostgreSQLConnection connection) async {
  try {
    final payload = await request.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));

    // Extract all expected fields
    final propertyId = data['property_id'];
    final title = data['title'];
    final price = data['price'];
    final location = data['location'];
    final category = data['category'];
    final userId = data['user_id'];
    final description = data['description'];
    final condition = data['condition'];
    final quantity = data['quantity'];
    final type = data['type'];
    final address = data['address'];
    final listerName = data['lister_name'];
    final listerEmail = data['lister_email'];
    final listerWhatsapp = data['lister_whatsapp'];
    final images = data['images'] != null ? jsonEncode(data['images']) : null;
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final isActive = data['is_active'] ?? true;
    final isVerified = data['is_verified'] ?? false;

    // Insert into database
    await connection.query('''
      INSERT INTO properties (
        property_id, title, price, location, category, user_id,
        description, condition, quantity, type, address,
        lister_name, lister_email, lister_whatsapp, images,
        latitude, longitude, is_active, is_verified, created_at, updated_at
      ) VALUES (
        @property_id, @title, @price, @location, @category, @user_id,
        @description, @condition, @quantity, @type, @address,
        @lister_name, @lister_email, @lister_whatsapp, @images,
        @latitude, @longitude, @is_active, @is_verified, NOW(), NOW()
      )
    ''', substitutionValues: {
      'property_id': propertyId,
      'title': title,
      'price': price,
      'location': location,
      'category': category,
      'user_id': userId,
      'description': description,
      'condition': condition,
      'quantity': quantity,
      'type': type,
      'address': address,
      'lister_name': listerName,
      'lister_email': listerEmail,
      'lister_whatsapp': listerWhatsapp,
      'images': images,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
      'is_verified': isVerified,
    });

    return Response.ok(jsonEncode({'status': 'success', 'message': 'Property created successfully'}), headers: {
      'Content-Type': 'application/json',
    });
  } catch (e, stack) {
    print('POST /properties failed: $e\n$stack');
    return Response.internalServerError(body: jsonEncode({
      'status': 'error',
      'message': 'Failed to create property',
      'error': e.toString()
    }));
  }
}

// Paystack API handler functions
Future<Response> handlePaystackInitialize(Request request) async {
  try {
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    final payload = await request.readAsString();
    final requestData = jsonDecode(payload);
    
    if (requestData['email'] == null || requestData['amount'] == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Email and amount are required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    final Map<String, dynamic> paystackData = {
      'email': requestData['email'],
      'amount': requestData['amount'],
      'currency': 'NGN',
      'reference': requestData['reference'] ?? 'MIP${DateTime.now().millisecondsSinceEpoch}',
      'callback_url': requestData['callback_url'] ?? 'https://mipripity-api-1.onrender.com/webhook',
    };
    
    if (requestData['metadata'] != null) {
      paystackData['metadata'] = requestData['metadata'];
    }
    
    final response = await http.post(
      Uri.parse('https://api.paystack.co/transaction/initialize'),
      headers: {
        'Authorization': 'Bearer $paystackSecretKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(paystackData),
    );
    
    final responseData = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      return Response.ok(
        jsonEncode({
          'authorization_url': responseData['data']['authorization_url'],
          'access_code': responseData['data']['access_code'],
          'reference': responseData['data']['reference'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      return Response(
        response.statusCode,
        body: jsonEncode({
          'error': responseData['message'] ?? 'Failed to initialize transaction',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e) {
    print('Paystack initialize error: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'An unexpected error occurred'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> handlePaystackVerify(Request request) async {
  try {
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    final payload = await request.readAsString();
    final requestData = jsonDecode(payload);
    
    if (requestData['reference'] == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Transaction reference is required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    final reference = requestData['reference'];
    
    final response = await http.get(
      Uri.parse('https://api.paystack.co/transaction/verify/$reference'),
      headers: {
        'Authorization': 'Bearer $paystackSecretKey',
        'Content-Type': 'application/json',
      },
    );
    
    final responseData = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      final status = responseData['data']['status'];
      final isSuccess = status == 'success';
      
      if (isSuccess) {
        print('Payment successful: $reference');
        
        if (requestData['property_id'] != null) {
          print('Payment for property: ${requestData['property_id']}');
        }
      }
      
      return Response.ok(
        jsonEncode({
          'verified': isSuccess,
          'status': status,
          'amount': responseData['data']['amount'],
          'transaction_date': responseData['data']['transaction_date'],
          'reference': reference,
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      return Response(
        response.statusCode,
        body: jsonEncode({
          'error': responseData['message'] ?? 'Failed to verify transaction',
        }),
        headers: {'Content-Type': 'application/json'},
      );
    }
  } catch (e) {
    print('Paystack verify error: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'An unexpected error occurred'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

Future<Response> handlePaystackWebhook(Request request) async {
  try {
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    final signature = request.headers['x-paystack-signature'];
    final payload = await request.readAsString();
    final eventData = jsonDecode(payload);
    
    final event = eventData['event'];
    
    if (event == 'charge.success') {
      final data = eventData['data'];
      final reference = data['reference'];
      final amount = data['amount'];
      final status = data['status'];
      
      print('Webhook: Successful payment - Reference: $reference, Amount: $amount, Status: $status');
    }
    
    return Response.ok(
      jsonEncode({'status': 'success'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Paystack webhook error: $e');
    return Response.ok(
      jsonEncode({'status': 'error', 'message': 'Error processing webhook'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}

// Image upload handler for Cloudinary with Replicate Real-ESRGAN enhancement
Future<Response> handleUploadImage(Request request) async {
  try {
    final boundary = request.headers['content-type']?.split('boundary=').last;
    if (boundary == null) {
      return Response.badRequest(body: jsonEncode({'error': 'No boundary found in content-type'}));
    }
    
    final transformer = MimeMultipartTransformer(boundary);
    final parts = await transformer.bind(request.read()).toList();

    for (final part in parts) {
      final contentDisposition = part.headers['content-disposition'];
      if (contentDisposition != null && contentDisposition.contains('filename=')) {
        final fileBytes = await part.toList();
        final fullBytes = fileBytes.expand((e) => e).toList();
        
        // Step 1: Upload to Cloudinary temporarily
        final cloudinaryUploadUri = Uri.parse('https://api.cloudinary.com/v1_1/dxhrlaz6j/image/upload');
        final cloudinaryUpload = http.MultipartRequest('POST', cloudinaryUploadUri)
          ..fields['upload_preset'] = 'mipripity'
          ..files.add(http.MultipartFile.fromBytes('file', fullBytes, filename: 'original.jpg'));
        
        final cloudinaryResponse = await cloudinaryUpload.send();
        final cloudinaryResult = await cloudinaryResponse.stream.bytesToString();
        final cloudinaryData = jsonDecode(cloudinaryResult);
        final originalImageUrl = cloudinaryData['secure_url'];
        
        if (originalImageUrl == null) {
          return Response.internalServerError(body: jsonEncode({'error': 'Cloudinary upload failed'}));
        }

        // Step 2: Enhance with Replicate Real-ESRGAN
        final replicateToken = 'Token r8_Q5kyvZPZ5Q0c1oyFB1W8MxLvSgK1PmH0ubyMd';
        final replicateResponse = await http.post(
          Uri.parse('https://api.replicate.com/v1/predictions'),
          headers: {
            'Authorization': replicateToken,
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'version': 'db21e45a3f647123bfdfdfb503e6c43c20404983c5d3c99c06a2c7a7afcddb6c',
            'input': {
              'image': originalImageUrl,
              'scale': 2
            },
          }),
        );

        if (replicateResponse.statusCode != 201) {
          return Response.internalServerError(body: replicateResponse.body);
        }

        final replicateData = jsonDecode(replicateResponse.body);
        final getResultUrl = replicateData['urls']['get'];

        // Step 3: Poll Replicate until enhancement completes
        for (int i = 0; i < 10; i++) {
          final statusResponse = await http.get(
            Uri.parse(getResultUrl),
            headers: {'Authorization': replicateToken},
          );
          final statusData = jsonDecode(statusResponse.body);
          
          if (statusData['status'] == 'succeeded') {
            final enhancedImageUrl = statusData['output'];
            return Response.ok(jsonEncode({
              'status': 'success',
              'url': enhancedImageUrl,
            }), headers: {'Content-Type': 'application/json'});
          }
          await Future.delayed(Duration(seconds: 2));
        }

        return Response.internalServerError(body: jsonEncode({'error': 'Replicate enhancement timed out'}));
      }
    }

    return Response.badRequest(body: jsonEncode({'error': 'No file found'}));
  } catch (e) {
    return Response.internalServerError(body: jsonEncode({'error': e.toString()}));
  }
}

// Database migrations function
Future<void> _applyMigrations() async {
  PostgreSQLConnection? db;
  try {
    db = await DatabaseHelper.connect();
    print('Connected to database successfully for migrations');

    // Create poll_properties table
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

    // Create poll_suggestions table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS poll_suggestions (
        id UUID PRIMARY KEY,
        poll_property_id UUID,
        suggestion TEXT NOT NULL,
        votes INTEGER DEFAULT 0,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create poll_user_votes table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS poll_user_votes (
        id UUID PRIMARY KEY,
        user_id TEXT NOT NULL,
        suggestion TEXT NOT NULL,
        poll_property_id UUID,
        voted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

    // Create bids table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS bids (
        id TEXT PRIMARY KEY,
        listing_id TEXT NOT NULL,
        listing_title TEXT NOT NULL,
        listing_image TEXT NOT NULL,
        listing_category TEXT NOT NULL,
        listing_location TEXT NOT NULL,
        listing_price REAL NOT NULL,
        bid_amount REAL NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        response_message TEXT,
        response_date TIMESTAMP,
        user_id TEXT NOT NULL
      )
    ''');

    // Check if financial_data table exists
    final financialTableExists = await db.mappedResultsQuery("""
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_name = 'user_financial_data'
    """);
    
    if (financialTableExists.isEmpty) {
      // Create user_financial_data table with income_start_timestamp
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_financial_data (
          id SERIAL PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id),
          monthly_income DECIMAL(15, 2) DEFAULT 0,
          income_start_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
          total_funds DECIMAL(15, 2) DEFAULT 0,
          total_bids DECIMAL(15, 2) DEFAULT 0,
          total_interests DECIMAL(15, 2) DEFAULT 0,
          income_breakdown JSONB DEFAULT '{}'::jsonb,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id)
        )
      ''');
      print('Created user_financial_data table with income_start_timestamp');
    } else {
      // Check if income_start_timestamp column exists, add it if it doesn't
      final timestampExists = await db.mappedResultsQuery("""
        SELECT column_name 
        FROM information_schema.columns 
        WHERE table_name = 'user_financial_data'
          AND column_name = 'income_start_timestamp'
      """);
      
      if (timestampExists.isEmpty) {
        await db.execute('''
          ALTER TABLE user_financial_data 
          ADD COLUMN income_start_timestamp TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
        ''');
        print('Added income_start_timestamp column to user_financial_data table');
      }
    }

    // Create transactions table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS financial_transactions (
        id UUID PRIMARY KEY,
        user_id INTEGER NOT NULL REFERENCES users(id),
        transaction_type VARCHAR(20) NOT NULL,
        amount DECIMAL(15, 2) NOT NULL,
        description TEXT,
        status VARCHAR(20) DEFAULT 'completed',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
      )
    ''');

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

    print('Database tables created successfully');
  } catch (e) {
    print('Error creating database tables: $e');
  } finally {
    await db?.close();
  }
}

// Investment functions
Future<Response> fetchInvestments(Request req) async {
  PostgreSQLConnection? db;
  try {
    db = await DatabaseHelper.connect();
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
    await db?.close();
  }
}

Future<Response> createInvestment(Request req) async {
  PostgreSQLConnection? db;
  final uuid = Uuid();
  try {
    db = await DatabaseHelper.connect();
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
    await db?.close();
  }
}

void main() async {
  // Apply database migrations
  await _applyMigrations();

  // Initialize database connection
  PostgreSQLConnection db = await DatabaseHelper.connect();

  final router = Router();

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

  // Helper to safely parse numeric values to double
  double _parseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (_) {
        return 0.0;
      }
    }
    return 0.0;
  }

  // CORS helper function
  Response _cors(Response response) => response.change(
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
    },
  );

  // CORS preflight handler
  router.options('/<path|.*>', (Request request, String path) {
    return _cors(Response.ok(''));
  });

  // Helper functions for bid and listing counts
  Future<Map<String, int>> getBidCounts(int userId) async {
    try {
      final results = await db.query('''
        SELECT status, COUNT(*) as count
        FROM bids
        WHERE user_id = @user_id
        GROUP BY status
      ''', substitutionValues: {'user_id': userId.toString()});

      final counts = <String, int>{
        'pending': 0,
        'accepted': 0,
        'rejected': 0,
        'expired': 0,
      };

      for (final row in results) {
        final status = row[0] as String;
        final count = row[1] as int;
        counts[status] = count;
      }

      return counts;
    } catch (e) {
      print('Error getting bid counts: $e');
      return {'pending': 0, 'accepted': 0, 'rejected': 0, 'expired': 0};
    }
  }

  Future<Map<String, int>> getListingCounts(int userId) async {
    try {
      final results = await db.query('''
        SELECT 
          COUNT(*) as all_count,
          COUNT(CASE WHEN is_active = true AND status = 'active' THEN 1 END) as active_count,
          COUNT(CASE WHEN status = 'pending' THEN 1 END) as pending_count,
          COUNT(CASE WHEN status = 'sold' OR status = 'archive' THEN 1 END) as archive_count
        FROM properties
        WHERE user_id = @user_id
      ''', substitutionValues: {'user_id': userId});

      if (results.isNotEmpty) {
        final row = results.first;
        return {
          'all': row[0] as int,
          'active': row[1] as int,
          'pending': row[2] as int,
          'archive': row[3] as int,
        };
      }

      return {'all': 0, 'active': 0, 'pending': 0, 'archive': 0};
    } catch (e) {
      print('Error getting listing counts: $e');
      return {'all': 0, 'active': 0, 'pending': 0, 'archive': 0};
    }
  }

  Future<List<Map<String, dynamic>>> getRecentTransactions(int userId, {int limit = 5}) async {
    try {
      final results = await db.query('''
        SELECT id, transaction_type, amount, description, status, created_at
        FROM financial_transactions
        WHERE user_id = @user_id
        ORDER BY created_at DESC
        LIMIT @limit
      ''', substitutionValues: {'user_id': userId, 'limit': limit});

      return results.map((row) {
        return {
          'id': row[0],
          'transaction_type': row[1],
          'amount': _parseDouble(row[2]),
          'description': row[3] ?? '',
          'status': row[4] ?? 'completed',
          'created_at': (row[5] as DateTime).toIso8601String(),
        };
      }).toList();
    } catch (e) {
      print('Error getting recent transactions: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getFavoriteListings(int userId, {int limit = 5}) async {
    try {
      // For now, return sample data since favorites table doesn't exist yet
      return [
        {
          'id': '1',
          'title': 'Modern Apartment',
          'price': 2500000.0,
          'image_url': 'assets/images/mipripity.png',
          'category': 'residential',
          'location': 'Lagos',
        },
        {
          'id': '2',
          'title': 'Commercial Space',
          'price': 5000000.0,
          'image_url': 'assets/images/mipripity.png',
          'category': 'commercial',
          'location': 'Abuja',
        },
      ];
    } catch (e) {
      print('Error getting favorite listings: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPropertyRecommendations(int userId, {int limit = 5}) async {
    try {
      // For now, return sample data since AI recommendations don't exist yet
      return [
        {
          'id': '1',
          'title': 'Luxury Villa',
          'price': 15000000.0,
          'image_url': 'assets/images/mipripity.png',
          'category': 'residential',
          'location': 'Victoria Island',
          'match_percentage': 95.0,
        },
        {
          'id': '2',
          'title': 'Office Complex',
          'price': 25000000.0,
          'image_url': 'assets/images/mipripity.png',
          'category': 'commercial',
          'location': 'Ikoyi',
          'match_percentage': 88.0,
        },
      ];
    } catch (e) {
      print('Error getting property recommendations: $e');
      return [];
    }
  }

  // Enhanced financial dashboard endpoint
  router.get('/users/id/<userId>/financial-dashboard', (Request request, String userId) async {
    try {
      final userIdInt = int.parse(userId);
      
      // Get user financial data
      final financialResults = await db.query('''
        SELECT monthly_income, income_start_timestamp, total_funds, total_bids, total_interests, income_breakdown
        FROM user_financial_data
        WHERE user_id = @user_id
      ''', substitutionValues: {'user_id': userIdInt});

      double monthlyIncome = 0.0;
      DateTime? incomeStartTimestamp;
      double totalFunds = 0.0;
      double totalBids = 0.0;
      double totalInterests = 0.0;
      Map<String, double> incomeBreakdown = {};

      if (financialResults.isNotEmpty) {
        final row = financialResults.first;
        monthlyIncome = _parseDouble(row[0]);
        incomeStartTimestamp = row[1] as DateTime?;
        totalFunds = _parseDouble(row[2]);
        totalBids = _parseDouble(row[3]);
        totalInterests = _parseDouble(row[4]);
        
        if (row[5] != null) {
          final breakdown = jsonDecode(row[5] as String) as Map<String, dynamic>;
          incomeBreakdown = breakdown.map((k, v) => MapEntry(k, _parseDouble(v)));
        }
      }

      // Get bid and listing counts
      final bidCounts = await getBidCounts(userIdInt);
      final listingCounts = await getListingCounts(userIdInt);

      // Get recent transactions
      final recentTransactions = await getRecentTransactions(userIdInt);

      // Get favorite listings
      final favoriteListings = await getFavoriteListings(userIdInt);

      // Get property recommendations
      final recommendations = await getPropertyRecommendations(userIdInt);

      // Calculate expense breakdown
      final expenseBreakdown = {
        'Bids': totalBids,
        'Purchases': 0.0,
        'Withdrawals': 0.0,
      };

      // If no income breakdown exists, create default one
      if (incomeBreakdown.isEmpty && monthlyIncome > 0) {
        incomeBreakdown = {
          'Salary': monthlyIncome * 0.8,
          'Investment': monthlyIncome * 0.1,
          'Other': monthlyIncome * 0.1,
        };
      }

      final dashboardData = {
        'total_funds': totalFunds,
        'monthly_income': monthlyIncome,
        'income_start_timestamp': incomeStartTimestamp?.toIso8601String(),
        'total_bids': totalBids,
        'total_interests': totalInterests,
        'total_expenses': totalBids, // For now, expenses are just bids
        'recent_transactions': recentTransactions,
        'active_bids': [], // Will be populated from bids table if needed
        'favorite_listings': favoriteListings,
        'my_listings': [], // Will be populated from properties table if needed
        'recommendations': recommendations,
        'income_breakdown': incomeBreakdown,
        'expense_breakdown': expenseBreakdown,
        'bid_counts': bidCounts,
        'listing_counts': listingCounts,
      };

      return _cors(Response.ok(
        jsonEncode(dashboardData),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching financial dashboard: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch financial dashboard data'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // User income endpoint
  router.post('/user/income', (Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final userId = data['user_id'];
      final amount = _parseDouble(data['amount']);
      final startTimestamp = data['start_timestamp'] != null 
          ? DateTime.parse(data['start_timestamp'])
          : DateTime.now();

      // Insert or update user financial data
      await db.execute('''
        INSERT INTO user_financial_data (user_id, monthly_income, income_start_timestamp, updated_at)
        VALUES (@user_id, @amount, @start_timestamp, CURRENT_TIMESTAMP)
        ON CONFLICT (user_id) 
        DO UPDATE SET 
          monthly_income = @amount,
          income_start_timestamp = @start_timestamp,
          updated_at = CURRENT_TIMESTAMP
      ''', substitutionValues: {
        'user_id': userId,
        'amount': amount,
        'start_timestamp': startTimestamp,
      });

      return _cors(Response.ok(
        jsonEncode({'status': 'success', 'message': 'Income updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error updating user income: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update income'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Bid counts endpoint
  router.get('/users/<userId>/bids/counts', (Request request, String userId) async {
    try {
      final userIdInt = int.parse(userId);
      final counts = await getBidCounts(userIdInt);
      
      return _cors(Response.ok(
        jsonEncode(counts),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching bid counts: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch bid counts'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // User bids endpoint
  router.get('/users/<userId>/bids', (Request request, String userId) async {
    try {
      final userIdInt = int.parse(userId);
      final status = request.url.queryParameters['status'];
      
      String query = '''
        SELECT id, listing_id, listing_title, listing_image, listing_category, 
               listing_location, listing_price, bid_amount, status, created_at,
               response_message, response_date, user_id
        FROM bids
        WHERE user_id = @user_id
      ''';
      
      Map<String, dynamic> substitutionValues = {'user_id': userId};
      
      if (status != null && status.isNotEmpty) {
        query += ' AND status = @status';
        substitutionValues['status'] = status;
      }
      
      query += ' ORDER BY created_at DESC';
      
      final results = await db.query(query, substitutionValues: substitutionValues);
      
      final bids = results.map((row) {
        return {
          'id': row[0],
          'listing_id': row[1],
          'listing_title': row[2],
          'listing_image': row[3],
          'listing_category': row[4],
          'listing_location': row[5],
          'listing_price': _parseDouble(row[6]),
          'bid_amount': _parseDouble(row[7]),
          'status': row[8],
          'created_at': (row[9] as DateTime).toIso8601String(),
          'response_message': row[10],
          'response_date': row[11] != null ? (row[11] as DateTime).toIso8601String() : null,
          'user_id': row[12],
        };
      }).toList();
      
      return _cors(Response.ok(
        jsonEncode(bids),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching user bids: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch user bids'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Listing counts endpoint
  router.get('/users/<userId>/listings/counts', (Request request, String userId) async {
    try {
      final userIdInt = int.parse(userId);
      final counts = await getListingCounts(userIdInt);
      
      return _cors(Response.ok(
        jsonEncode(counts),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching listing counts: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch listing counts'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // User listings endpoint
  router.get('/users/<userId>/listings', (Request request, String userId) async {
    try {
      final userIdInt = int.parse(userId);
      final status = request.url.queryParameters['status'];
      
      String query = '''
        SELECT property_id, title, price, location, category, user_id, description,
               condition, quantity, type, address, lister_name, lister_email,
               lister_whatsapp, images, latitude, longitude, is_active, is_verified,
               status, created_at, updated_at
        FROM properties
        WHERE user_id = @user_id
      ''';
      
      Map<String, dynamic> substitutionValues = {'user_id': userIdInt};
      
      if (status != null && status.isNotEmpty && status != 'all') {
        if (status == 'active') {
          query += ' AND is_active = true AND status = \'active\'';
        } else if (status == 'archive') {
          query += ' AND (status = \'sold\' OR status = \'archive\')';
        } else {
          query += ' AND status = @status';
          substitutionValues['status'] = status;
        }
      }
      
      query += ' ORDER BY created_at DESC';
      
      final results = await db.query(query, substitutionValues: substitutionValues);
      
      final listings = results.map((row) {
        List<String> imagesList = [];
        if (row[14] != null) {
          try {
            final decoded = jsonDecode(row[14] as String);
            if (decoded is List) {
              imagesList = decoded.cast<String>();
            }
          } catch (e) {
            print('Error parsing images JSON: $e');
          }
        }

        return {
          'id': row[0],
          'property_id': row[0],
          'title': row[1],
          'price': _parseDouble(row[2]),
          'location': row[3],
          'category': row[4],
          'user_id': row[5],
          'description': row[6],
          'condition': row[7],
          'quantity': row[8],
          'type': row[9],
          'address': row[10],
          'lister_name': row[11],
          'lister_email': row[12],
          'lister_whatsapp': row[13],
          'images': imagesList,
          'latitude': row[15] != null ? _parseDouble(row[15]) : null,
          'longitude': row[16] != null ? _parseDouble(row[16]) : null,
          'is_active': row[17] ?? false,
          'is_verified': row[18] ?? false,
          'status': row[19] ?? 'active',
          'created_at': (row[20] as DateTime).toIso8601String(),
          'updated_at': (row[21] as DateTime).toIso8601String(),
        };
      }).toList();
      
      return _cors(Response.ok(
        jsonEncode(listings),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching user listings: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch user listings'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Create bid endpoint
  router.post('/bids', (Request request) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final bidId = Uuid().v4();
      final userId = data['user_id'].toString();
      final listingId = data['listing_id'];
      final bidAmount = _parseDouble(data['bid_amount']);
      final message = data['message'];
      final status = data['status'] ?? 'pending';
      
      // Get listing details
      final listingResults = await db.query('''
        SELECT title, price, category, location, images
        FROM properties
        WHERE property_id = @listing_id
      ''', substitutionValues: {'listing_id': listingId});
      
      if (listingResults.isEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'Listing not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      
      final listing = listingResults.first;
      String listingImage = 'assets/images/mipripity.png';
      
      if (listing[4] != null) {
        try {
          final images = jsonDecode(listing[4] as String) as List;
          if (images.isNotEmpty) {
            listingImage = images.first.toString();
          }
        } catch (e) {
          print('Error parsing listing images: $e');
        }
      }
      
      // Insert bid
      await db.execute('''
        INSERT INTO bids (
          id, listing_id, listing_title, listing_image, listing_category,
          listing_location, listing_price, bid_amount, status, created_at,
          response_message, user_id
        ) VALUES (
          @id, @listing_id, @listing_title, @listing_image, @listing_category,
          @listing_location, @listing_price, @bid_amount, @status, CURRENT_TIMESTAMP,
          @message, @user_id
        )
      ''', substitutionValues: {
        'id': bidId,
        'listing_id': listingId,
        'listing_title': listing[0],
        'listing_image': listingImage,
        'listing_category': listing[2],
        'listing_location': listing[3],
        'listing_price': _parseDouble(listing[1]),
        'bid_amount': bidAmount,
        'status': status,
        'message': message,
        'user_id': userId,
      });
      
      return _cors(Response.ok(
        jsonEncode({'id': bidId, 'status': 'success', 'message': 'Bid created successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error creating bid: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create bid'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Update bid status endpoint
  router.patch('/bids/<bidId>/status', (Request request, String bidId) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final status = data['status'];
      final message = data['message'];
      
      await db.execute('''
        UPDATE bids
        SET status = @status, response_message = @message, response_date = CURRENT_TIMESTAMP
        WHERE id = @bid_id
      ''', substitutionValues: {
        'status': status,
        'message': message,
        'bid_id': bidId,
      });
      
      return _cors(Response.ok(
        jsonEncode({'status': 'success', 'message': 'Bid status updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error updating bid status: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update bid status'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Delete bid endpoint
  router.delete('/bids/<bidId>', (Request request, String bidId) async {
    try {
      await db.execute('''
        DELETE FROM bids WHERE id = @bid_id
      ''', substitutionValues: {'bid_id': bidId});
      
      return _cors(Response.ok(
        jsonEncode({'status': 'success', 'message': 'Bid deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error deleting bid: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete bid'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Get bid by ID endpoint
  router.get('/bids/<bidId>', (Request request, String bidId) async {
    try {
      final results = await db.query('''
        SELECT id, listing_id, listing_title, listing_image, listing_category,
               listing_location, listing_price, bid_amount, status, created_at,
               response_message, response_date, user_id
        FROM bids
        WHERE id = @bid_id
      ''', substitutionValues: {'bid_id': bidId});
      
      if (results.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'Bid not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      
      final row = results.first;
      final bid = {
        'id': row[0],
        'listing_id': row[1],
        'listing_title': row[2],
        'listing_image': row[3],
        'listing_category': row[4],
        'listing_location': row[5],
        'listing_price': _parseDouble(row[6]),
        'bid_amount': _parseDouble(row[7]),
        'status': row[8],
        'created_at': (row[9] as DateTime).toIso8601String(),
        'response_message': row[10],
        'response_date': row[11] != null ? (row[11] as DateTime).toIso8601String() : null,
        'user_id': row[12],
      };
      
      return _cors(Response.ok(
        jsonEncode(bid),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching bid: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch bid'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Get bids for a listing endpoint
  router.get('/listings/<listingId>/bids', (Request request, String listingId) async {
    try {
      final results = await db.query('''
        SELECT id, listing_id, listing_title, listing_image, listing_category,
               listing_location, listing_price, bid_amount, status, created_at,
               response_message, response_date, user_id
        FROM bids
        WHERE listing_id = @listing_id
        ORDER BY created_at DESC
      ''', substitutionValues: {'listing_id': listingId});
      
      final bids = results.map((row) {
        return {
          'id': row[0],
          'listing_id': row[1],
          'listing_title': row[2],
          'listing_image': row[3],
          'listing_category': row[4],
          'listing_location': row[5],
          'listing_price': _parseDouble(row[6]),
          'bid_amount': _parseDouble(row[7]),
          'status': row[8],
          'created_at': (row[9] as DateTime).toIso8601String(),
          'response_message': row[10],
          'response_date': row[11] != null ? (row[11] as DateTime).toIso8601String() : null,
          'user_id': row[12],
        };
      }).toList();
      
      return _cors(Response.ok(
        jsonEncode(bids),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching listing bids: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch listing bids'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Update listing status endpoint
  router.patch('/properties/<listingId>/status', (Request request, String listingId) async {
    try {
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      final status = data['status'];
      
      await db.execute('''
        UPDATE properties
        SET status = @status, updated_at = CURRENT_TIMESTAMP
        WHERE property_id = @listing_id
      ''', substitutionValues: {
        'status': status,
        'listing_id': listingId,
      });
      
      return _cors(Response.ok(
        jsonEncode({'status': 'success', 'message': 'Listing status updated successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error updating listing status: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update listing status'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Delete listing endpoint
  router.delete('/properties/<listingId>', (Request request, String listingId) async {
    try {
      await db.execute('''
        DELETE FROM properties WHERE property_id = @listing_id
      ''', substitutionValues: {'listing_id': listingId});
      
      return _cors(Response.ok(
        jsonEncode({'status': 'success', 'message': 'Listing deleted successfully'}),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error deleting listing: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to delete listing'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Get listing by ID endpoint
  router.get('/properties/<listingId>', (Request request, String listingId) async {
    try {
      final results = await db.query('''
        SELECT property_id, title, price, location, category, user_id, description,
               condition, quantity, type, address, lister_name, lister_email,
               lister_whatsapp, images, latitude, longitude, is_active, is_verified,
               status, created_at, updated_at
        FROM properties
        WHERE property_id = @listing_id
      ''', substitutionValues: {'listing_id': listingId});
      
      if (results.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'Listing not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      
      final row = results.first;
      List<String> imagesList = [];
      if (row[14] != null) {
        try {
          final decoded = jsonDecode(row[14] as String);
          if (decoded is List) {
            imagesList = decoded.cast<String>();
          }
        } catch (e) {
          print('Error parsing images JSON: $e');
        }
      }

      final listing = {
        'id': row[0],
        'property_id': row[0],
        'title': row[1],
        'price': _parseDouble(row[2]),
        'location': row[3],
        'category': row[4],
        'user_id': row[5],
        'description': row[6],
        'condition': row[7],
        'quantity': row[8],
        'type': row[9],
        'address': row[10],
        'lister_name': row[11],
        'lister_email': row[12],
        'lister_whatsapp': row[13],
        'images': imagesList,
        'latitude': row[15] != null ? _parseDouble(row[15]) : null,
        'longitude': row[16] != null ? _parseDouble(row[16]) : null,
        'is_active': row[17] ?? false,
        'is_verified': row[18] ?? false,
        'status': row[19] ?? 'active',
        'created_at': (row[20] as DateTime).toIso8601String(),
        'updated_at': (row[21] as DateTime).toIso8601String(),
      };
      
      return _cors(Response.ok(
        jsonEncode(listing),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error fetching listing: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch listing'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Search listings endpoint
  router.get('/properties/search', (Request request) async {
    try {
      final query = request.url.queryParameters['q'] ?? '';
      
      if (query.isEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'Search query is required'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      
      final results = await db.query('''
        SELECT property_id, title, price, location, category, user_id, description,
               condition, quantity, type, address, lister_name, lister_email,
               lister_whatsapp, images, latitude, longitude, is_active, is_verified,
               status, created_at, updated_at
        FROM properties
        WHERE (title ILIKE @query OR description ILIKE @query OR location ILIKE @query)
          AND is_active = true
        ORDER BY created_at DESC
      ''', substitutionValues: {'query': '%$query%'});
      
      final listings = results.map((row) {
        List<String> imagesList = [];
        if (row[14] != null) {
          try {
            final decoded = jsonDecode(row[14] as String);
            if (decoded is List) {
              imagesList = decoded.cast<String>();
            }
          } catch (e) {
            print('Error parsing images JSON: $e');
          }
        }

        return {
          'id': row[0],
          'property_id': row[0],
          'title': row[1],
          'price': _parseDouble(row[2]),
          'location': row[3],
          'category': row[4],
          'user_id': row[5],
          'description': row[6],
          'condition': row[7],
          'quantity': row[8],
          'type': row[9],
          'address': row[10],
          'lister_name': row[11],
          'lister_email': row[12],
          'lister_whatsapp': row[13],
          'images': imagesList,
          'latitude': row[15] != null ? _parseDouble(row[15]) : null,
          'longitude': row[16] != null ? _parseDouble(row[16]) : null,
          'is_active': row[17] ?? false,
          'is_verified': row[18] ?? false,
          'status': row[19] ?? 'active',
          'created_at': (row[20] as DateTime).toIso8601String(),
          'updated_at': (row[21] as DateTime).toIso8601String(),
        };
      }).toList();
      
      return _cors(Response.ok(
        jsonEncode(listings),
        headers: {'Content-Type': 'application/json'},
      ));
    } catch (e) {
      print('Error searching listings: $e');
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Failed to search listings'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Existing endpoints...
  router.get('/properties', (Request req) async {
    try {
      final results = await db.query('SELECT * FROM properties ORDER BY created_at DESC');
      final properties = results.map((row) {
        final map = Map.fromIterables(
          results.columnDescriptions.map((c) => c.columnName),
          row,
        );
        return _convertDateTimes(map);
      }).toList();
      
      return _cors(Response.ok(jsonEncode(properties), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching properties: $e'}),
      ));
    }
  });

  router.post('/properties', (Request req) async {
    return _cors(await handlePostProperty(req, db));
  });

  // Get property by ID
  router.get('/properties/<propertyId>', (Request req, String propertyId) async {
    try {
      final results = await db.query('''
        SELECT * FROM properties WHERE property_id = @property_id
      ''', substitutionValues: {'property_id': propertyId});
      if (results.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'Property not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      final row = results.first;
      final map = Map.fromIterables(
        results.columnDescriptions.map((c) => c.columnName),
        row,
      );
      final property = _convertDateTimes(map);
      return _cors(Response.ok(jsonEncode(property), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching property: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  //Get properties by category
  router.get('/properties/category/<category>', (Request req, String category) async {
    try {
      final results = await db.query('''
        SELECT * FROM properties WHERE category = @category ORDER BY created_at DESC
      ''', substitutionValues: {'category': category});
      final properties = results.map((row) {
        final map = Map.fromIterables(
          results.columnDescriptions.map((c) => c.columnName),
          row,
        );
        return _convertDateTimes(map);
      }).toList();
      
      return _cors(Response.ok(jsonEncode(properties), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching properties by category: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  //Get user by email
  router.get('/users/email/<email>', (Request req, String email) async {
    try {
      final results = await db.query('''
        SELECT * FROM users WHERE email = @user_email
      ''', substitutionValues: {'user_email': email});
      if (results.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      final row = results.first;
      final map = Map.fromIterables(
        results.columnDescriptions.map((c) => c.columnName),
        row,
      );
      final user = {
        'id': map['id'],
        'name': map['name'],
        'email': map['email'],
        'phone': map['phone'],
        'created_at': (map['created_at'] as DateTime).toIso8601String(),
        'updated_at': (map['updated_at'] as DateTime).toIso8601String(),
      };
      return _cors(Response.ok(jsonEncode(user), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching user by email: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  //Get user by ID
  router.get('/users/<userId>', (Request req, String userId) async {
    try {
      final results = await db.query('''
        SELECT * FROM users WHERE id = @user_id
      ''', substitutionValues: {'user_id': userId});
      if (results.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'User not found'}),
          headers: {'Content-Type': 'application/json'},
        ));
      }
      final row = results.first;
      final map = Map.fromIterables(
        results.columnDescriptions.map((c) => c.columnName),
        row,
      );
      final user = {
        'id': map['id'],
        'name': map['name'],
        'email': map['email'],
        'phone': map['phone'],
        'created_at': (map['created_at'] as DateTime).toIso8601String(),
        'updated_at': (map['updated_at'] as DateTime).toIso8601String(),
      };
      return _cors(Response.ok(jsonEncode(user), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching user by ID: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // User endpoints
  router.get('/users', (Request req) async {
    try {
      final results = await db.query('SELECT * FROM users ORDER BY created_at DESC');
      final users = results.map((row) {
        final map = Map.fromIterables(
          results.columnDescriptions.map((c) => c.columnName),
          row,
        );
        return {
          'id': map['id'],
          'name': map['name'],
          'email': map['email'],
          'phone': map['phone'],
          'created_at': (map['created_at'] as DateTime).toIso8601String(),
          'updated_at': (map['updated_at'] as DateTime).toIso8601String(),
        };
      }).toList();
      return _cors(Response.ok(jsonEncode(users), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching users: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  router.post('/users', (Request req) async {
    try {
      final body = await req.readAsString();
      final userData = jsonDecode(body);
      final id = Uuid().v4();
      final name = userData['name'];
      final email = userData['email'];
      final phone = userData['phone'];
      final createdAt = DateTime.now().toIso8601String();
      await db.execute('''
        INSERT INTO users (id, name, email, phone, created_at)
        VALUES (@id, @name, @user_email, @phone, @created_at)
      ''', substitutionValues: {
        'id': id,
        'name': name,
        'user_email': email,
        'phone': phone,
        'created_at': createdAt,
      });
      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'User created successfully',
        'id': id,
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error creating user: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });
  router.patch('/users/<userId>', (Request req, String userId) async {
    try {
      final body = await req.readAsString();
      final userData = jsonDecode(body);
      final name = userData['name'];
      final email = userData['email'];
      final phone = userData['phone'];
      
      await db.execute('''
        UPDATE users
        SET name = @name, email = @user_email, phone = @phone, updated_at = CURRENT_TIMESTAMP
        WHERE id = @user_id
      ''', substitutionValues: {
        'name': name,
        'user_email': email,
        'phone': phone,
        'user_id': userId,
      });
      
      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'User updated successfully',
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error updating user: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  router.delete('/users/<userId>', (Request req, String userId) async {
    try {
      await db.execute('''
        DELETE FROM users WHERE id = @user_id
      ''', substitutionValues: {'user_id': userId});
      
      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'User deleted successfully',
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error deleting user: $e'}),
        headers: {'Content-Type': 'application/json'},
      ));
    }
  });

  // Poll properties endpoints
  router.get('/poll-properties', (Request req) async {
    try {
      final results = await db.query('SELECT * FROM poll_properties ORDER BY created_at DESC');
      final pollProperties = results.map((row) {
        final map = Map.fromIterables(
          results.columnDescriptions.map((c) => c.columnName),
          row,
        );
        
        // Parse suggestions JSON
        List<Map<String, dynamic>> suggestions = [];
        if (map['suggestions'] != null) {
          try {
            final suggestionsJson = jsonDecode(map['suggestions']);
            if (suggestionsJson is List) {
              suggestions = suggestionsJson.cast<Map<String, dynamic>>();
            }
          } catch (e) {
            print('Error parsing suggestions: $e');
          }
        }
        
        return PollProperty(
          id: map['id'],
          title: map['title'],
          location: map['location'],
          imageUrl: map['image_url'],
          suggestions: suggestions,
        ).toJson();
      }).toList();
      
      return _cors(Response.ok(jsonEncode(pollProperties), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching poll properties: $e'}),
      ));
    }
  });

  router.post('/poll-properties', (Request req) async {
    try {
      final body = await req.readAsString();
      final pollData = jsonDecode(body);
      
      final id = Uuid().v4();
      final title = pollData['title'];
      final location = pollData['location'];
      final imageUrl = pollData['image_url'];
      final suggestions = jsonEncode(pollData['suggestions'] ?? []);

      await db.execute('''
        INSERT INTO poll_properties (id, title, location, image_url, suggestions)
        VALUES (@id, @title, @location, @image_url, @suggestions)
      ''', substitutionValues: {
        'id': id,
        'title': title,
        'location': location,
        'image_url': imageUrl,
        'suggestions': suggestions,
      });

      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'Poll property created successfully',
        'id': id,
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error creating poll property: $e'}),
      ));
    }
  });

  router.post('/poll-properties/<pollId>/vote', (Request req, String pollId) async {
    try {
      final body = await req.readAsString();
      final voteData = jsonDecode(body);
      
      final userId = voteData['user_id'];
      final suggestion = voteData['suggestion'];

      // Check if user has already voted for this poll
      final existingVote = await db.query('''
        SELECT id FROM poll_user_votes 
        WHERE user_id = @user_id AND poll_property_id = @poll_id
      ''', substitutionValues: {
        'user_id': userId,
        'poll_id': pollId,
      });

      if (existingVote.isNotEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'User has already voted for this poll'}),
        ));
      }

      // Record the vote
      final voteId = Uuid().v4();
      await db.execute('''
        INSERT INTO poll_user_votes (id, user_id, suggestion, poll_property_id)
        VALUES (@id, @user_id, @suggestion, @poll_id)
      ''', substitutionValues: {
        'id': voteId,
        'user_id': userId,
        'suggestion': suggestion,
        'poll_id': pollId,
      });

      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'Vote recorded successfully',
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error recording vote: $e'}),
      ));
    }
  });

  router.get('/poll-properties/<pollId>/results', (Request req, String pollId) async {
    try {
      final results = await db.query('''
        SELECT suggestion, COUNT(*) as vote_count
        FROM poll_user_votes
        WHERE poll_property_id = @poll_id
        GROUP BY suggestion
        ORDER BY vote_count DESC
      ''', substitutionValues: {
        'poll_id': pollId,
      });

      final pollResults = results.map((row) {
        return {
          'suggestion': row[0],
          'votes': row[1],
        };
      }).toList();

      return _cors(Response.ok(jsonEncode(pollResults), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching poll results: $e'}),
      ));
    }
  });

  // Investment endpoints
  router.get('/investments', fetchInvestments);
  router.post('/investments', createInvestment);

  // User endpoints
  router.post('/register', (Request req) async {
    try {
      final body = await req.readAsString();
      final userData = jsonDecode(body);
      
      final firstName = userData['firstName'];
      final lastName = userData['lastName'];
      final email = userData['email'];
      final password = userData['password'];
      final phoneNumber = userData['phoneNumber'];
      final hashedPassword = hashPassword(password);

      // Check if user already exists
      final existingUser = await db.query(
        'SELECT id FROM users WHERE email = @email',
        substitutionValues: {'email': email},
      );

      if (existingUser.isNotEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'User with this email already exists'}),
        ));
      }

      // Insert new user
      await db.execute('''
        INSERT INTO users (first_name, last_name, email, password_hash, phone_number)
        VALUES (@firstName, @lastName, @email, @password, @phoneNumber)
      ''', substitutionValues: {
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'password': hashedPassword,
        'phoneNumber': phoneNumber,
      });

      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'User registered successfully',
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Registration failed: $e'}),
      ));
    }
  });

  router.post('/login', (Request req) async {
    try {
      final body = await req.readAsString();
      final loginData = jsonDecode(body);
      
      final email = loginData['email'];
      final password = loginData['password'];

      // Find user by email
      final userResults = await db.query(
        'SELECT id, first_name, last_name, email, password_hash, phone_number, avatar_url, rc_number, official_agency_name FROM users WHERE email = @email',
        substitutionValues: {'email': email},
      );

      if (userResults.isEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'Invalid email or password'}),
        ));
      }

      final user = userResults.first;
      final storedHash = user[4] as String;

      if (!verifyPassword(password, storedHash)) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'Invalid email or password'}),
        ));
      }

      // Return user data (excluding password)
      final userData = {
        'id': user[0],
        'firstName': user[1],
        'lastName': user[2],
        'email': user[3],
        'phoneNumber': user[5],
        'avatarUrl': user[6],
        'rcNumber': user[7],
        'officialAgencyName': user[8],
      };

      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'Login successful',
        'user': userData,
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Login failed: $e'}),
      ));
    }
  });

  router.get('/users/id/<userId>', (Request req, String userId) async {
    try {
      final userResults = await db.query(
        'SELECT id, first_name, last_name, email, phone_number, avatar_url, rc_number, official_agency_name FROM users WHERE id = @id',
        substitutionValues: {'id': int.parse(userId)},
      );

      if (userResults.isEmpty) {
        return _cors(Response.notFound(
          jsonEncode({'error': 'User not found'}),
        ));
      }

      final user = userResults.first;
      final userData = {
        'id': user[0],
        'firstName': user[1],
        'lastName': user[2],
        'email': user[3],
        'phoneNumber': user[4],
        'avatarUrl': user[5],
        'rcNumber': user[6],
        'officialAgencyName': user[7],
      };

      return _cors(Response.ok(jsonEncode(userData), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error fetching user: $e'}),
      ));
    }
  });

  router.put('/users/id/<userId>', (Request req, String userId) async {
    try {
      final body = await req.readAsString();
      final updateData = jsonDecode(body);
      
      // Build dynamic update query
      final updates = <String>[];
      final substitutionValues = <String, dynamic>{'id': int.parse(userId)};
      
      if (updateData['firstName'] != null) {
        updates.add('first_name = @firstName');
        substitutionValues['firstName'] = updateData['firstName'];
      }
      if (updateData['lastName'] != null) {
        updates.add('last_name = @lastName');
        substitutionValues['lastName'] = updateData['lastName'];
      }
      if (updateData['email'] != null) {
        updates.add('email = @email');
        substitutionValues['email'] = updateData['email'];
      }
      if (updateData['phoneNumber'] != null) {
        updates.add('phone_number = @phoneNumber');
        substitutionValues['phoneNumber'] = updateData['phoneNumber'];
      }
      if (updateData['avatarUrl'] != null) {
        updates.add('avatar_url = @avatarUrl');
        substitutionValues['avatarUrl'] = updateData['avatarUrl'];
      }
      if (updateData['rcNumber'] != null) {
        updates.add('rc_number = @rcNumber');
        substitutionValues['rcNumber'] = updateData['rcNumber'];
      }
      if (updateData['officialAgencyName'] != null) {
        updates.add('official_agency_name = @officialAgencyName');
        substitutionValues['officialAgencyName'] = updateData['officialAgencyName'];
      }

      if (updates.isEmpty) {
        return _cors(Response.badRequest(
          body: jsonEncode({'error': 'No valid fields to update'}),
        ));
      }

      final query = 'UPDATE users SET ${updates.join(', ')} WHERE id = @id';
      await db.execute(query, substitutionValues: substitutionValues);

      return _cors(Response.ok(jsonEncode({
        'status': 'success',
        'message': 'User updated successfully',
      }), headers: {
        'Content-Type': 'application/json',
      }));
    } catch (e) {
      return _cors(Response.internalServerError(
        body: jsonEncode({'error': 'Error updating user: $e'}),
      ));
    }
  });

  // Paystack endpoints
  router.post('/paystack/initialize', handlePaystackInitialize);
  router.post('/paystack/verify', handlePaystackVerify);
  router.post('/webhook', handlePaystackWebhook);

  // Image upload endpoint
  router.post('/upload-image', handleUploadImage);

  // Health check endpoint
  router.get('/health', (Request req) {
    return _cors(Response.ok(jsonEncode({
      'status': 'healthy',
      'timestamp': DateTime.now().toIso8601String(),
    }), headers: {
      'Content-Type': 'application/json',
    }));
  });

  // Start the server
  final ip = InternetAddress.anyIPv4;
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(router, ip, port);
  print('Server listening on port ${server.port}');
}
