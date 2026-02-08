// mobile/lib/utils/trust_score.dart
//
// Deterministic, explainable trust scoring (demo-safe)
// This is NOT AI. It gives stable, repeatable checks.

class TrustCheck {
  final String name;
  final String status; // 'pass' | 'warn' | 'fail'
  final int impact; // points deducted (0..)
  final String description;

  const TrustCheck({
    required this.name,
    required this.status,
    required this.impact,
    required this.description,
  });
}

class TrustScore {
  final int score; // 0..100
  final List<TrustCheck> checks;

  const TrustScore({required this.score, required this.checks});

  static TrustScore compute({
    required String merchant,
    required String date,
    required String currency,
    required double subtotal,
    required double tax,
    required double total,
  }) {
    final checks = <TrustCheck>[];
    var score = 100;

    // 1) Merchant presence
    final m = merchant.trim();
    if (m.isEmpty) {
      checks.add(const TrustCheck(
        name: 'Merchant present',
        status: 'fail',
        impact: 25,
        description: 'Merchant is missing.',
      ));
      score -= 25;
    } else if (m.length < 3) {
      checks.add(const TrustCheck(
        name: 'Merchant present',
        status: 'warn',
        impact: 8,
        description: 'Merchant looks unusually short.',
      ));
      score -= 8;
    } else {
      checks.add(const TrustCheck(
        name: 'Merchant present',
        status: 'pass',
        impact: 0,
        description: 'Merchant field looks okay.',
      ));
    }

    // 2) Math consistency: subtotal + tax ≈ total
    final expected = subtotal + tax;
    final diff = (expected - total).abs();
    if (diff <= 0.02) {
      checks.add(const TrustCheck(
        name: 'Math consistency',
        status: 'pass',
        impact: 0,
        description: 'Subtotal + tax matches total.',
      ));
    } else if (diff <= 0.25) {
      checks.add(TrustCheck(
        name: 'Math consistency',
        status: 'warn',
        impact: 10,
        description: 'Total is off by \$${diff.toStringAsFixed(2)} (possible rounding / entry error).',
      ));
      score -= 10;
    } else {
      checks.add(TrustCheck(
        name: 'Math consistency',
        status: 'fail',
        impact: 25,
        description: 'Total is off by \$${diff.toStringAsFixed(2)} (high risk).',
      ));
      score -= 25;
    }

    // 3) Currency sanity
    final c = currency.trim().toUpperCase();
    const common = {'CAD', 'USD', 'EUR', 'GBP', 'AUD'};
    if (c.isEmpty) {
      checks.add(const TrustCheck(
        name: 'Currency',
        status: 'warn',
        impact: 6,
        description: 'Currency missing.',
      ));
      score -= 6;
    } else if (!common.contains(c)) {
      checks.add(TrustCheck(
        name: 'Currency',
        status: 'warn',
        impact: 6,
        description: 'Uncommon currency: $c',
      ));
      score -= 6;
    } else {
      checks.add(const TrustCheck(
        name: 'Currency',
        status: 'pass',
        impact: 0,
        description: 'Currency looks normal.',
      ));
    }

    // 4) Tax plausibility (simple heuristic, demo-safe)
    // For CAD: Ontario HST 13% is common; allow a wide band
    if (subtotal <= 0 || total <= 0) {
      checks.add(const TrustCheck(
        name: 'Amounts positive',
        status: 'fail',
        impact: 25,
        description: 'Subtotal/total must be greater than 0.',
      ));
      score -= 25;
    } else {
      checks.add(const TrustCheck(
        name: 'Amounts positive',
        status: 'pass',
        impact: 0,
        description: 'Amounts are positive.',
      ));
    }

    if (subtotal > 0) {
      final rate = tax / subtotal; // e.g., 0.13
      if (tax == 0) {
        checks.add(const TrustCheck(
          name: 'Tax rate',
          status: 'warn',
          impact: 8,
          description: 'Tax is 0 (could be valid, but unusual).',
        ));
        score -= 8;
      } else if (c == 'CAD') {
        if (rate >= 0.02 && rate <= 0.20) {
          checks.add(TrustCheck(
            name: 'Tax rate',
            status: 'pass',
            impact: 0,
            description: 'Tax rate ${(rate * 100).toStringAsFixed(1)}% looks plausible.',
          ));
        } else if (rate > 0.20 && rate <= 0.35) {
          checks.add(TrustCheck(
            name: 'Tax rate',
            status: 'warn',
            impact: 10,
            description: 'Tax rate ${(rate * 100).toStringAsFixed(1)}% is high.',
          ));
          score -= 10;
        } else {
          checks.add(TrustCheck(
            name: 'Tax rate',
            status: 'fail',
            impact: 22,
            description: 'Tax rate ${(rate * 100).toStringAsFixed(1)}% is implausible.',
          ));
          score -= 22;
        }
      } else {
        // Non-CAD: lighter heuristic
        if (rate >= 0.00 && rate <= 0.35) {
          checks.add(TrustCheck(
            name: 'Tax rate',
            status: 'pass',
            impact: 0,
            description: 'Tax rate ${(rate * 100).toStringAsFixed(1)}% looks plausible.',
          ));
        } else {
          checks.add(TrustCheck(
            name: 'Tax rate',
            status: 'warn',
            impact: 10,
            description: 'Tax rate ${(rate * 100).toStringAsFixed(1)}% seems unusual.',
          ));
          score -= 10;
        }
      }
    }

    // 5) Date plausibility (NO timezone nonsense — parse YYYY-MM-DD only)
    final dateCheck = _checkDate(date);
    checks.add(dateCheck);
    score -= dateCheck.impact;

    // Clamp
    if (score < 0) score = 0;
    if (score > 100) score = 100;

    return TrustScore(score: score, checks: checks);
  }

  static TrustCheck _checkDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return const TrustCheck(
        name: 'Date',
        status: 'warn',
        impact: 8,
        description: 'Date missing.',
      );
    }

    // Accept YYYY-MM-DD OR YYYY-MM-DD HH:MM
    final datePart = s.split(' ').first;
    final re = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!re.hasMatch(datePart)) {
      return const TrustCheck(
        name: 'Date',
        status: 'warn',
        impact: 8,
        description: 'Date format should be YYYY-MM-DD.',
      );
    }

    final parts = datePart.split('-');
    final y = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;

    DateTime parsed;
    try {
      parsed = DateTime(y, m, d); // local midnight, safe for comparisons
    } catch (_) {
      return const TrustCheck(
        name: 'Date',
        status: 'fail',
        impact: 18,
        description: 'Invalid date.',
      );
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Future date?
    if (parsed.isAfter(today)) {
      return TrustCheck(
        name: 'Date',
        status: 'fail',
        impact: 25,
        description: 'Date is in the future (${datePart}).',
      );
    }

    // Too old? (example: > 365 days)
    final daysOld = today.difference(parsed).inDays;
    if (daysOld > 365) {
      return TrustCheck(
        name: 'Date',
        status: 'warn',
        impact: 10,
        description: 'Receipt is $daysOld days old (older than 1 year).',
      );
    }

    return TrustCheck(
      name: 'Date',
      status: 'pass',
      impact: 0,
      description: 'Date looks valid (${datePart}).',
    );
  }
}
