// lib/screens/result_screen.dart

import 'package:flutter/material.dart';

import '../models/receipt_analysis.dart';
import '../models/receipt_input.dart';
import '../services/api_service.dart';
import 'proof_screen.dart';

class ResultScreen extends StatefulWidget {
  final ReceiptAnalysis analysis;
  final ReceiptInput? receiptInput;

  const ResultScreen({
    super.key,
    required this.analysis,
    this.receiptInput,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  bool _certifying = false;

  /// Builds canonical text locally (so we don't need analysis.canonicalText field).
  String _buildCanonicalText(ReceiptAnalysis a) {
    String money(double v) => v.toStringAsFixed(2);
    return [
      'merchant=${a.merchant.trim()}',
      'date=${a.date.trim()}',
      'currency=${a.currency.trim().toUpperCase()}',
      'subtotal=${money(a.subtotal)}',
      'tax=${money(a.tax)}',
      'total=${money(a.total)}',
    ].join('\n');
  }

  Future<void> _certifyOnSolana() async {
    setState(() => _certifying = true);

    try {
      // Uses backend endpoint: POST /certify with canonicalText
      final canonicalText = _buildCanonicalText(widget.analysis);
      final certJson = await ApiService.certifyReceipt(canonicalText);

      final txSignature = (certJson['txSignature'] ?? '').toString();
      if (txSignature.isEmpty) {
        throw Exception('Missing txSignature from backend.');
      }

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProofScreen(
            txSignature: txSignature,
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
      appBar: AppBar(title: const Text('Analysis')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VerdictHeader(analysis: widget.analysis),
            const SizedBox(height: 16),
            _KeyFieldsCard(analysis: widget.analysis),
            const SizedBox(height: 16),
            _ReasonsCard(analysis: widget.analysis),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _certifying ? null : _certifyOnSolana,
              icon: _certifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified),
              label: Text(_certifying ? 'Certifying...' : 'Certify on Solana'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _certifying ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.edit),
              label: const Text('Edit Receipt'),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Certified = This receipt fingerprint is timestamped on Solana. Future verification can detect edits.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerdictHeader extends StatelessWidget {
  final ReceiptAnalysis analysis;
  const _VerdictHeader({required this.analysis});

  Color _getVerdictColor(BuildContext context) {
    switch (analysis.verdict) {
      case 'LIKELY_REAL':
        return Colors.green.shade100;
      case 'SUSPICIOUS':
        return Colors.red.shade100;
      case 'UNREADABLE':
        return Colors.orange.shade100;
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  Color _getTextColor() {
    switch (analysis.verdict) {
      case 'LIKELY_REAL':
        return Colors.green.shade900;
      case 'SUSPICIOUS':
        return Colors.red.shade900;
      case 'UNREADABLE':
        return Colors.orange.shade900;
      default:
        return Colors.black87;
    }
  }

  @override
  Widget build(BuildContext context) {
    final badge = analysis.badgeText;
    final score = analysis.fraudScore;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _getVerdictColor(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _getTextColor().withOpacity(0.3),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Text(
            badge,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: _getTextColor(),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            analysis.subtitle,
            style: TextStyle(color: _getTextColor()),
          ),
          const SizedBox(height: 12),
          Text(
            'Fraud Score: $score / 100',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: _getTextColor(),
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Confidence: ${(analysis.confidence * 100).toStringAsFixed(0)}%',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _getTextColor(),
                ),
          ),
        ],
      ),
    );
  }
}

class _KeyFieldsCard extends StatelessWidget {
  final ReceiptAnalysis analysis;
  const _KeyFieldsCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  k,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  v,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Extracted Fields',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          row('Merchant', analysis.merchant.isEmpty ? '—' : analysis.merchant),
          row('Date', analysis.date.isEmpty ? '—' : analysis.date),
          row('Currency', analysis.currency),
          const Divider(height: 18),
          row('Subtotal',
              '${analysis.currency} ${analysis.money(analysis.subtotal)}'),
          row('Tax', '${analysis.currency} ${analysis.money(analysis.tax)}'),
          row('Total',
              '${analysis.currency} ${analysis.money(analysis.total)}'),
        ],
      ),
    );
  }
}

class _ReasonsCard extends StatelessWidget {
  final ReceiptAnalysis analysis;
  const _ReasonsCard({required this.analysis});

  @override
  Widget build(BuildContext context) {
    final reasons =
        analysis.reasons.isEmpty ? ['No reasons provided.'] : analysis.reasons;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Why', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...reasons.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('•  '),
                  Expanded(child: Text(r)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
