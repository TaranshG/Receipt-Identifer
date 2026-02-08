import '../models/receipt_analysis.dart';
import 'trust_score.dart';

enum RiskLevel { good, warning, bad }

class FinalRisk {
  final RiskLevel level;
  final String badge;
  final String summary;
  final String explanation;

  const FinalRisk({
    required this.level,
    required this.badge,
    required this.summary,
    required this.explanation,
  });

  // Deterministic resolver: AI + TrustScore → single decision
  static FinalRisk resolve({
    required ReceiptAnalysis analysis,
    required TrustScore trustScore,
  }) {
    // Hard fails override everything
    final mathFail = trustScore.checks.any((c) => c.name == 'Math Consistency' && c.status == 'fail');
    final aiSaysFake = analysis.verdict == 'LIKELY_FAKE';
    final aiSaysSuspicious = analysis.verdict == 'SUSPICIOUS';
    final lowTrust = trustScore.score < 50;

    // BAD: Math fail or AI says fake or very low trust
    if (mathFail || aiSaysFake || lowTrust) {
      String explanation;
      if (mathFail) {
        explanation = 'Total does not match subtotal + tax. This is a critical inconsistency.';
      } else if (aiSaysFake) {
        explanation = 'AI flagged as likely fake. ${analysis.reasons.isNotEmpty ? analysis.reasons.first : ""}';
      } else {
        explanation = 'Low trust score (${trustScore.score}/100). Multiple red flags detected.';
      }

      return FinalRisk(
        level: RiskLevel.bad,
        badge: 'HIGH RISK',
        summary: 'Do not reimburse without further review',
        explanation: explanation,
      );
    }

    // WARNING: AI suspicious or moderate trust issues
    if (aiSaysSuspicious || trustScore.score < 70) {
      final reasons = <String>[];
      if (aiSaysSuspicious) reasons.add('AI flagged as suspicious');
      if (trustScore.score < 70) reasons.add('Trust score ${trustScore.score}/100');

      return FinalRisk(
        level: RiskLevel.warning,
        badge: 'REVIEW NEEDED',
        summary: 'Some inconsistencies detected',
        explanation: reasons.join('; ') + '. Manual review recommended.',
      );
    }

    // GOOD: AI says likely real + high trust
    return const FinalRisk(
      level: RiskLevel.good,
      badge: 'LOW RISK',
      summary: 'Receipt appears legitimate',
      explanation: 'All checks passed. No significant red flags detected.',
    );
  }
}