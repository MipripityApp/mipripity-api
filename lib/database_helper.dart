import 'dart:io';
import 'package:postgres/postgres.dart';

/// Database connection helper with hardcoded Render.com configuration
class DatabaseHelper {
  // Hardcoded database configuration for Render.com
  static const String _host = 'dpg-d159reffte5s738vedk0-a.frankfurt-postgres.render.com';
  static const int _port = 5432;
  static const String _databaseName = 'mipripity_app';
  static const String _username = 'mipripity_user';
  static const String _password = 'jwMRrsn2O9LNHqm83byh6XxYxV7tqmYz';

  /// Create a PostgreSQL connection with the configured settings
  static PostgreSQLConnection createConnection() {
    // Allow environment variables to override hardcoded values if needed
    final host = Platform.environment['DB_HOST'] ?? _host;
    final port = int.tryParse(Platform.environment['DB_PORT'] ?? '') ?? _port;
    final databaseName = Platform.environment['DB_NAME'] ?? _databaseName;
    final username = Platform.environment['DB_USER'] ?? _username;
    final password = Platform.environment['DB_PASSWORD'] ?? _password;

    return PostgreSQLConnection(
      host,
      port,
      databaseName,
      username: username,
      password: password,
      useSSL: true, // Render requires SSL
    );
  }

  /// Connect to the database and handle errors
  static Future<PostgreSQLConnection> connect() async {
    final connection = createConnection();
    
    try {
      await connection.open();
      print('Connected to database successfully');
      return connection;
    } catch (e) {
      print('Failed to connect to the database: $e');
      rethrow;
    }
  }

  /// Alternative direct connection method (matches your original request exactly)
  static Future<PostgreSQLConnection> connectDirect() async {
    final connection = PostgreSQLConnection(
      'dpg-d159reffte5s738vedk0-a.frankfurt-postgres.render.com', // host
      5432, // port
      'mipripity_app', // database name
      username: 'mipripity_user',
      password: 'jwMRrsn2O9LNHqm83byh6XxYxV7tqmYz',
      useSSL: true, // Render requires SSL
    );
    await connection.open();
    return connection;
  }
}