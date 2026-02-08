// lib/models/receipt_analysis.dart

/// The structured result returned by Gemini.
/// Keep this model stable: it becomes the contract between AI + UI + proof logic.
class ReceiptAnalysis {
  final String merchant;
  final String date; // Keep as string to avoid parsing issues from OCR/AI
  final String currency; // e.g., "CAD", "USD"
  final double subtotal;
  final double tax;
  final double total;

  /// "LIKELY_REAL" | "SUSPICIOUS" | "UNREADABLE"
  final String verdict;

  /// 0–100. Higher = more suspicious.
  final int fraudScore;

  /// Short bullets suitable for judges.
  final List<String> reasons;

  /// 0.0–1.0 confidence from Gemini (or our own estimate).
  final double confidence;

  /// Optional: set later when you compute the canonical hash for proof.
  final String? canonicalHash;

  const ReceiptAnalysis({
    required this.merchant,
    required this.date,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
    required this.verdict,
    required this.fraudScore,
    required this.reasons,
    required this.confidence,
    this.canonicalHash,
  });

  /// UI helper: big badge text (judge-friendly)
  String get badgeText {
    switch (verdict) {
      case 'LIKELY_REAL':
        return 'LIKELY REAL';
      case 'SUSPICIOUS':
        return 'SUSPICIOUS';
      case 'UNREADABLE':
        return 'UNREADABLE';
      default:
        return verdict;
    }
  }

  /// UI helper: small one-liner explanation (judge-friendly)
  String get subtitle {
    if (verdict == 'LIKELY_REAL') return 'Fields look consistent.';
    if (verdict == 'SUSPICIOUS') return 'Inconsistencies detected.';
    if (verdict == 'UNREADABLE') return 'Try a clearer photo.';
    return '';
  }

  /// For demo polish: format money consistently
  String money(double v) => v.toStringAsFixed(2);
  
  /// JSON parsing for when Gemini returns structured output.
  /// Keep tolerant: Gemini might return numbers as strings.
  factory ReceiptAnalysis.fromJson(Map<String, dynamic> json) {
    double _toDouble(dynamic x) {
      if (x == null) return 0.0;
      if (x is num) return x.toDouble();
      if (x is String) return double.tryParse(x.replaceAll(RegExp(r'[^0-9\.\-]'), '')) ?? 0.0;
      return 0.0;
    }

    int _toInt(dynamic x) {
      if (x == null) return 0;
      if (x is int) return x;
      if (x is num) return x.round();
      if (x is String) return int.tryParse(x.replaceAll(RegExp(r'[^0-9\-]'), '')) ?? 0;
      return 0;
    }

    List<String> _toStringList(dynamic x) {
      if (x is List) return x.map((e) => e.toString()).toList();
      return const <String>[];
    }

    return ReceiptAnalysis(
      merchant: (json['merchant'] ?? '').toString().trim(),
      date: (json['date'] ?? '').toString().trim(),
      currency: (json['currency'] ?? 'USD').toString().trim().toUpperCase(),
      subtotal: _toDouble(json['subtotal']),
      tax: _toDouble(json['tax']),
      total: _toDouble(json['total']),
      verdict: (json['verdict'] ?? 'UNREADABLE').toString().trim(),
      fraudScore: _toInt(json['fraud_score']),
      reasons: _toStringList(json['reasons']),
      confidence: _toDouble(json['confidence']).clamp(0.0, 1.0),
      canonicalHash: json['canonical_hash']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'merchant': merchant,
        'date': date,
        'currency': currency,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
        'verdict': verdict,
        'fraud_score': fraudScore,
        'reasons': reasons,
        'confidence': confidence,
        if (canonicalHash != null) 'canonical_hash': canonicalHash,
      };

  /// Demo sample: a clean, consistent receipt (Receipt A).
  static ReceiptAnalysis demoLegit() {
    return const ReceiptAnalysis(
      merchant: 'Campus Mart',
      date: '2026-02-07 14:12',
      currency: 'CAD',
      subtotal: 12.49,
      tax: 1.62,
      total: 14.11,
      verdict: 'LIKELY_REAL',
      fraudScore: 12,
      reasons: [
        'Subtotal + tax matches total (within rounding).',
        'Merchant, date, and currency present.',
        'No contradictory totals detected.',
      ],
      confidence: 0.87,
    );
  }

  /// Demo sample: a tampered version (Receipt B) with inconsistent totals.
  static ReceiptAnalysis demoTampered() {
    return const ReceiptAnalysis(
      merchant: 'Campus Mart',
      date: '2026-02-07 14:12',
      currency: 'CAD',
      subtotal: 12.49,
      tax: 1.62,
      total: 19.11, // edited total to simulate fraud
      verdict: 'SUSPICIOUS',
      fraudScore: 86,
      reasons: [
        'Total does not equal subtotal + tax.',
        'Total appears edited relative to other values.',
        'Recommend manual review or re-scan.',
      ],
      confidence: 0.82,
    );
  }

  /// Demo sample: unreadable receipt (blurry / missing fields).
  static ReceiptAnalysis demoUnreadable() {
    return const ReceiptAnalysis(
      merchant: '',
      date: '',
      currency: 'CAD',
      subtotal: 0.0,
      tax: 0.0,
      total: 0.0,
      verdict: 'UNREADABLE',
      fraudScore: 50,
      reasons: [
        'Could not confidently read the total or date.',
        'Try brighter lighting and fill the frame with the receipt.',
      ],
      confidence: 0.25,
    );
  }
}
