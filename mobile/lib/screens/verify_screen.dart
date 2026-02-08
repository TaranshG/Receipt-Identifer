// mobile/lib/screens/verify_screen.dart

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/receipt_input.dart';
import '../models/verify_result.dart';
import '../services/api_service.dart';

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

  String? _chainCanonicalText;
  String? _localCanonicalText;

  // NEW: Proof lookup bundle (from GET /proof/:tx)
  Map<String, dynamic>? _proofBundle;
  bool _loadingProof = false;
  String? _proofError;

  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    _txController = TextEditingController(text: widget.initialTxSignature ?? '');

    // If initial tx exists, attempt proof lookup immediately
    final initial = _txController.text.trim();
    if (initial.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchProofBundle(initial);
      });
    }

    // Optional: auto proof lookup when user edits tx field (debounced-ish)
    _txController.addListener(() {
      final tx = _txController.text.trim();
      // Don't spam calls while verifying
      if (_verifying || tx.length < 20) return;
    });
  }

  @override
  void dispose() {
    _txController.dispose();
    super.dispose();
  }

  String _buildCanonicalText(ReceiptInput input) {
    final merchant = input.merchant.trim().toLowerCase();
    final date = input.date.trim();
    final currency = input.currency.trim().toUpperCase();
    final subtotal = input.subtotal.toStringAsFixed(2);
    final tax = input.tax.toStringAsFixed(2);
    final total = input.total.toStringAsFixed(2);

    return 'merchant=$merchant\n'
        'date=$date\n'
        'currency=$currency\n'
        'subtotal=$subtotal\n'
        'tax=$tax\n'
        'total=$total';
  }

  Map<String, String> _parseCanonical(String? text) {
    if (text == null || text.trim().isEmpty) return {};
    final lines = text.split('\n');
    final map = <String, String>{};
    for (final line in lines) {
      final idx = line.indexOf('=');
      if (idx <= 0) continue;
      final k = line.substring(0, idx).trim();
      final v = line.substring(idx + 1).trim();
      map[k] = v;
    }
    return map;
  }

  Future<void> _enterReceipt() async {
    final result = await Navigator.push<ReceiptInput>(
      context,
      MaterialPageRoute(builder: (_) => const _VerifyEntryScreen()),
    );

    if (result != null) {
      setState(() {
        _receiptInput = result;
        _result = null;
        _chainCanonicalText = null;
        _localCanonicalText = null;
      });
    }
  }

  String _extractTxFromQr(String raw) {
    // Supports:
    // 1) raw tx signature
    // 2) vericeipt://proof?tx=...&v=1
    try {
      if (raw.startsWith('vericeipt://')) {
        final uri = Uri.parse(raw);
        final tx = uri.queryParameters['tx'];
        if (tx != null && tx.trim().isNotEmpty) return tx.trim();
      }
    } catch (_) {}
    return raw.trim();
  }

  Future<void> _scanQr() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _QrScanPage(
          onScanned: (raw) {
            final tx = _extractTxFromQr(raw);
            _txController.text = tx;
          },
        ),
      ),
    );

    final tx = _txController.text.trim();
    if (tx.isNotEmpty) {
      await _fetchProofBundle(tx);
    }

    if (mounted) setState(() {});
  }

  Future<void> _fetchProofBundle(String txSignature) async {
    final tx = txSignature.trim();
    if (tx.isEmpty) return;

    setState(() {
      _loadingProof = true;
      _proofError = null;
      _proofBundle = null;
    });

    try {
      final json = await ApiService.getProof(tx);
      if (!mounted) return;

      setState(() {
        _proofBundle = json;
        _loadingProof = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProof = false;
        _proofError = e.toString();
      });
    }
  }

  Future<void> _verify() async {
    if (_receiptInput == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter receipt data first')),
      );
      return;
    }

    final tx = _txController.text.trim();
    if (tx.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter or scan a transaction signature')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      // Always re-fetch proof bundle once before verify (latest local store)
      await _fetchProofBundle(tx);

      final localCanonical = _buildCanonicalText(_receiptInput!);
      final json = await ApiService.verifyReceipt(localCanonical, tx);

      final verified = json['verified'] == true;
      final message = (json['message'] ?? (verified ? 'VERIFIED' : 'NOT VERIFIED')).toString();
      final chainHash = json['chainHash']?.toString();
      final localHash = json['localHash']?.toString();

      final chainCanon = json['chainCanonicalText']?.toString();
      final localCanon = json['localCanonicalText']?.toString();

      if (!mounted) return;
      setState(() {
        _result = VerifyResult(
          verified: verified,
          message: message,
          chainHash: chainHash,
          localHash: localHash,
        );
        _chainCanonicalText = chainCanon;
        _localCanonicalText = localCanon;
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

  void _demoVerify(bool ok) {
    if (_receiptInput == null) setState(() => _receiptInput = ReceiptInput.demoLegit());
    setState(() {
      _result = ok ? VerifyResult.demoVerified() : VerifyResult.demoTampered();
      _chainCanonicalText = ok ? _buildCanonicalText(_receiptInput!) : 'merchant=demo\nsubtotal=10.00\ntax=1.30\ntotal=12.34\ncurrency=CAD\ndate=2026-02-08';
      _localCanonicalText = _buildCanonicalText(_receiptInput!);

      _proofBundle = {
        "success": true,
        "found": true,
        "txSignature": "DEMO_TX_SIGNATURE_123",
        "hash": "demo_hash",
        "duplicate": !ok,
        "seenCount": ok ? 1 : 3,
        "firstSeenAt": "2026-02-08T09:00:00Z",
        "firstSeenTx": "DEMO_FIRST_TX_456",
        "explorerUrl": "https://explorer.solana.com/tx/DEMO?cluster=devnet",
        "canonicalText": _chainCanonicalText,
      };
      _proofError = null;
      _loadingProof = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final chainMap = _parseCanonical(_chainCanonicalText);
    final localMap = _parseCanonical(_localCanonicalText);

    final keys = <String>{...chainMap.keys, ...localMap.keys}.toList()..sort();
    final showDiff = _result != null && _result!.verified == false && keys.isNotEmpty;

    final proofFound = _proofBundle != null && (_proofBundle!['found'] == true || _proofBundle!['success'] == true);
    final dup = proofFound && (_proofBundle!['duplicate'] == true);
    final seenCount = proofFound ? (_proofBundle!['seenCount']?.toString() ?? '1') : null;
    final firstSeenAt = proofFound ? (_proofBundle!['firstSeenAt']?.toString() ?? '—') : null;
    final explorerUrl = proofFound ? (_proofBundle!['explorerUrl']?.toString()) : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Verify Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_result != null) ...[
            _ResultBadge(result: _result!),
            const SizedBox(height: 16),
          ],

          // NEW: Proof Lookup Card (instant product feel)
          _ProofLookupCard(
            tx: _txController.text.trim(),
            loading: _loadingProof,
            error: _proofError,
            bundle: _proofBundle,
            onRefresh: _verifying ? null : () => _fetchProofBundle(_txController.text.trim()),
          ),

          if (proofFound) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: dup ? Colors.amber.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: dup ? Colors.amber.shade200 : Colors.blue.shade200),
              ),
              child: Text(
                dup
                    ? '⚠️ Duplicate signal: this fingerprint was certified before.\nSeen count: $seenCount\nFirst seen: $firstSeenAt'
                    : '✅ Proof record found on this server.\nSeen count: $seenCount\nFirst seen: $firstSeenAt',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],

          if (explorerUrl != null && explorerUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                await ApiService.copyToClipboard(explorerUrl);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Explorer link copied'), duration: Duration(seconds: 1)),
                );
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Copy Solana Explorer Link'),
            ),
          ],

          const SizedBox(height: 16),

          if (showDiff) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(
                  'Forensic Replay: What Changed?',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                ...keys.map((k) {
                  final c = chainMap[k] ?? '—';
                  final l = localMap[k] ?? '—';
                  final match = c == l;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: match ? Colors.green.shade50 : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: match ? Colors.green.shade200 : Colors.red.shade200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(k, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text('Certified: $c', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      Text('Current:   $l', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                    ]),
                  );
                }),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          if (_receiptInput != null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Receipt Data Entered',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.green.shade900),
                  ),
                ]),
                const SizedBox(height: 12),
                _InfoRow('Merchant', _receiptInput!.merchant),
                _InfoRow('Date', _receiptInput!.date),
                _InfoRow('Total', '${_receiptInput!.currency} ${_receiptInput!.total.toStringAsFixed(2)}'),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          OutlinedButton.icon(
            onPressed: _verifying ? null : _enterReceipt,
            icon: const Icon(Icons.edit_document),
            label: Text(_receiptInput == null ? 'Enter Receipt Data' : 'Change Receipt Data'),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),
          const SizedBox(height: 20),

          Text('Solana Transaction Signature', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _txController,
            onChanged: (v) {
              // If user pastes a tx, try proof lookup when it looks valid
              final tx = v.trim();
              if (tx.length >= 60 && !_loadingProof && !_verifying) {
                _fetchProofBundle(tx);
              }
            },
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

          ElevatedButton.icon(
            onPressed: _verifying ? null : _verify,
            icon: _verifying
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.verified_user),
            label: Text(_verifying ? 'Verifying...' : 'Verify Receipt'),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
          ),

          const SizedBox(height: 20),
          const Divider(),
          const SizedBox(height: 12),

          Text('Demo Mode (for testing)',
              style: Theme.of(context).textTheme.titleSmall, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: OutlinedButton(onPressed: () => _demoVerify(true), child: const Text('Demo: Match'))),
            const SizedBox(width: 8),
            Expanded(child: OutlinedButton(onPressed: () => _demoVerify(false), child: const Text('Demo: Mismatch'))),
          ]),
        ]),
      ),
    );
  }
}

