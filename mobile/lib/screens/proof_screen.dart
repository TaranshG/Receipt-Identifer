import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/receipt_input.dart';

class ProofScreen extends StatelessWidget {
  final String txSignature;
  final String? explorerUrl;
  final bool? duplicate;
  final int? seenCount;
  final String? firstSeenTx;
  final String? firstSeenAt;
  final ReceiptInput? receiptInput;

  const ProofScreen({
    super.key,
    required this.txSignature,
    this.explorerUrl,
    this.duplicate,
    this.seenCount,
    this.firstSeenTx,
    this.firstSeenAt,
    this.receiptInput,
  });

  String get proofPayload {
    final uri = Uri(
      scheme: 'vericeipt',
      host: 'proof',
      queryParameters: {'tx': txSignature, 'v': '1'},
    );
    return uri.toString();
  }

  Future<void> _copy(BuildContext context, String text, String toast) async {
    await Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(toast), duration: const Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDup = duplicate == true;
    final count = seenCount ?? 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Blockchain Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.verified, size: 64, color: Colors.green.shade600),
            const SizedBox(height: 16),
            Text(
              'Proof Created ✓',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Receipt fingerprint anchored on Solana',
              style: TextStyle(color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // WOW Feature 2: Duplicate Badge
            if (isDup)
              Card(
                color: Colors.amber.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.warning, color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Duplicate Detected',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Colors.amber.shade900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.amber.shade300),
                            ),
                            child: Text(
                              'Seen ${count}x',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Colors.amber.shade900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _infoRow('Risk', 'Possible duplicate claim', Icons.error_outline),
                      _infoRow('First Seen', firstSeenAt ?? '—', Icons.access_time),
                      _infoRow('First Tx', firstSeenTx ?? '—', Icons.link),
                    ],
                  ),
                ),
              ),

            if (isDup) const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Transaction Signature', style: Theme.of(context).textTheme.titleSmall),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          onPressed: () => _copy(context, txSignature, 'Tx copied'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      txSignature,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                    if (explorerUrl != null) ...[
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () => _copy(context, explorerUrl!, 'Explorer link copied'),
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('Copy Explorer Link'),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // WOW Feature 3: QR Code with proof payload
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Scan to Verify', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(data: proofPayload, size: 200, backgroundColor: Colors.white),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => _copy(context, proofPayload, 'Proof payload copied'),
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy Payload'),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            ElevatedButton.icon(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              icon: const Icon(Icons.home),
              label: const Text('Back to Home'),
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

  Widget _infoRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.amber.shade700),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}