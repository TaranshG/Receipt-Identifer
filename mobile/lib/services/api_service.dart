// lib/services/api_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class ApiService {
  /// Backend URL
  /// - Android emulator uses 10.0.2.2
  /// - iOS sim / desktop uses localhost
  /// - REAL PHONE: override with --dart-define=API_BASE_URL=http://<YOUR_LAPTOP_IP>:3000
  static String get baseUrl {
    const override = String.fromEnvironment('API_BASE_URL');
    if (override.isNotEmpty) return override;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
  };

  static Exception _prettyError(String title, http.Response r) {
    try {
      final body = jsonDecode(r.body);
      final msg = body['error'] ?? body['message'] ?? r.body;
      return Exception('$title (${r.statusCode}): $msg');
    } catch (_) {
      return Exception('$title (${r.statusCode}): ${r.body}');
    }
  }

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
  ///
  /// Expects backend to return JSON:
  /// { success:true, ...analysisFields, canonicalText, hash, timestamp }
  static Future<Map<String, dynamic>> analyzeReceipt(Map<String, dynamic> data) async {
    final response = await http.post(
      Uri.parse('$baseUrl/analyze'),
      headers: _headers,
      body: jsonEncode(data),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Analyze failed: invalid JSON response');
    }

    throw _prettyError('Analyze failed', response);
  }

  /// Certify receipt on Solana
  ///
  /// Backend returns:
  /// {
  ///   success:true,
  ///   txSignature,
  ///   chainHash,
  ///   explorerUrl,
  ///   duplicate, firstSeenTx, firstSeenAt, seenCount,
  ///   message
  /// }
  static Future<Map<String, dynamic>> certifyReceipt(String canonicalText) async {
    final response = await http.post(
      Uri.parse('$baseUrl/certify'),
      headers: _headers,
      body: jsonEncode({'canonicalText': canonicalText}),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Certification failed: invalid JSON response');
    }

    throw _prettyError('Certification failed', response);
  }

  /// Verify receipt against blockchain
  ///
  /// Backend returns:
  /// {
  ///   success:true,
  ///   verified, message,
  ///   chainHash, localHash,
  ///   chainCanonicalText, localCanonicalText
  /// }
  static Future<Map<String, dynamic>> verifyReceipt(String canonicalText, String txSignature) async {
    final response = await http.post(
      Uri.parse('$baseUrl/verify'),
      headers: _headers,
      body: jsonEncode({
        'canonicalText': canonicalText,
        'txSignature': txSignature,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Verification failed: invalid JSON response');
    }

    throw _prettyError('Verification failed', response);
  }

  /// NEW: Instant proof lookup (WOW endpoint)
  /// GET /proof/:txSignature
  static Future<Map<String, dynamic>> getProof(String txSignature) async {
    final response = await http.get(
      Uri.parse('$baseUrl/proof/$txSignature'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw Exception('Proof lookup failed: invalid JSON response');
    }

    throw _prettyError('Proof lookup failed', response);
  }

  /// NEW: Clipboard helper (no extra packages)
  static Future<void> copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
  }
}
