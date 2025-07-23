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
  final String status; // 'pending', 'accepted', 'rejected', 'expired', 'withdrawn'
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

// Handler for POST /properties endpoint
Future<Response> handlePostProperty(Request request, PostgreSQLConnection connection) async {
  try {
    final payload = await request.readAsString();
    final data = Map<String, dynamic>.from(jsonDecode(payload));

    // Extract all expected fields
    final propertyId = data['property_id'];
    final title = data['title'];
    final price = data['price'];
    final market_value = data['market_value'] ?? 0.0;
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
    final List<String> images =
    data['images'] != null ? List<String>.from(data['images']) : <String>[];
    final String imagesJson = jsonEncode(images);
    final latitude = data['latitude'];
    final longitude = data['longitude'];
    final landType = data['landType'];
    final bedrooms = data['bedrooms'];
    final bathrooms = data['bathrooms'];
    final toilets = data['toilets'];
    final parkingSpaces = data['parkingSpaces'];
    final internet = data['internetValue'] ?? false;
    final electricity = data['electricityValue'] ?? false;
    final landSize = data['landSize'];
    final landTitle = data['landtitle'];
    final isActive = data['is_active'] ?? true;
    final isVerified = data['is_verified'] ?? false;

    // Insert into database
    await connection.query('''
      INSERT INTO properties (
        title, category, description, land_type,
        bedrooms, bathrooms, toilets, parking_spaces,
        internet, electricity, land_size, land_title,
        price, market_value, status, location, latitude, longitude,
        quantity, condition, terms_and_conditions, images,
        is_urgent, urgency_data, is_bidding, bidding_data,
        target_demography, demography_data,
        user_id, lister_name, lister_email, address, lister_whatsapp,
        created_at, updated_at
      ) VALUES (
        @title, @category, @description, @land_type,
        @bedrooms, @bathrooms, @toilets, @parking_spaces,
        @internet, @electricity, @land_size, @land_title,
        @price, @market_value, @status, @location, @latitude, @longitude,
        @quantity, @condition, @terms_and_conditions, @images::jsonb,
        @is_urgent, @urgency_data, @is_bidding, @bidding_data,
        @target_demography, @demography_data,
        @user_id, @lister_name, @lister_email, @address, @lister_whatsapp,
        NOW(), NOW()
      )
    ''', substitutionValues: {
      'property_id': propertyId,
      'title': title,
      'market_value': market_value,
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
      'images': imagesJson,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
      'is_verified': isVerified,
      'land_type': landType,
      'bedrooms': bedrooms,
      'bathrooms': bathrooms,
      'toilets': toilets,
      'parking_spaces': parkingSpaces,
      'internet': internet,
      'electricity': electricity,
      'land_size': landSize,
      'land_title': landTitle,
      'terms_and_conditions': data['termsAndConditions'] ?? '',
      'is_urgent': data['isUrgent'] ?? false,
      'urgency_data': data['urgencyData'] != null ? jsonEncode(data['urgencyData']) : null,
      'is_bidding': data['isBidding'] ?? false,
      'bidding_data': data['biddingData'] != null ? jsonEncode(data['biddingData']) : null,
      'target_demography': data['targetDemography'] != null ? jsonEncode(data['targetDemography']) : null,
      'demography_data': data['demographyData'] != null ? jsonEncode(data['demographyData']) : null,
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
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

// Paystack API handler functions
Future<Response> handlePaystackInitialize(Request request) async {
  try {
    // Get Paystack secret key from environment variables (for security)
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    // Read request body
    final payload = await request.readAsString();
    final requestData = jsonDecode(payload);
    
    // Validate required fields
    if (requestData['email'] == null || requestData['amount'] == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Email and amount are required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    // Prepare data for Paystack API
    final Map<String, dynamic> paystackData = {
      'email': requestData['email'],
      'amount': requestData['amount'],
      'currency': 'NGN',
      'reference': requestData['reference'] ?? 'MIP${DateTime.now().millisecondsSinceEpoch}',
      'callback_url': requestData['callback_url'] ?? 'https://mipripity-api-1.onrender.com/webhook',
    };
    
    // Add metadata if provided
    if (requestData['metadata'] != null) {
      paystackData['metadata'] = requestData['metadata'];
    }
    
    // Initialize transaction with Paystack API
    final response = await http.post(
      Uri.parse('https://api.paystack.co/transaction/initialize'),
      headers: {
        'Authorization': 'Bearer $paystackSecretKey',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(paystackData),
    );
    
    // Parse response
    final responseData = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      // Return success with authorization URL
      return Response.ok(
        jsonEncode({
          'authorization_url': responseData['data']['authorization_url'],
          'access_code': responseData['data']['access_code'],
          'reference': responseData['data']['reference'],
        }),
        headers: {'Content-Type': 'application/json'},
      );
    } else {
      // Return error
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
    // Get Paystack secret key from environment variables (for security)
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    // Read request body
    final payload = await request.readAsString();
    final requestData = jsonDecode(payload);
    
    // Validate required fields
    if (requestData['reference'] == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Transaction reference is required'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    
    final reference = requestData['reference'];
    
    // Verify transaction with Paystack API
    final response = await http.get(
      Uri.parse('https://api.paystack.co/transaction/verify/$reference'),
      headers: {
        'Authorization': 'Bearer $paystackSecretKey',
        'Content-Type': 'application/json',
      },
    );
    
    // Parse response
    final responseData = jsonDecode(response.body);
    
    if (response.statusCode == 200) {
      // Check if transaction was successful
      final status = responseData['data']['status'];
      final isSuccess = status == 'success';
      
      // Log transaction information (optional)
      if (isSuccess) {
        // Here you could store the transaction in your database
        // Or perform other actions based on the payment
        print('Payment successful: $reference');
        
        // If property_id is provided, update property with payment information
        if (requestData['property_id'] != null) {
          // You could implement property-specific logic here
          print('Payment for property: ${requestData['property_id']}');
        }
      }
      
      // Return verification result
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
      // Return error
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

// Webhook handler for Paystack callbacks
Future<Response> handlePaystackWebhook(Request request) async {
  try {
    // Get Paystack secret key from environment variables (for security)
    final paystackSecretKey = Platform.environment['PAYSTACK_SECRET_KEY'] ?? 'sk_live_fe4415cf99c999fb2b731f8991c94e548421aa90';
    
    // Verify Paystack signature if provided (for production)
    final signature = request.headers['x-paystack-signature'];
    
    // Read request body
    final payload = await request.readAsString();
    final eventData = jsonDecode(payload);
    
    // Extract event information
    final event = eventData['event'];
    
    if (event == 'charge.success') {
      // Handle successful payment
      final data = eventData['data'];
      final reference = data['reference'];
      final amount = data['amount'];
      final status = data['status'];
      
      print('Webhook: Successful payment - Reference: $reference, Amount: $amount, Status: $status');
      
      // Here you could update your database or trigger other actions
      // based on the successful payment
    }
    
    // Always return 200 OK to acknowledge receipt of webhook
    return Response.ok(
      jsonEncode({'status': 'success'}),
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Paystack webhook error: $e');
    // Still return 200 OK to prevent Paystack from retrying
    return Response.ok(
      jsonEncode({'status': 'error', 'message': 'Error processing webhook'}),
      headers: {'Content-Type': 'application/json'},
    );
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
        
        // Create bids table if it doesn't exist
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
        
        print('Database tables created successfully');
    } catch (e) {
      print('Error creating poll properties tables: $e');
      // Continue anyway as this is not critical for the API to function
    }
  } catch (e) {
    print('Failed to connect to the database: $e');
    exit(1);
  }

  // Image upload handler for Cloudinary with Replicate Real-ESRGAN enhancement
  Future<Response> handleUploadImage(Request request) async {
    try {
      final boundary = request.headers['content-type']?.split('boundary=').last;
      final transformer = MimeMultipartTransformer(boundary!);
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

  final router = Router();
  
  // Register Paystack endpoints
  router.post('/paystack/initialize', handlePaystackInitialize);
  router.post('/paystack/verify', handlePaystackVerify);
  router.post('/webhook', handlePaystackWebhook);

  router.get('/', (Request req) async {
    return Response.ok('Mipripity API is running');
  });
  
  // Register the upload endpoints
  // GET handler returns a simple HTML form for testing uploads
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
  
  // POST handler processes the image upload
  router.post('/upload', (Request request) async {
    return await handleUploadImage(request);
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
  
  // Bids Endpoints
  // GET /bids - Fetch all bids, with optional user_id filter
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
  
  // POST /bids - Create a new bid
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
  
  // PUT /bids/:id - Update a bid (amount or status)
  router.put('/bids/<id>', (Request req, String id) async {
    try {
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      // Check if bid exists
      final existingBid = await db.mappedResultsQuery(
        'SELECT * FROM bids WHERE id = @id',
        substitutionValues: {'id': id}
      );
      
      if (existingBid.isEmpty) {
        return Response.notFound(
          jsonEncode({'error': 'Bid not found'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Build dynamic update query based on provided fields
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'id': id};
      
      // Allowed fields to update
      final allowedFields = [
        'bid_amount', 'status', 'response_message', 'response_date'
      ];
      
      for (final field in allowedFields) {
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
      
      // If updating status to 'accepted' or 'rejected', add response date if not provided
      if (data.containsKey('status') && 
          (data['status'] == 'accepted' || data['status'] == 'rejected') && 
          !data.containsKey('response_date')) {
        updateFields.add('response_date = @response_date');
        substitutionValues['response_date'] = DateTime.now().toIso8601String();
      }
      
      final updateQuery = '''
        UPDATE bids 
        SET ${updateFields.join(', ')} 
        WHERE id = @id
      ''';
      
      await db.execute(updateQuery, substitutionValues: substitutionValues);
      
      // Fetch and return updated bid
      final results = await db.mappedResultsQuery(
        'SELECT * FROM bids WHERE id = @id',
        substitutionValues: {'id': id}
      );
      
      if (results.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch updated bid'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final bid = _convertDateTimes(results.first['bids'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'message': 'Bid updated successfully',
          'bid': bid
        }),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error updating bid: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update bid: $e'}),
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

  // Create property - using the comprehensive handlePostProperty function
  router.post('/properties', (Request req) {
    return handlePostProperty(req, db);
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
  
  // Get properties by user_id
  router.get('/properties/user', (Request req) async {
    try {
      final params = req.url.queryParameters;
      final userId = params['user_id'];
      
      if (userId == null || userId.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required user_id parameter'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final results = await db.mappedResultsQuery(
        'SELECT * FROM properties WHERE user_id = @user_id ORDER BY created_at DESC',
        substitutionValues: {'user_id': userId},
      );
      
      final properties = results.map((row) => _convertDateTimes(row['properties'] ?? {})).toList();
      
      return Response.ok(
        jsonEncode(properties),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error fetching properties by user_id: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to fetch user properties: $e'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
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

  // Create necessary tables for user dashboard
  try {
    // Check if financial_data table exists
    final financialTableExists = await db.mappedResultsQuery("""
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_name = 'user_financial_data'
    """);

    if (financialTableExists.isEmpty) {
      // Create user_financial_data table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS user_financial_data (
          id SERIAL PRIMARY KEY,
          user_id INTEGER NOT NULL REFERENCES users(id),
          monthly_income DECIMAL(15, 2) DEFAULT 0,
          total_funds DECIMAL(15, 2) DEFAULT 0,
          total_bids DECIMAL(15, 2) DEFAULT 0,
          total_interests DECIMAL(15, 2) DEFAULT 0,
          income_breakdown JSONB DEFAULT '{}'::jsonb,
          created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
          UNIQUE(user_id)
        )
      ''');
      
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
      
      print('Created financial dashboard tables');
    }
    
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

  // User financial dashboard endpoints
  
  // GET /users/id/:id/financial-dashboard - Get user's financial dashboard data
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
      final bids = await db.mappedResultsQuery('''
        SELECT * FROM bids 
        WHERE user_id = @user_id AND status IN ('pending', 'active') 
        ORDER BY created_at DESC
      ''', substitutionValues: {'user_id': userId.toString()});
      
      final activeBids = bids.map((row) => 
        _convertDateTimes(row['bids'] ?? {})
      ).toList();
      
      // Create income breakdown based on monthly income
      final monthlyIncome = userData['monthly_income'] ?? 0.0;
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
        'total_funds': userData['total_funds'] ?? 0.0,
        'monthly_income': monthlyIncome,
        'total_bids': userData['total_bids'] ?? 0.0,
        'total_interests': userData['total_interests'] ?? 0.0,
        'recent_transactions': recentTransactions,
        'active_bids': activeBids,
        'income_breakdown': incomeBreakdown,
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
  
  // PUT /users/id/:id/financial - Update user's financial data
  router.put('/users/id/<id>/financial', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
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
      
      // Check if financial data exists, create if not
      var financialData = await db.mappedResultsQuery(
        'SELECT id FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (financialData.isEmpty) {
        await db.execute('''
          INSERT INTO user_financial_data (user_id)
          VALUES (@user_id)
        ''', substitutionValues: {'user_id': userId});
      }
      
      // Build dynamic update query based on provided fields
      final updateFields = <String>[];
      final substitutionValues = <String, dynamic>{'user_id': userId};
      
      // Valid fields to update
      final validFields = [
        'monthly_income', 'total_funds', 'total_bids', 'total_interests',
        'income_breakdown'
      ];
      
      for (final field in validFields) {
        if (data.containsKey(field)) {
          updateFields.add('$field = @$field');
          
          if (field == 'income_breakdown' && data[field] is Map) {
            substitutionValues[field] = jsonEncode(data[field]);
          } else {
            substitutionValues[field] = data[field];
          }
        }
      }
      
      if (updateFields.isEmpty) {
        return Response.badRequest(
          body: jsonEncode({'error': 'No valid fields provided for update'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      // Add updated_at timestamp
      updateFields.add('updated_at = NOW()');
      
      final updateQuery = '''
        UPDATE user_financial_data 
        SET ${updateFields.join(', ')} 
        WHERE user_id = @user_id
      ''';
      
      await db.execute(updateQuery, substitutionValues: substitutionValues);
      
      // Get updated financial data
      final updatedData = await db.mappedResultsQuery(
        'SELECT * FROM user_financial_data WHERE user_id = @user_id',
        substitutionValues: {'user_id': userId},
      );
      
      if (updatedData.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch updated financial data'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final result = _convertDateTimes(updatedData.first['user_financial_data'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'data': result,
          'message': 'Financial data updated successfully'
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error updating financial data: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to update financial data'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });
  
  // POST /users/id/:id/transactions - Record a new financial transaction
  router.post('/users/id/<id>/transactions', (Request req, String id) async {
    try {
      final userId = int.parse(id);
      final payload = await req.readAsString();
      final data = jsonDecode(payload);
      
      // Validate required fields
      if (data['amount'] == null || data['transaction_type'] == null) {
        return Response.badRequest(
          body: jsonEncode({'error': 'Missing required fields: amount, transaction_type'}),
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
      
      // Generate transaction ID
      final uuid = Uuid();
      final transactionId = uuid.v4();
      
      // Insert transaction
      await db.execute('''
        INSERT INTO financial_transactions (
          id, user_id, transaction_type, amount, description, status, created_at
        ) VALUES (
          @id, @user_id, @transaction_type, @amount, @description, @status, @created_at
        )
      ''', substitutionValues: {
        'id': transactionId,
        'user_id': userId,
        'transaction_type': data['transaction_type'],
        'amount': data['amount'],
        'description': data['description'] ?? '',
        'status': data['status'] ?? 'completed',
        'created_at': data['created_at'] ?? DateTime.now().toIso8601String(),
      });
      
      // Update user financial data based on transaction type
      if (data['transaction_type'] == 'credit') {
        await db.execute('''
          UPDATE user_financial_data
          SET total_funds = total_funds + @amount
          WHERE user_id = @user_id
        ''', substitutionValues: {
          'user_id': userId,
          'amount': data['amount'],
        });
      } else if (data['transaction_type'] == 'debit') {
        await db.execute('''
          UPDATE user_financial_data
          SET total_funds = total_funds - @amount
          WHERE user_id = @user_id
        ''', substitutionValues: {
          'user_id': userId,
          'amount': data['amount'],
        });
      }
      
      // Get the created transaction
      final result = await db.mappedResultsQuery(
        'SELECT * FROM financial_transactions WHERE id = @id',
        substitutionValues: {'id': transactionId},
      );
      
      if (result.isEmpty) {
        return Response.internalServerError(
          body: jsonEncode({'error': 'Failed to fetch created transaction'}),
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final transaction = _convertDateTimes(result.first['financial_transactions'] ?? {});
      
      return Response.ok(
        jsonEncode({
          'success': true,
          'transaction': transaction,
          'message': 'Transaction recorded successfully'
        }),
        headers: {'Content-Type': 'application/json'}
      );
      
    } catch (e) {
      print('Error recording transaction: $e');
      return Response.internalServerError(
        body: jsonEncode({'error': 'Failed to record transaction'}),
        headers: {'Content-Type': 'application/json'}
      );
    }
  });

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