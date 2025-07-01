import 'package:uuid/uuid.dart';
import 'package:mipripity_api/database_helper.dart';
import 'dart:convert';

void main() async {
  final db = await DatabaseHelper.connect();
  final uuid = Uuid();

  final sampleInvestments = [
    {
      'title': 'Lagoon View Apartments',
      'location': 'Lekki, Lagos',
      'description': 'Luxury waterfront apartments with a great return on investment.',
      'realtorName': 'John Adeyemi',
      'realtorImage': 'https://example.com/images/john.jpg',
      'minInvestment': 100000,
      'expectedReturn': '20%',
      'duration': '12 months',
      'investors': 15,
      'remainingAmount': 3000000,
      'totalAmount': 10000000,
      'images': ['https://example.com/images/apt1.jpg', 'https://example.com/images/apt2.jpg'],
      'features': ['Swimming Pool', 'Gym', 'Parking Space']
    },
    {
      'title': 'Ikoyi Smart Offices',
      'location': 'Ikoyi, Lagos',
      'description': 'Modern commercial spaces in prime location.',
      'realtorName': 'Tolu Bakare',
      'realtorImage': 'https://example.com/images/tolu.jpg',
      'minInvestment': 500000,
      'expectedReturn': '25%',
      'duration': '8 months',
      'investors': 8,
      'remainingAmount': 2000000,
      'totalAmount': 5000000,
      'images': ['https://example.com/images/office1.jpg'],
      'features': ['24/7 Electricity', 'Elevator', 'CCTV']
    },
  ];

  try {
    for (final investment in sampleInvestments) {
      final id = uuid.v4();

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
        'id': id,
        'title': investment['title'],
        'location': investment['location'],
        'description': investment['description'],
        'realtorName': investment['realtorName'],
        'realtorImage': investment['realtorImage'],
        'minInvestment': investment['minInvestment'],
        'expectedReturn': investment['expectedReturn'],
        'duration': investment['duration'],
        'investors': investment['investors'],
        'remainingAmount': investment['remainingAmount'],
        'totalAmount': investment['totalAmount'],
        'images': jsonEncode(investment['images']),
        'features': jsonEncode(investment['features']),
      });

      print('Seeded: ${investment['title']}');
    }
    print('Seeding complete.');
  } catch (e) {
    print('Error during seeding: $e');
  } finally {
    await db.close();
  }
}
