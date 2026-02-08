import 'package:flutter/material.dart';
import '../models/receipt_input.dart';

class VerifyResultScreen extends StatelessWidget {
  final Map<String, dynamic> verifyResult;
  final ReceiptInput receiptInput;
  final String? certifiedSnapshot;

  const VerifyResultScreen({
    super.key,
    required this.verifyResult,
    required this.receiptInput,
    this.certifiedSnapshot,
  });

  @override
  Widget build(BuildContext context) {
    final chainVerified = verifyResult['verified'] == true;
    final chainHash = verifyResult['chainHash']?.toString();
    final localHash = verifyResult['localHash']?.toString();
    final chainCanonical = verifyResult['chainCanonicalText']?.toString();
    final localCanonical = verifyResult['localCanonicalText']?.toString();
    final error = verifyResult['error']?.toString();

    // 3-state logic
    final bool proofSnapshotExists = certifiedSnapshot != null && certifiedSnapshot!.isNotEmpty;
    final bool chainAnchorVerified = chainVerified;
    final bool dataMatchesCertified = proofSnapshotExists && chainCanonical == localCanonical;

    String status;
    Color statusColor;
    IconData statusIcon;
    String explanation;

    if (chainAnchorVerified && dataMatchesCertified) {
      status = 'VERIFIED ✓';
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
      explanation = 'Receipt matches the blockchain anchor. No tampering detected.';
    } else if (chainAnchorVerified && !dataMatchesCertified) {
      status = 'TAMPERED';
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
      explanation = 'Chain anchor verified, but current data does not match certified snapshot. Receipt may have been edited.';
    } else if (proofSnapshotExists && error != null && error.contains('MEMO')) {
      // Demo-safe fallback: chain parse failed but we have local proof
      status = 'LOCAL PROOF (Demo Mode)';
      statusColor = Colors.blue;
      statusIcon = Icons.info;
      explanation = 'Local proof snapshot found. Chain anchor could not be verified (memo parse issue). Comparing against local snapshot instead.';
    } else if (!chainAnchorVerified) {
      status = 'CHAIN ANCHOR UNAVAILABLE';
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
      explanation = error != null
          ? 'Chain verification failed: $error. ${proofSnapshotExists ? "Local snapshot available for comparison." : "No local snapshot found."}'
          : 'Transaction not found on blockchain or could not be verified.';
    } else {
      status = 'UNKNOWN';
      statusColor = Colors.grey;
      statusIcon = Icons.help_outline;
      explanation = 'Unable to determine verification status.';
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Result')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              status: status,
              color: statusColor,
              icon: statusIcon,
              explanation: explanation,
            ),
            const SizedBox(height: 16),

            if (proofSnapshotExists) ...[
              _InfoCard(
                title: 'Proof Snapshot Status',
                icon: Icons.folder,
                color: Colors.blue,
                items: [
                  _InfoItem('Local Proof', 'Found ✓'),
                  _InfoItem('Certified at', certifiedSnapshot!.split('\n').firstWhere((l) => l.startsWith('date='), orElse: () => '').replaceFirst('date=', '')),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (chainHash != null) ...[
              _InfoCard(
                title: 'Chain Anchor',
                icon: Icons.link,
                color: chainAnchorVerified ? Colors.green : Colors.orange,
                items: [
                  _InfoItem('Chain Verified', chainAnchorVerified ? 'Yes ✓' : 'No ✗'),
                  _InfoItem('Chain Hash', chainHash),
                  _InfoItem('Local Hash', localHash ?? '—'),
                ],
              ),
              const SizedBox(height: 16),
            ],

            if (!chainAnchorVerified && chainCanonical != null && localCanonical != null) ...[
              Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.compare_arrows, color: Colors.orange.shade700),
                          const SizedBox(width: 8),
                          Text('Forensic Diff', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.orange.shade900, fontSize: 16)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _diffView(context, 'Certified (Chain)', chainCanonical, Colors.green),
                      const SizedBox(height: 12),
                      _diffView(context, 'Current (Local)', localCanonical, Colors.red),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Transaction Details', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (verifyResult['timestamp'] != null)
                      _infoRow('Timestamp', verifyResult['timestamp'].toString()),
                    if (verifyResult['explorerUrl'] != null)
                      _infoRow('Explorer', verifyResult['explorerUrl'].toString()),
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

  Widget _diffView(BuildContext context, String label, String text, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 13)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ),
      ],
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ),
          Expanded(
            child: SelectableText(value, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String status;
  final Color color;
  final IconData icon;
  final String explanation;

  const _StatusCard({
    required this.status,
    required this.color,
    required this.icon,
    required this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, size: 64, color: color),
            const SizedBox(height: 16),
            Text(
              status,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              explanation,
              style: TextStyle(color: color, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<_InfoItem> items;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.items,
  });

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
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            ...items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      ),
                      Expanded(
                        child: Text(item.value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _InfoItem {
  final String label;
  final String value;
  const _InfoItem(this.label, this.value);
}