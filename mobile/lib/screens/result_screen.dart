import 'package:flutter/material.dart';
import '../models/receipt_analysis.dart';
import '../models/receipt_input.dart';
import '../services/api_service.dart';
import '../utils/trust_score.dart';
import '../utils/final_risk.dart';
import 'proof_screen.dart';

class ResultScreen extends StatefulWidget {
  final ReceiptAnalysis analysis;
  final ReceiptInput? receiptInput;

  const ResultScreen({super.key, required this.analysis, this.receiptInput});

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _certifying = false;
  late TrustScore _trustScore;
  late FinalRisk _finalRisk;

  @override
  void initState() {
    super.initState();
    _trustScore = TrustScore.compute(
      merchant: widget.analysis.merchant,
      date: widget.analysis.date,
      currency: widget.analysis.currency,
      subtotal: widget.analysis.subtotal,
      tax: widget.analysis.tax,
      total: widget.analysis.total,
    );

    _finalRisk = FinalRisk.resolve(
      analysis: widget.analysis,
      trustScore: _trustScore,
    );
  }

  String _buildCanonicalText(ReceiptAnalysis a) {
    String money(double v) => v.toStringAsFixed(2);
    final merchant = a.merchant.trim().toLowerCase();
    final date = a.date.trim();
    final currency = a.currency.trim().toUpperCase();

    return [
      'merchant=$merchant',
      'date=$date',
      'currency=$currency',
      'subtotal=${money(a.subtotal)}',
      'tax=${money(a.tax)}',
      'total=${money(a.total)}',
    ].join('\n');
  }

  Future<void> _certifyOnSolana() async {
    setState(() => _certifying = true);

    try {
      final canonicalText = _buildCanonicalText(widget.analysis);
      final certJson = await ApiService.certifyReceipt(canonicalText);

      final txSignature = (certJson['txSignature'] ?? '').toString();
      if (txSignature.isEmpty) throw Exception('Missing txSignature');

      final explorerUrl = certJson['explorerUrl']?.toString();
      final duplicate = certJson['duplicate'] == true;
      final seenCount = certJson['seenCount'] as int? ?? 1;
      final firstSeenTx = certJson['firstSeenTx']?.toString();
      final firstSeenAt = certJson['firstSeenAt']?.toString();

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProofScreen(
            txSignature: txSignature,
            explorerUrl: explorerUrl,
            duplicate: duplicate,
            seenCount: seenCount,
            firstSeenTx: firstSeenTx,
            firstSeenAt: firstSeenAt,
            receiptInput: widget.receiptInput,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Certification failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _certifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RiskCard(finalRisk: _finalRisk, trustScore: _trustScore, aiConfidence: widget.analysis.confidence),
            const SizedBox(height: 16),
            _WhyThisVerdictCard(finalRisk: _finalRisk, analysis: widget.analysis, trustScore: _trustScore),
            const SizedBox(height: 16),
            _FieldsCard(analysis: widget.analysis),
            const SizedBox(height: 20),
            Card(
              color: _finalRisk.level == RiskLevel.bad ? Colors.red.shade50 : Colors.blue.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _finalRisk.level == RiskLevel.bad
                      ? '⚠️ Create proof to lock state and detect future edits'
                      : '✅ Create proof to certify this receipt on blockchain',
                  style: TextStyle(
                    color: _finalRisk.level == RiskLevel.bad ? Colors.red.shade900 : Colors.blue.shade900,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _certifying ? null : _certifyOnSolana,
              icon: _certifying
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.verified),
              label: Text(_certifying ? 'Creating proof...' : 'Create Blockchain Proof'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RiskCard extends StatelessWidget {
  final FinalRisk finalRisk;
  final TrustScore trustScore;
  final double aiConfidence;

  const _RiskCard({required this.finalRisk, required this.trustScore, required this.aiConfidence});

  MaterialColor _getColor() {
    switch (finalRisk.level) {
      case RiskLevel.good:
        return Colors.green;
      case RiskLevel.warning:
        return Colors.orange;
      case RiskLevel.bad:
        return Colors.red;
    }
  }

  IconData _getIcon() {
    switch (finalRisk.level) {
      case RiskLevel.good:
        return Icons.check_circle;
      case RiskLevel.warning:
        return Icons.warning;
      case RiskLevel.bad:
        return Icons.cancel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();
    final icon = _getIcon();

    return Card(
      color: color[50],
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, color: color.shade700, size: 48),
            const SizedBox(height: 12),
            Text(
              finalRisk.badge,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color.shade900),
            ),
            const SizedBox(height: 6),
            Text(finalRisk.summary, style: TextStyle(color: color.shade700, fontSize: 14), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _metric('Trust Score', '${trustScore.score}/100', color),
                _metric('AI Confidence', '${(aiConfidence * 100).toStringAsFixed(0)}%', color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: (color as MaterialColor).shade900)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: (color as MaterialColor).shade600)),
      ],
    );
  }
}

class _WhyThisVerdictCard extends StatelessWidget {
  final FinalRisk finalRisk;
  final ReceiptAnalysis analysis;
  final TrustScore trustScore;

  const _WhyThisVerdictCard({required this.finalRisk, required this.analysis, required this.trustScore});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: Theme.of(context).colorScheme.primary, size: 20),
                const SizedBox(width: 8),
                Text('Why This Verdict?', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),

            // Main explanation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(finalRisk.explanation, style: const TextStyle(fontSize: 13)),
            ),

            const SizedBox(height: 16),

            // Rule-based checks
            Text('Rule-Based Checks', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            ...trustScore.checks.map((check) {
              Color chipColor;
              IconData icon;
              switch (check.status) {
                case 'pass':
                  chipColor = Colors.green;
                  icon = Icons.check_circle_outline;
                  break;
                case 'warn':
                  chipColor = Colors.orange;
                  icon = Icons.warning_amber;
                  break;
                default:
                  chipColor = Colors.red;
                  icon = Icons.error_outline;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(icon, color: (chipColor as MaterialColor).shade700, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${check.name}: ${check.description}', style: const TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              );
            }),

            // AI reasoning
            if (analysis.reasons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('AI Observations', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              ...analysis.reasons.map((r) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('•  ', style: TextStyle(fontSize: 12)),
                        Expanded(child: Text(r, style: const TextStyle(fontSize: 12))),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }
}

class _FieldsCard extends StatelessWidget {
  final ReceiptAnalysis analysis;
  const _FieldsCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Extracted Fields', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            _row('Merchant', analysis.merchant.isEmpty ? '—' : analysis.merchant),
            _row('Date', analysis.date.isEmpty ? '—' : analysis.date),
            _row('Currency', analysis.currency),
            const Divider(height: 24),
            _row('Subtotal', '${analysis.currency} ${analysis.money(analysis.subtotal)}'),
            _row('Tax', '${analysis.currency} ${analysis.money(analysis.tax)}'),
            _row('Total', '${analysis.currency} ${analysis.money(analysis.total)}'),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
          Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}