class _ProofLookupCard extends StatelessWidget {
  final String tx;
  final bool loading;
  final String? error;
  final Map<String, dynamic>? bundle;
  final VoidCallback? onRefresh;

  const _ProofLookupCard({
    required this.tx,
    required this.loading,
    required this.error,
    required this.bundle,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final found = bundle != null && (bundle!['found'] == true || bundle!['success'] == true);
    final subtitle = found
        ? 'Proof record loaded'
        : 'Scan a VeriCeipt QR or paste a tx signature';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Instant Proof Lookup', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const Spacer(),
          if (onRefresh != null)
            IconButton(
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              tooltip: 'Refresh proof record',
            ),
        ]),
        const SizedBox(height: 8),
        Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 10),

        if (loading) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 10),
          const Text('Fetching proof record…', textAlign: TextAlign.center),
        ] else if (error != null) ...[
          Text(
            'Proof lookup failed: $error',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ] else if (found) ...[
          _kv(context, 'tx', tx.isEmpty ? '—' : tx),
          _kv(context, 'hash', (bundle!['hash'] ?? '—').toString()),
          _kv(context, 'seenCount', (bundle!['seenCount'] ?? '—').toString()),
          _kv(context, 'firstSeenAt', (bundle!['firstSeenAt'] ?? '—').toString()),
        ] else ...[
          _kv(context, 'tx', tx.isEmpty ? '—' : tx),
        ],
      ]),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Expanded(child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(child: Text(v, textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
      ]),
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
        Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
        Expanded(child: Text(value, textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
      ]),
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
      child: Column(children: [
        Text(
          badgeText,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: textColor),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(result.message, style: TextStyle(color: textColor), textAlign: TextAlign.center),
        if (result.chainHash != null && result.localHash != null) ...[
          const SizedBox(height: 12),
          Text(
            'Chain: ${result.chainHash}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: textColor.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'Local: ${result.localHash}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', color: textColor.withOpacity(0.8)),
            textAlign: TextAlign.center,
          ),
        ],
      ]),
    );
  }
}

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
          child: Column(children: [
            TextFormField(
              controller: _merchantController,
              decoration: const InputDecoration(labelText: 'Merchant *', border: OutlineInputBorder()),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _dateController,
              decoration: const InputDecoration(labelText: 'Date *', border: OutlineInputBorder()),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _currencyController,
              decoration: const InputDecoration(labelText: 'Currency *', border: OutlineInputBorder()),
              validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _subtotalController,
              decoration: const InputDecoration(labelText: 'Subtotal *', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _taxController,
              decoration: const InputDecoration(labelText: 'Tax *', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _totalController,
              decoration: const InputDecoration(labelText: 'Total *', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (v) => double.tryParse(v ?? '') == null ? 'Invalid' : null,
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
          ]),
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
