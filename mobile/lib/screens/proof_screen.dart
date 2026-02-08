// mobile/lib/screens/proof_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/receipt_input.dart';
import 'verify_screen.dart';

class ProofScreen extends StatelessWidget {
  final String txSignature;
  final String? explorerUrl;
  final bool? duplicate;
  final String? firstSeenTx;
  final String? firstSeenAt;
  final ReceiptInput? receiptInput;

  const ProofScreen({
    super.key,
    required this.txSignature,
    this.explorerUrl,
    this.duplicate,
    this.firstSeenTx,
    this.firstSeenAt,
    this.receiptInput,
  });

  String get proofPayload {
    final uri = Uri(
      scheme: 'vericeipt',
      host: 'proof',
      queryParameters: {
        'tx': txSignature,
        'v': '1',
      },
    );
    return uri.toString();
  }

  Future<void> _copy(BuildContext context, String text, {String toast = 'Copied'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(toast), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDup = duplicate == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Icon(Icons.verified, size: 64, color: Colors.green.shade600),
          const SizedBox(height: 16),

          Text(
            'Proof Created on Solana',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isDup ? '⚠️ Hash seen before (possible duplicate claim)' : 'This receipt is now tamper-evident',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Privacy: only a fingerprint is anchored — no receipt image stored on-chain.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),

          if (isDup) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Text(
                'Duplicate signal: this receipt hash was previously certified.\n'
                'First seen: ${firstSeenAt ?? "—"}\n'
                'First tx: ${firstSeenTx ?? "—"}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 18),
          ],

          // Tx signature card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('Transaction Signature', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, txSignature),
                  tooltip: 'Copy tx signature',
                ),
              ]),
              const SizedBox(height: 8),
              SelectableText(
                txSignature,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              if (explorerUrl != null && explorerUrl!.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                TextButton.icon(
                  onPressed: () => _copy(context, explorerUrl!, toast: 'Explorer link copied'),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Copy Solana Explorer link'),
                ),
              ],
            ]),
          ),

          const SizedBox(height: 18),

          // Proof payload card (what QR encodes)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Text('Proof Payload', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () => _copy(context, proofPayload, toast: 'Proof payload copied'),
                  tooltip: 'Copy proof payload',
                ),
              ]),
              const SizedBox(height: 8),
              SelectableText(
                proofPayload,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ]),
          ),

          const SizedBox(height: 24),

          // QR Code (smart payload)
          Center(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(children: [
                QrImageView(data: proofPayload, size: 210, backgroundColor: Colors.white),
                const SizedBox(height: 8),
                Text('Scan to verify', style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
          ),

          const SizedBox(height: 20),

          // Share proof (one button that judges will notice)
          ElevatedButton.icon(
            onPressed: () {
              final pack = [
                'VeriCeipt Proof',
                'tx: $txSignature',
                'payload: $proofPayload',
                if (explorerUrl != null && explorerUrl!.trim().isNotEmpty) 'explorer: $explorerUrl',
              ].join('\n');

              _copy(context, pack, toast: 'Proof pack copied');
            },
            icon: const Icon(Icons.share),
            label: const Text('Copy Proof Pack'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),

          const SizedBox(height: 24),

          if (receiptInput != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Certified Receipt', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _InfoRow('Merchant', receiptInput!.merchant),
                _InfoRow('Date', receiptInput!.date),
                _InfoRow('Total', '${receiptInput!.currency} ${receiptInput!.total.toStringAsFixed(2)}'),
              ]),
            ),
            const SizedBox(height: 24),
          ],

          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => VerifyScreen(initialTxSignature: txSignature)),
              );
            },
            icon: const Icon(Icons.verified_user),
            label: const Text('Verify a Receipt'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            icon: const Icon(Icons.home),
            label: const Text('Back to Home'),
          ),
        ]),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(child: Text(value, textAlign: TextAlign.right)),
      ]),
    );
  }
}
