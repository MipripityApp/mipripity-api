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

// CORS helper function to add CORS headers to responses
Response _cors(Response response) {
  return response.change(headers: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
    'Access-Control-Max-Age': '3600',
    ...response.headers,
  });
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
      'status': 'available', // Default status
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

// .................................//
// HomeScreen-specific API endpoints
// ................................//

// GET /user-financial-summary/:userId - Returns user's financial summary
router.get('/user-financial-summary/<userId>', (Request req, String userId) async {
  try {
    final userIdInt = int.tryParse(userId);
    if (userIdInt == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid user ID'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Query user financial data
    final results = await db.mappedResultsQuery(
      'SELECT balance, total_expenses, total_savings FROM user_financial_data WHERE user_id = @user_id',
      substitutionValues: {'user_id': userIdInt}
    );

    if (results.isEmpty) {
      // Return zeros if no financial data exists
      return Response.ok(
        jsonEncode({
          'balance': 0,
          'expenses': 0,
          'savings': 0
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final data = results.first['user_financial_data'];
    return Response.ok(
      jsonEncode({
        'balance': (data?['balance'] ?? 0).toDouble(),
        'expenses': (data?['total_expenses'] ?? 0).toDouble(),
        'savings': (data?['total_savings'] ?? 0).toDouble()
      }),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching financial summary: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch financial dashboard data'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});

// GET /nearby-properties - Returns properties near given coordinates
router.get('/nearby-properties', (Request req) async {
  try {
    final params = req.url.queryParameters;
    final latStr = params['lat'];
    final lngStr = params['lng'];
    final radiusStr = params['radius'] ?? '10';

    if (latStr == null || lngStr == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing lat or lng parameters'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final lat = double.tryParse(latStr);
    final lng = double.tryParse(lngStr);
    final radius = double.tryParse(radiusStr) ?? 10.0;

    if (lat == null || lng == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid lat or lng values'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Query properties with latitude and longitude
    final results = await db.mappedResultsQuery('''
      SELECT *, 
        (6371 * acos(cos(radians(@lat)) * cos(radians(latitude)) * 
        cos(radians(longitude) - radians(@lng)) + sin(radians(@lat)) * 
        sin(radians(latitude)))) AS distance
      FROM properties 
      WHERE latitude IS NOT NULL AND longitude IS NOT NULL
      HAVING distance <= @radius
      ORDER BY distance
      LIMIT 20
    ''', substitutionValues: {
      'lat': lat,
      'lng': lng,
      'radius': radius
    });

    final properties = results.map((row) {
      final propertyData = _convertDateTimes(row['properties'] ?? {});
      propertyData['distance'] = row['properties']?['distance']?.toDouble() ?? 0.0;
      return propertyData;
    }).toList();

    return Response.ok(
      jsonEncode(properties),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching nearby properties: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to load nearby properties'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});

// GET /user-activities/:userId - Returns user's recent activities
router.get('/user-activities/<userId>', (Request req, String userId) async {
  try {
    final userIdInt = int.tryParse(userId);
    if (userIdInt == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid user ID'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final results = await db.mappedResultsQuery(
      'SELECT * FROM user_activities WHERE user_id = @user_id ORDER BY created_at DESC LIMIT 10',
      substitutionValues: {'user_id': userIdInt}
    );

    final activities = results.map((row) {
      return _convertDateTimes(row['user_activities'] ?? {});
    }).toList();

    return Response.ok(
      jsonEncode(activities),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching user activities: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch activities'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});

// GET /user-properties/:userId - Returns user's properties
router.get('/properties/<userId>', (Request req, String userId) async {
  try {
    final userIdInt = int.tryParse(userId);
    if (userIdInt == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid user ID'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final results = await db.mappedResultsQuery(
      'SELECT * FROM properties WHERE user_id = @user_id ORDER BY created_at DESC',
      substitutionValues: {'user_id': userIdInt}
    );

    final properties = results.map((row) {
      return _convertDateTimes(row['properties'] ?? {});
    }).toList();

    return Response.ok(
      jsonEncode(properties),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching user properties: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch properties'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});

// POST /user-monthly-income/:userId - Store user's monthly income
router.post('/user-monthly-income/<userId>', (Request req, String userId) async {
  try {
    final userIdInt = int.tryParse(userId);
    if (userIdInt == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid user ID'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final payload = await req.readAsString();
    final data = jsonDecode(payload);
    final monthlyIncome = data['monthly_income'];

    if (monthlyIncome == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Missing monthly_income'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    // Insert or update monthly income
    await db.execute('''
      INSERT INTO user_financial_data (user_id, monthly_income, balance, total_expenses, total_savings)
      VALUES (@user_id, @monthly_income, 0, 0, 0)
      ON CONFLICT (user_id) 
      DO UPDATE SET monthly_income = @monthly_income, updated_at = CURRENT_TIMESTAMP
    ''', substitutionValues: {
      'user_id': userIdInt,
      'monthly_income': monthlyIncome
    });

    return Response.ok(
      jsonEncode({'success': true, 'message': 'Monthly income saved successfully'}),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error saving monthly income: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to save monthly income'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});

// GET /user-monthly-income/:userId - Get user's monthly income
router.get('/user-monthly-income/<userId>', (Request req, String userId) async {
  try {
    final userIdInt = int.tryParse(userId);
    if (userIdInt == null) {
      return Response.badRequest(
        body: jsonEncode({'error': 'Invalid user ID'}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final results = await db.mappedResultsQuery(
      'SELECT monthly_income FROM user_financial_data WHERE user_id = @user_id',
      substitutionValues: {'user_id': userIdInt}
    );

    if (results.isEmpty) {
      return Response.ok(
        jsonEncode({'monthly_income': null}),
        headers: {'Content-Type': 'application/json'}
      );
    }

    final monthlyIncome = results.first['user_financial_data']?['monthly_income'];
    return Response.ok(
      jsonEncode({'monthly_income': monthlyIncome?.toDouble()}),
      headers: {'Content-Type': 'application/json'}
    );
  } catch (e) {
    print('Error fetching monthly income: $e');
    return Response.internalServerError(
      body: jsonEncode({'error': 'Failed to fetch monthly income'}),
      headers: {'Content-Type': 'application/json'}
    );
  }
});


  
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware((innerHandler) {
        return (request) async {
          if (request.method == 'OPTIONS') {
            return Response.ok('', headers: {
              'Access-Control-Allow-Origin': '*',
              'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
              'Access-Control-Allow-Headers': 'Origin, Content-Type, Accept, Authorization, X-Requested-With',
              'Access-Control-Max-Age': '3600',
            });
          }
          final response = await innerHandler(request);
          return _cors(response);
        };
      })
      .addHandler(router);

  final server = await serve(handler, InternetAddress.anyIPv4, 8080);
  print('Server listening on port ${server.port}');
}
