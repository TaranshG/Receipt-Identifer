import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiService {
  /// Automatically chooses the correct backend URL
  static String get baseUrl {
    // Android emulator cannot reach localhost
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  /// Health check
  static Future<bool> checkHealth() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Analyze receipt (image or manual data)
  static Future<Map<String, dynamic>> analyzeReceipt(
      Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/analyze'),
      headers: _headers,
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Analyze failed: ${response.body}');
  }

  /// Certify receipt on Solana
  static Future<Map<String, dynamic>> certifyReceipt(
      String canonicalText) async {
    final response = await http.post(
      Uri.parse('$baseUrl/certify'),
      headers: _headers,
      body: jsonEncode({'canonicalText': canonicalText}),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Certification failed: ${response.body}');
  }

  /// Verify receipt against blockchain
  static Future<Map<String, dynamic>> verifyReceipt(
      String canonicalText, String txSignature) async {
    final response = await http.post(
      Uri.parse('$baseUrl/verify'),
      headers: _headers,
      body: jsonEncode({
        'canonicalText': canonicalText,
        'txSignature': txSignature,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    throw Exception('Verification failed: ${response.body}');
  }
}
