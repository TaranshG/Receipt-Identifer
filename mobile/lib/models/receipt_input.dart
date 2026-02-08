// lib/models/receipt_input.dart

/// User's manual input of receipt fields.
/// This replaces image capture since Gemini free tier doesn't support images.
class ReceiptInput {
  final String merchant;
  final String date;
  final String currency;
  final double subtotal;
  final double tax;
  final double total;

  const ReceiptInput({
    required this.merchant,
    required this.date,
    required this.currency,
    required this.subtotal,
    required this.tax,
    required this.total,
  });

  /// Validate that all required fields are filled
  bool get isValid {
    return merchant.trim().isNotEmpty &&
        date.trim().isNotEmpty &&
        currency.trim().isNotEmpty &&
        subtotal >= 0 &&
        tax >= 0 &&
        total >= 0;
  }

  /// Convert to JSON for API calls
  Map<String, dynamic> toJson() => {
        'merchant': merchant,
        'date': date,
        'currency': currency,
        'subtotal': subtotal,
        'tax': tax,
        'total': total,
      };

  /// Create from JSON
  factory ReceiptInput.fromJson(Map<String, dynamic> json) {
    double _toDouble(dynamic x) {
      if (x == null) return 0.0;
      if (x is num) return x.toDouble();
      if (x is String) {
        return double.tryParse(x.replaceAll(RegExp(r'[^0-9\.\-]'), '')) ?? 0.0;
      }
      return 0.0;
    }

    return ReceiptInput(
      merchant: (json['merchant'] ?? '').toString(),
      date: (json['date'] ?? '').toString(),
      currency: (json['currency'] ?? 'CAD').toString(),
      subtotal: _toDouble(json['subtotal']),
      tax: _toDouble(json['tax']),
      total: _toDouble(json['total']),
    );
  }

  /// Demo receipt A (legit)
  static ReceiptInput demoLegit() {
    return const ReceiptInput(
      merchant: 'Campus Mart',
      date: '2026-02-07',
      currency: 'CAD',
      subtotal: 12.49,
      tax: 1.62,
      total: 14.11, // Correct math
    );
  }

  /// Demo receipt B (tampered - wrong total)
  static ReceiptInput demoTampered() {
    return const ReceiptInput(
      merchant: 'Campus Mart',
      date: '2026-02-07',
      currency: 'CAD',
      subtotal: 12.49,
      tax: 1.62,
      total: 19.11, // Tampered! Should be 14.11
    );
  }

  /// Demo receipt C (blank for manual entry)
  static ReceiptInput empty() {
    return const ReceiptInput(
      merchant: '',
      date: '',
      currency: 'CAD',
      subtotal: 0.0,
      tax: 0.0,
      total: 0.0,
    );
  }

  /// Copy with modifications
  ReceiptInput copyWith({
    String? merchant,
    String? date,
    String? currency,
    double? subtotal,
    double? tax,
    double? total,
  }) {
    return ReceiptInput(
      merchant: merchant ?? this.merchant,
      date: date ?? this.date,
      currency: currency ?? this.currency,
      subtotal: subtotal ?? this.subtotal,
      tax: tax ?? this.tax,
      total: total ?? this.total,
    );
  }
}
