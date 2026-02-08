// lib/screens/verify_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../models/receipt_input.dart';
import '../../../models/verify_result.dart';
import '../services/receipt_service.dart';
import 'entry_screen.dart';

class VerifyScreen extends StatefulWidget {
  final String? initialTxSignature;
  const VerifyScreen({super.key, this.initialTxSignature});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  late final TextEditingController _txController;

  ReceiptInput? _receiptInput;
  VerifyResult? _result;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _txController =
        TextEditingController(text: widget.initialTxSignature ?? '');
  }

  @override
  void dispose() {
    _txController.dispose();
    super.dispose();
  }

  Future<void> _enterReceipt() async {
    final result = await Navigator.push<ReceiptInput>(
      context,
      MaterialPageRoute(
        builder: (_) => const _VerifyEntryScreen(),
      ),
    );

    if (result != null) {
      setState(() {
        _receiptInput = result;
        _result = null; // Clear previous result
      });
    }
  }

  Future<void> _scanQr() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QrScanPage(
          onScanned: (value) {
            _txController.text = value;
          },
        ),
      ),
    );
    setState(() {}); // Refresh UI after scan
  }

  Future<void> _verify() async {
    if (_receiptInput == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter receipt data first')),
      );
      return;
    }

    if (_txController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please enter or scan a transaction signature')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      // Call Person 2 + 3's verification logic
      final result = await ReceiptService.verifyReceipt(
        _receiptInput!,
        _txController.text.trim(),
      );

      if (!mounted) return;
      setState(() {
        _result = result;
        _verifying = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    }
  }

  // Demo buttons for testing UI flow
  void _demoVerify(bool ok) {
    if (_receiptInput == null) {
      setState(() => _receiptInput = ReceiptInput.demoLegit());
    }
    setState(() {
      _result = ok ? VerifyResult.demoVerified() : VerifyResult.demoTampered();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Result badge
            if (_result != null) ...[
              _ResultBadge(result: _result!),
              const SizedBox(height: 20),
            ],

            // Receipt data preview
            if (_receiptInput != null) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle,
                            color: Colors.green.shade700, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Receipt Data Entered',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.green.shade900,
                                  ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _InfoRow('Merchant', _receiptInput!.merchant),
                    _InfoRow('Date', _receiptInput!.date),
                    _InfoRow('Total',
                        '${_receiptInput!.currency} ${_receiptInput!.total.toStringAsFixed(2)}'),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Enter receipt button
            OutlinedButton.icon(
              onPressed: _verifying ? null : _enterReceipt,
              icon: const Icon(Icons.edit_document),
              label: Text(_receiptInput == null
                  ? 'Enter Receipt Data'
                  : 'Change Receipt Data'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 20),

            // Transaction signature input
            Text(
              'Solana Transaction Signature',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _txController,
              decoration: const InputDecoration(
                hintText: 'Enter or scan tx signature',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),

            OutlinedButton.icon(
              onPressed: _verifying ? null : _scanQr,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan QR Code'),
            ),

            const SizedBox(height: 24),

            // Main verify button
            ElevatedButton.icon(
              onPressed: _verifying ? null : _verify,
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_user),
              label: Text(_verifying ? 'Verifying...' : 'Verify Receipt'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),

            // Demo buttons (for testing without backend)
            Text(
              'Demo Mode (for testing)',
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _demoVerify(true),
                    child: const Text('Demo: Match'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _demoVerify(false),
                    child: const Text('Demo: Mismatch'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'How it works: We recompute the receipt fingerprint from your entered data and compare it to the fingerprint stored in the Solana transaction.',
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

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultBadge extends StatelessWidget {
  final VerifyResult result;
  const _ResultBadge({required this.result});

  @override
  Widget build(BuildContext context) {
    final verified = result.verified;
    final badgeText = verified ? 'VERIFIED ✓' : 'NOT VERIFIED ✗';
    final bgColor = verified ? Colors.green.shade100 : Colors.red.shade100;
    final textColor = verified ? Colors.green.shade900 : Colors.red.shade900;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          Text(
            badgeText,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            result.message,
            style: TextStyle(color: textColor),
            textAlign: TextAlign.center,
          ),
          if (result.chainHash != null && result.localHash != null) ...[
            const SizedBox(height: 12),
            Text(
              'Chain: ${result.chainHash}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: textColor.withOpacity(0.8),
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              'Local: ${result.localHash}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontFamily: 'monospace',
                    color: textColor.withOpacity(0.8),
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Simplified entry screen for verification (returns ReceiptInput)
class _VerifyEntryScreen extends StatefulWidget {
  const _VerifyEntryScreen();

  @override
  State<_VerifyEntryScreen> createState() => _VerifyEntryScreenState();
}

class _VerifyEntryScreenState extends State<_VerifyEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _merchantController;
  late TextEditingController _dateController;
  late TextEditingController _currencyController;
  late TextEditingController _subtotalController;
  late TextEditingController _taxController;
  late TextEditingController _totalController;

  @override
  void initState() {
    super.initState();
    _merchantController = TextEditingController();
    _dateController = TextEditingController();
    _currencyController = TextEditingController(text: 'CAD');
    _subtotalController = TextEditingController();
    _taxController = TextEditingController();
    _totalController = TextEditingController();
  }

  @override
  void dispose() {
    _merchantController.dispose();
    _dateController.dispose();
    _currencyController.dispose();
    _subtotalController.dispose();
    _taxController.dispose();
    _totalController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final input = ReceiptInput(
      merchant: _merchantController.text.trim(),
      date: _dateController.text.trim(),
      currency: _currencyController.text.trim().toUpperCase(),
      subtotal: double.parse(_subtotalController.text),
      tax: double.parse(_taxController.text),
      total: double.parse(_totalController.text),
    );

    Navigator.pop(context, input);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Enter Receipt for Verification')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _merchantController,
                decoration: const InputDecoration(
                  labelText: 'Merchant *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dateController,
                decoration: const InputDecoration(
                  labelText: 'Date *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _currencyController,
                decoration: const InputDecoration(
                  labelText: 'Currency *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) => v?.trim().isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _subtotalController,
                decoration: const InputDecoration(
                  labelText: 'Subtotal *',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Invalid' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _taxController,
                decoration: const InputDecoration(
                  labelText: 'Tax *',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Invalid' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _totalController,
                decoration: const InputDecoration(
                  labelText: 'Total *',
                  border: OutlineInputBorder(),
                ),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                validator: (v) =>
                    double.tryParse(v ?? '') == null ? 'Invalid' : null,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QrScanPage extends StatelessWidget {
  final void Function(String value) onScanned;

  const _QrScanPage({required this.onScanned});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;
          final raw = barcodes.first.rawValue;
          if (raw == null || raw.isEmpty) return;

          onScanned(raw);
          Navigator.pop(context);
        },
      ),
    );
  }
}
