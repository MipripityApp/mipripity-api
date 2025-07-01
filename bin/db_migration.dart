import 'dart:io';
import 'package:postgres/postgres.dart';
import 'package:mipripity_api/database_helper.dart';

/// Script to initialize the database schema
/// Run this script to create necessary tables before starting the server
void main() async {
  print('Starting database migration...');

  PostgreSQLConnection db;
  try {
    db = await DatabaseHelper.connect();
    print('Connected to database successfully');
  } catch (e) {
    print('Failed to connect to the database: $e');
    exit(1);
  }

  try {
    // Create users table if it doesn't exist
    await db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      email VARCHAR(255) UNIQUE NOT NULL,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''');
    print('Users table created or verified');

    // Create properties table if it doesn't exist
    await db.execute('''
    CREATE TABLE IF NOT EXISTS properties (
      id SERIAL PRIMARY KEY,
      name VARCHAR(255) NOT NULL,
      type VARCHAR(50) NOT NULL,
      location VARCHAR(255) NOT NULL,
      description TEXT,
      price DECIMAL(15, 2),
      user_id INTEGER REFERENCES users(id),
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''');
    print('Properties table created or verified');

    // Add any additional tables or schema updates here

        // Create investments table if it doesn't exist
    await _createInvestmentsTable(db);
    print('Investments table created or verified');

    print('Database migration completed successfully');
  } catch (e) {
    print('Error during database migration: $e');
    exit(1);
  } finally {
    await db.close();
  }
}

Future<void> _createInvestmentsTable(PostgreSQLConnection db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS investments (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      location TEXT NOT NULL,
      description TEXT NOT NULL,
      realtorName TEXT NOT NULL,
      realtorImage TEXT NOT NULL,
      minInvestment INTEGER NOT NULL,
      expectedReturn TEXT NOT NULL,
      duration TEXT NOT NULL,
      investors INTEGER NOT NULL,
      remainingAmount INTEGER NOT NULL,
      totalAmount INTEGER NOT NULL,
      images TEXT NOT NULL,
      features TEXT NOT NULL
    )
  ''');
}