import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:yaml/yaml.dart';

/// Database connection helper that loads configuration from pubspec.yaml
class DatabaseHelper {
  /// Load database configuration from pubspec.yaml file
  static Map<String, dynamic> loadDbConfig() {
    try {
      // Read the pubspec.yaml file
      final File pubspecFile = File('pubspec.yaml');
      if (!pubspecFile.existsSync()) {
        throw Exception('pubspec.yaml file not found');
      }

      final String pubspecContent = pubspecFile.readAsStringSync();
      final dynamic pubspecYaml = loadYaml(pubspecContent);

      // Get the database configuration
      final List<dynamic> databases = pubspecYaml['databases'] ?? [];
      if (databases.isEmpty) {
        throw Exception('No database configuration found in pubspec.yaml');
      }

      // Find the mipripity_db configuration
      final dynamic dbConfig = databases.firstWhere(
        (db) => db['name'] == 'mipripity_db',
        orElse: () => null,
      );

      if (dbConfig == null) {
        throw Exception('mipripity_db configuration not found in pubspec.yaml');
      }

      // Extract the database configuration
      return {
        'databaseName': dbConfig['databaseName'] as String,
        'user': dbConfig['user'] as String,
        'region': dbConfig['region'] as String,
        'plan': dbConfig['plan'] as String,
        'postgresMajorVersion': dbConfig['postgresMajorVersion'] as String,
      };
    } catch (e) {
      print('Error loading database configuration: $e');
      // Return default values if configuration cannot be loaded
      return {
        'databaseName': 'mipripity_app',
        'user': 'mipripity_user',
        'region': 'frankfurt',
        'plan': 'free',
        'postgresMajorVersion': '15',
      };
    }
  }

  /// Create a PostgreSQL connection using the configuration from pubspec.yaml
  static PostgreSQLConnection createConnection() {
    final dbConfig = loadDbConfig();
    
    // Construct the host based on the region
    // For render.com, the format is usually region.postgres.render.com
    final host = Platform.environment['DB_HOST'] ?? 
                '${dbConfig['region']}.postgres.render.com';
    
    // Get database name and user from config
    final databaseName = Platform.environment['DB_NAME'] ?? 
                        dbConfig['databaseName'];
    
    final user = Platform.environment['DB_USER'] ?? 
                dbConfig['user'];
    
    // Password should be provided via environment variable for security
    final password = Platform.environment['DB_PASSWORD'] ?? '';
    
    return PostgreSQLConnection(
      host,
      5432, // Default PostgreSQL port
      databaseName,
      username: user,
      password: password,
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
}