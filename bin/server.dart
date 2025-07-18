import 'dart:convert';
import 'dart:io';
import 'package:uuid/uuid.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';
import 'package:mipripity_api/cac_verification.dart';
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
      ...response.headers,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization',
    },
  );

  // Basic routes
  router.get('/', (Request req) async {
    return Response.ok('Mipripity API is running');
  });

  // Paystack endpoints
  router.post('/paystack/initialize', handlePaystackInitialize);
  router.post('/paystack/verify', handlePaystackVerify);
  router.post('/webhook', handlePaystackWebhook);

  // Upload endpoints
  router.get('/upload', (Request request) async {
    return Response.ok('''
      <!DOCTYPE html>
      <html>
        <head>
          <title>Mipripity Image Upload</title>
          <style>
            body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
            h1 { color: #333; }
            form { margin-top: 20px; border: 1px solid #ddd; padding: 20px; border-radius: 5px; }
            input[type=file] { margin: 10px 0; }
            button { background: #4CAF50; color: white; border: none; padding: 10px 15px; border-radius: 4px; cursor: pointer; }
            button:hover { background: #45a049; }
          </style>
        </head>
        <body>
          <h1>Mipripity Image Upload</h1>
          <p>Use this form to test the image upload API, or use the POST endpoint programmatically.</p>
          <form action="/upload" method="post" enctype="multipart/form-data">
            <div>
              <label for="file">Select image to upload:</label><br>
              <input type="file" id="file" name="file" accept="image/*">
            </div>
            <button type="submit">Upload Image</button>
          </form>
        </body>
      </html>
    ''', headers: {'Content-Type': 'text/html'});
  });

  router.post('/upload', (Request request) async {
    return await handleUploadImage(request);
  });

  // User endpoints
  router.get('/users', (Request req) async {
    final results = await db.query('SELECT id, email, first_name, last_name, phone_number, whatsapp_link, avatar_url, account_status, created_at, last_login FROM users');
    final users = results.map((row) => _convertDateTimes(row.toColumnMap())).toList();
    return Response.ok(jsonEncode(users), headers: {'Content-Type': 'application/json'});
  });

  router.post('/users', (Request req) async {
    final payload = await req.readAsString();
    final data = jsonDecode(payload);
    
    if (data['email'] == null || data['password'] == null) {
      return Response(400, body: jsonEncode({'error': 'Email and password required'}), headers: {'Content-Type': 'application/json'});
    }

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

  // Login endpoint
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

  // Get user by email
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

  // User financial dashboard endpoints
  router.get('/users/id/<id>/financial-dashboard', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      
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
      
      // Get or create financial data
      var financialData = await db.mappedResultsQuery(
        'SELECT * FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (financialData.isEmpty) {
        // Create default financial data
        await db.execute('''
          INSERT INTO user_financial_data (user_id, monthly_income, total_funds)
          VALUES (@user_id, 0, 0)
        ''', substitutionValues: {'user_id': userId});
        
        financialData = await db.mappedResultsQuery(
          'SELECT * FROM user_financial_data WHERE user_id = @user_id',
          substitutionValues: {'user_id': userId},
        );
      }
      
      final userData = _convertDateTimes(financialData.first['user_financial_data'] ?? {});
      
      // Fetch recent transactions
      final transactions = await db.mappedResultsQuery('''
        SELECT * FROM financial_transactions 
        WHERE user_id = @user_id 
        ORDER BY created_at DESC LIMIT 5
      ''', substitutionValues: {'user_id': userId});
      
      final recentTransactions = transactions.map((row) => 
        _convertDateTimes(row['financial_transactions'] ?? {})
      ).toList();
      
      // Fetch active bids
      final String userIdStr = userId.toString();
      var bids = <Map<String, Map<String, dynamic>>>[];
      
      try {
        bids = await db.mappedResultsQuery('''
          SELECT * FROM bids 
          WHERE user_id = @user_id AND status IN ('pending', 'active')
          ORDER BY created_at DESC
        ''', substitutionValues: {'user_id': userIdStr});
      } catch (e) {
        print('Error fetching bids, trying with integer ID: $e');
        bids = await db.mappedResultsQuery('''
          SELECT * FROM bids 
          WHERE user_id = @user_id_int AND status IN ('pending', 'active')
          ORDER BY created_at DESC
        ''', substitutionValues: {'user_id_int': userId});
      }
      
      final activeBids = bids.map((row) => 
        _convertDateTimes(row['bids'] ?? {})
      ).toList();
      
      // Create income breakdown based on monthly income
      final dynamic rawMonthlyIncome = userData['monthly_income'];
      final double monthlyIncome = (rawMonthlyIncome is num)
          ? rawMonthlyIncome.toDouble()
          : double.tryParse(rawMonthlyIncome?.toString() ?? '0') ?? 0.0;
      
      final incomeBreakdown = {
        'second': monthlyIncome / (30 * 24 * 60 * 60),
        'minute': monthlyIncome / (30 * 24 * 60),
        'hour': monthlyIncome / (30 * 24),
        'day': monthlyIncome / 30,
        'week': monthlyIncome / 4,
        'month': monthlyIncome,
        'year': monthlyIncome * 12,
      };
      
      // Compile response
      final response = {
        'total_funds': _parseDouble(userData['total_funds']),
        'monthly_income': monthlyIncome,
        'total_bids': _parseDouble(userData['total_bids']),
        'total_interests': _parseDouble(userData['total_interests']),
        'total_expenses': 0.0, // Add calculation if needed
        'recent_transactions': recentTransactions,
        'active_bids': activeBids,
        'favorite_listings': [], // Add if needed
        'watchlist': [], // Add if needed
        'recommendations': [], // Add if needed
        'income_breakdown': {
          'Salary': monthlyIncome * 0.8,
          'Investment': monthlyIncome * 0.1,
          'Other': monthlyIncome * 0.1,
        },
        'expense_breakdown': {
          'Bids': 0.0,
          'Purchases': 0.0,
          'Withdrawals': 0.0,
        },
      };
      
      return Response.ok(
        jsonEncode(response),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error fetching financial dashboard: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch financial dashboard data'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Set user monthly income
  router.post('/user/income', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      if (data['user_id'] == null || data['amount'] == null) {
        return Response(400,
          body: jsonEncode({
            'success': false,
            'error': 'User ID and amount are required'
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final userId = data['user_id'];
      final amount = data['amount'];
      final startTimestamp = data['start_timestamp'] ?? DateTime.now().toIso8601String();
      
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
      
      // Check if financial data exists, create or update
      var financialData = await db.mappedResultsQuery(
        'SELECT id FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (financialData.isEmpty) {
        // Create new financial data with income
        await db.execute('''
          INSERT INTO user_financial_data (
            user_id, 
            monthly_income, 
            income_start_timestamp
          )
          VALUES (
            @user_id, 
            @amount, 
            @start_timestamp
          )
        ''', substitutionValues: {
          'user_id': userId,
          'amount': amount,
          'start_timestamp': startTimestamp,
        });
      } else {
        // Update existing financial data
        await db.execute('''
          UPDATE user_financial_data 
          SET monthly_income = @amount,
              income_start_timestamp = @start_timestamp,
              updated_at = NOW()
          WHERE user_id = @user_id
        ''', substitutionValues: {
          'user_id': userId,
          'amount': amount,
          'start_timestamp': startTimestamp,
        });
      }
      
      // Get updated financial data
      final updatedData = await db.mappedResultsQuery(
        'SELECT monthly_income, income_start_timestamp FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (updatedData.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch updated income data'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final result = _convertDateTimes(updatedData.first['user_financial_data'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'data': {
            'amount': result['monthly_income'],
            'start_timestamp': result['income_start_timestamp'],
          },
          'message': 'Income updated successfully'
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error updating income data: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update income data'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Get user income data
  router.get('/user/income/<id>', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      
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
      
      // Get financial data
      final financialData = await db.mappedResultsQuery(
        'SELECT monthly_income, income_start_timestamp FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (financialData.isEmpty) {
        return Response.ok(
          jsonEncode({
            'amount': 0,
            'start_timestamp': DateTime.now().toIso8601String(),
          }),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final userData = _convertDateTimes(financialData.first['user_financial_data'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'amount': userData['monthly_income'],
          'start_timestamp': userData['income_start_timestamp'],
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error fetching income data: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch income data'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Wallet endpoints
  router.post('/wallet/topup', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      if (data['user_id'] == null || data['amount'] == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'User ID and amount are required'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final userId = data['user_id'];
      final amount = data['amount'];
      
      // Update user financial data
      await db.execute('''
        UPDATE user_financial_data
        SET total_funds = total_funds + @amount
        WHERE user_id = @user_id
      ''', substitutionValues: {
        'user_id': userId,
        'amount': amount,
      });
      
      // Record transaction
      final uuid = Uuid();
      await db.execute('''
        INSERT INTO financial_transactions (
          id, user_id, transaction_type, amount, description, status, created_at
        ) VALUES (
          @id, @user_id, @transaction_type, @amount, @description, @status, @created_at
        )
      ''', substitutionValues: {
        'id': uuid.v4(),
        'user_id': userId,
        'transaction_type': 'credit',
        'amount': amount,
        'description': 'Wallet Top-up',
        'status': 'completed',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Top-up successful'
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error processing top-up: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to process top-up'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  router.post('/wallet/withdraw', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      if (data['user_id'] == null || data['amount'] == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'User ID and amount are required'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final userId = data['user_id'];
      final amount = data['amount'];
      
      // Check if user has sufficient funds
      final financialData = await db.mappedResultsQuery(
        'SELECT total_funds FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (financialData.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'User financial data not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final currentFunds = _parseDouble(financialData.first['user_financial_data']?['total_funds']);
      
      if (currentFunds < amount) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Insufficient funds'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Update user financial data
      await db.execute('''
        UPDATE user_financial_data
        SET total_funds = total_funds - @amount
        WHERE user_id = @user_id
      ''', substitutionValues: {
        'user_id': userId,
        'amount': amount,
      });
      
      // Record transaction
      final uuid = Uuid();
      await db.execute('''
        INSERT INTO financial_transactions (
          id, user_id, transaction_type, amount, description, status, created_at
        ) VALUES (
          @id, @user_id, @transaction_type, @amount, @description, @status, @created_at
        )
      ''', substitutionValues: {
        'id': uuid.v4(),
        'user_id': userId,
        'transaction_type': 'debit',
        'amount': amount,
        'description': 'Wallet Withdrawal',
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
      });
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Withdrawal request submitted'
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error processing withdrawal: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to process withdrawal'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Properties endpoints
  router.get('/properties', (Request req) async {
    final results = await db.mappedResultsQuery('SELECT * FROM properties');
    final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
    return Response.ok(jsonEncode(properties), headers: {'Content-Type': 'application/json'});
  });

  router.post('/properties', (Request req) {
    return handlePostProperty(req, db);
  });

  router.get('/properties/<id>', (Request req, String id) async {
    List<Map<String, Map<String, dynamic>>> results = [];
    
    try {
      results = await db.mappedResultsQuery(
        'SELECT * FROM properties WHERE id = @id',
        substitutionValues: {'id': int.parse(id)},
      );
    } catch (_) {
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

  // Bids endpoints
  router.get('/bids', (Request req) async {
    try {
      final params = req.url.queryParameters;
      final userId = params['user_id'];
      
      String query = 'SELECT * FROM bids';
      Map<String, dynamic> substitutionValues = {};
      
      if (userId != null && userId.isNotEmpty) {
        query += ' WHERE user_id = @user_id';
        substitutionValues['user_id'] = userId;
      }
      
      query += ' ORDER BY created_at DESC';
      
      final results = await db.mappedResultsQuery(query, substitutionValues: substitutionValues);
      
      final bids = results.map((row) {
        final bidData = _convertDateTimes(row['bids'] ?? {});
        return bidData;
      }).toList();
      
      return Response.ok(
        jsonEncode(bids),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error fetching bids: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch bids: $e'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  router.post('/bids', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      // Validate required fields
      final requiredFields = [
        'user_id', 'listing_id', 'listing_title', 'listing_image', 
        'listing_category', 'listing_location', 'listing_price', 'bid_amount'
      ];
      
      for (final field in requiredFields) {
        if (data[field] == null) {
          return Response.badRequest(
            body: jsonEncode({'error': 'Missing required field: $field'}),
            headers: {'Content-Type': 'application/json'}
          );
        }
      }
      
      // Generate a unique ID for the bid
      final uuid = Uuid();
      final id = uuid.v4();
      
      // Insert the bid
      await db.execute('''
        INSERT INTO bids (
          id, user_id, listing_id, listing_title, listing_image, 
          listing_category, listing_location, listing_price, 
          bid_amount, status, created_at
        ) VALUES (
          @id, @user_id, @listing_id, @listing_title, @listing_image, 
          @listing_category, @listing_location, @listing_price, 
          @bid_amount, @status, @created_at
        )
      ''', substitutionValues: {
        'id': id,
        'user_id': data['user_id'],
        'listing_id': data['listing_id'],
        'listing_title': data['listing_title'],
        'listing_image': data['listing_image'],
        'listing_category': data['listing_category'],
        'listing_location': data['listing_location'],
        'listing_price': data['listing_price'],
        'bid_amount': data['bid_amount'],
        'status': data['status'] ?? 'pending',
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      });
      
      // Fetch the newly created bid
      final results = await db.mappedResultsQuery(
        'SELECT * FROM bids WHERE id = @id',
        substitutionValues: {'id': id}
      );
      
      if (results.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to create bid'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final bid = _convertDateTimes(results.first['bids'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Bid created successfully',
          'bid': bid
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error creating bid: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to create bid: $e'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

  // Poll properties endpoints
  router.get('/poll_properties', (Request req) async {
    try {
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
      
      for (final poll in pollResults) {
        final pollData = _convertDateTimes(poll['poll_properties'] ?? {});
        
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

  router.post('/poll_properties', (Request req) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      if (data['title'] == null || data['location'] == null || data['suggestions'] == null ||
          !data['suggestions'].isNotEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields: title, location, suggestions'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final uuid = Uuid();
      final id = uuid.v4();
      
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

  // Investment endpoints
  router.get('/investments', (Request req) async {
    return fetchInvestments(req);
  });

  router.post('/investments', (Request req) async {
    return createInvestment(req);
  });

  // CAC verification endpoint
  router.post('/verify-agency', CacVerificationHandler.handleVerifyAgency);

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