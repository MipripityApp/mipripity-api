import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'package:html/dom.dart';
import 'package:shelf/shelf.dart';

/// CAC Verification Handler
/// 
/// This class handles the verification of business names against the
/// Corporate Affairs Commission (CAC) public search database.
class CacVerificationHandler {
  /// Base URL for CAC public search
  static const String _cacSearchUrl = 'https://search.cac.gov.ng/home';
  
  /// User agent to mimic a browser
  static const String _userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36';

  /// Verify a company/business name with CAC
  /// 
  /// This method scrapes the CAC public search page to verify if a business name exists.
  /// If found, it returns the verification status, RC number, and official name.
  static Future<Map<String, dynamic>> verifyBusinessName(String businessName) async {
    try {
      // Initialize result
      final result = {
        'status': 'not_found',
        'rc_number': null,
        'official_name': null,
      };
      
      // First, get the search page to obtain any CSRF tokens or cookies
      final client = http.Client();
      final initialResponse = await client.get(
        Uri.parse(_cacSearchUrl),
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        },
      );
      
      // Parse the HTML to find the form and any tokens
      final document = parser.parse(initialResponse.body);
      
      // Extract CSRF token if present (common in web forms)
      final csrfToken = _extractCsrfToken(document);
      
      // Submit the search form
      final searchResponse = await client.post(
        Uri.parse('$_cacSearchUrl/search'),
        headers: {
          'User-Agent': _userAgent,
          'Content-Type': 'application/x-www-form-urlencoded',
          'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
          'Referer': _cacSearchUrl,
          if (csrfToken != null) 'X-CSRF-TOKEN': csrfToken,
        },
        body: {
          'search_term': businessName,
          if (csrfToken != null) '_token': csrfToken,
        },
      );
      
      // Parse the search results
      if (searchResponse.statusCode == 200) {
        final resultDocument = parser.parse(searchResponse.body);
        
        // Check if business was found
        final verificationResult = _extractVerificationResult(resultDocument, businessName);
        
        if (verificationResult['found']) {
          result['status'] = 'verified';
          result['rc_number'] = verificationResult['rc_number'];
          result['official_name'] = verificationResult['official_name'];
        }
      }
      
      client.close();
      return result;
    } catch (e) {
      print('CAC verification error: $e');
      return {
        'status': 'error',
        'message': 'Error during verification: $e',
      };
    }
  }
  
  /// Extract CSRF token from the HTML document
  static String? _extractCsrfToken(Document document) {
    try {
      // Look for meta tag with CSRF token
      final metaTag = document.querySelector('meta[name="csrf-token"]');
      if (metaTag != null) {
        return metaTag.attributes['content'];
      }
      
      // Look for hidden input with CSRF token
      final inputTag = document.querySelector('input[name="_token"]');
      if (inputTag != null) {
        return inputTag.attributes['value'];
      }
      
      return null;
    } catch (e) {
      print('Error extracting CSRF token: $e');
      return null;
    }
  }
  
  /// Extract verification result from the search results page
  static Map<String, dynamic> _extractVerificationResult(Document document, String businessName) {
    final Map<String, dynamic> result = {
      'found': false,
      'rc_number': null as String?,
      'official_name': null as String?,
    };
    
    try {
      // Look for search results table
      final resultTables = document.querySelectorAll('table');
      
      for (final table in resultTables) {
        final rows = table.querySelectorAll('tr');
        
        for (final row in rows) {
          final cells = row.querySelectorAll('td');
          
          if (cells.length >= 2) {
            final companyName = cells[0].text.trim().toLowerCase();
            
            // Check if the business name is found (using partial match)
            if (companyName.contains(businessName.toLowerCase()) || 
                businessName.toLowerCase().contains(companyName)) {
              result['found'] = true;
              
              // Try to extract RC number from the row
              if (cells.length >= 3) {
                result['rc_number'] = cells[1].text.trim();
              }
              
              // Use the exact company name from CAC
              result['official_name'] = cells[0].text.trim();
              
              return result;
            }
          }
        }
      }
      
      // Check for alternative result structures
      final resultDivs = document.querySelectorAll('.search-result-item');
      for (final div in resultDivs) {
        final nameElement = div.querySelector('.company-name');
        final rcElement = div.querySelector('.rc-number');
        
        if (nameElement != null) {
          final companyName = nameElement.text.trim().toLowerCase();
          
          if (companyName.contains(businessName.toLowerCase()) || 
              businessName.toLowerCase().contains(companyName)) {
            result['found'] = true;
            result['official_name'] = nameElement.text.trim();
            
            if (rcElement != null) {
              result['rc_number'] = rcElement.text.trim();
            }
            
            return result;
          }
        }
      }
      
      return result;
    } catch (e) {
      print('Error extracting verification result: $e');
      return result;
    }
  }
  
  /// Handle API requests for CAC verification
  static Future<Response> handleVerifyAgency(Request request) async {
    try {
      // Parse request body
      final payload = await request.readAsString();
      final data = jsonDecode(payload);
      
      // Validate request
      if (data['agency_name'] == null || data['agency_name'].trim().isEmpty) {
        return Response(400, 
          body: jsonEncode({
            'status': 'error',
            'message': 'Agency name is required'
          }), 
          headers: {'Content-Type': 'application/json'}
        );
      }
      
      final agencyName = data['agency_name'].trim();
      
      // Perform verification
      final verificationResult = await verifyBusinessName(agencyName);
      
      return Response.ok(
        jsonEncode(verificationResult),
        headers: {'Content-Type': 'application/json'}
      );
    } catch (e) {
      print('Error handling verify-agency request: $e');
      return Response.internalServerError(
        body: jsonEncode({
          'status': 'error',
          'message': 'Internal server error during verification'
        }),
        headers: {'Content-Type': 'application/json'}
      );
    }
  }
}