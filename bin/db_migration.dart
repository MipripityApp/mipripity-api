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
      email VARCHAR(255) UNIQUE NOT NULL,
      password VARCHAR(255) NOT NULL,
      first_name VARCHAR(100),
      last_name VARCHAR(100),
      phone_number VARCHAR(20),
      whatsapp_link VARCHAR(255),
      avatar_url TEXT,
      account_status VARCHAR(20) DEFAULT 'active',
      last_login TIMESTAMP,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''');
    print('Users table created or verified');

    // Create user_settings table if it doesn't exist
    await db.execute('''
    CREATE TABLE IF NOT EXISTS user_settings (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      push_notifications BOOLEAN DEFAULT true,
      email_notifications BOOLEAN DEFAULT true,
      sms_notifications BOOLEAN DEFAULT false,
      in_app_notifications BOOLEAN DEFAULT true,
      notification_sound BOOLEAN DEFAULT true,
      notification_vibration BOOLEAN DEFAULT true,
      theme_preference VARCHAR(20) DEFAULT 'light',
      language_preference VARCHAR(10) DEFAULT 'en',
      currency_preference VARCHAR(10) DEFAULT 'NGN',
      distance_unit VARCHAR(10) DEFAULT 'km',
      date_format VARCHAR(20) DEFAULT 'DD/MM/YYYY',
      two_factor_auth BOOLEAN DEFAULT false,
      biometric_auth BOOLEAN DEFAULT false,
      location_tracking BOOLEAN DEFAULT true,
      auto_logout_minutes INTEGER DEFAULT 30,
      profile_visibility VARCHAR(20) DEFAULT 'public',
      show_email BOOLEAN DEFAULT false,
      show_phone BOOLEAN DEFAULT false,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
      UNIQUE(user_id)
    )
    ''');
    print('User settings table created or verified');

    // Create user_activity_log table if it doesn't exist
    await db.execute('''
    CREATE TABLE IF NOT EXISTS user_activity_log (
      id SERIAL PRIMARY KEY,
      user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
      activity_type VARCHAR(50) NOT NULL,
      activity_description TEXT,
      metadata JSONB,
      ip_address VARCHAR(45),
      user_agent TEXT,
      created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    )
    ''');
    print('User activity log table created or verified');

    // Create properties table if it doesn't exist
    await db.execute('''
    CREATE TABLE IF NOT EXISTS properties (
      id SERIAL PRIMARY KEY,
      property_id VARCHAR(50) UNIQUE,
      title VARCHAR(255) NOT NULL,
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

    print('Database migration completed successfully');
  } catch (e) {
    print('Error during database migration: $e');
    exit(1);
  } finally {
    await db.close();
  }
}