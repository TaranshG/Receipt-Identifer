import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/receipt_input.dart';
import '../services/api_service.dart';
import 'verify_result_screen.dart';

class VerifyScreen extends StatefulWidget {
  final String? initialTxSignature;
  const VerifyScreen({super.key, this.initialTxSignature});

  @override
  State<VerifyScreen> createState() => _VerifyScreenState();
}

class _VerifyScreenState extends State<VerifyScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _txController;
  late TextEditingController _merchantController;
  late TextEditingController _dateController;
  late TextEditingController _subtotalController;
  late TextEditingController _taxController;
  late TextEditingController _totalController;
  late TextEditingController _customCurrencyController;

  bool _verifying = false;
  bool _fetchingProof = false;
  String? _proofStatus; // 'found' | 'not_found' | null
  String? _certifiedSnapshot;

  final List<String> _commonCurrencies = ['CAD', 'USD', 'EUR', 'GBP', 'INR', 'AUD', 'Custom'];
  String _selectedCurrency = 'CAD';

  @override
  void initState() {
    super.initState();
    _txController = TextEditingController(text: widget.initialTxSignature ?? '');
    _merchantController = TextEditingController();
    _dateController = TextEditingController();
    _subtotalController = TextEditingController();
    _taxController = TextEditingController();
    _totalController = TextEditingController();
    _customCurrencyController = TextEditingController();

    if (widget.initialTxSignature != null && widget.initialTxSignature!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchProof());
    }
  }

  @override
  void dispose() {
    _txController.dispose();
    _merchantController.dispose();
    _dateController.dispose();
    _subtotalController.dispose();
    _taxController.dispose();
    _totalController.dispose();
    _customCurrencyController.dispose();
    super.dispose();
  }

  String get _effectiveCurrency {
    if (_selectedCurrency == 'Custom') {
      return _customCurrencyController.text.trim().toUpperCase();
    }
    return _selectedCurrency;
  }

  Future<void> _fetchProof() async {
    final tx = _txController.text.trim();
    if (tx.isEmpty) return;

    setState(() {
      _fetchingProof = true;
      _proofStatus = null;
      _certifiedSnapshot = null;
    });

    try {
      final proofBundle = await ApiService.getProof(tx);
      if (!mounted) return;

      final found = proofBundle['found'] == true;
      final canonicalText = proofBundle['canonicalText']?.toString();

      if (found && canonicalText != null && canonicalText.isNotEmpty) {
        setState(() {
          _proofStatus = 'found';
          _certifiedSnapshot = canonicalText;
        });
      } else {
        setState(() => _proofStatus = 'not_found');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _proofStatus = 'not_found');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Proof lookup failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _fetchingProof = false);
    }
  }

  void _autofillFromCertified() {
    if (_certifiedSnapshot == null) return;
    _parseCanonicalIntoForm(_certifiedSnapshot!);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Certified data loaded')),
    );
  }

  void _parseCanonicalIntoForm(String canonical) {
    final lines = canonical.split('\n');
    final map = <String, String>{};
    for (final line in lines) {
      final idx = line.indexOf('=');
      if (idx > 0) {
        final k = line.substring(0, idx).trim();
        final v = line.substring(idx + 1).trim();
        map[k] = v;
      }
    }

    if (map['merchant'] != null) _merchantController.text = map['merchant']!;
    if (map['date'] != null) _dateController.text = map['date']!;

    if (map['currency'] != null) {
      final curr = map['currency']!.toUpperCase();
      if (_commonCurrencies.contains(curr)) {
        setState(() => _selectedCurrency = curr);
      } else {
        setState(() {
          _selectedCurrency = 'Custom';
          _customCurrencyController.text = curr;
        });
      }
    }

    if (map['subtotal'] != null) _subtotalController.text = map['subtotal']!;
    if (map['tax'] != null) _taxController.text = map['tax']!;
    if (map['total'] != null) _totalController.text = map['total']!;
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;

    final currency = _effectiveCurrency;
    if (currency.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Currency must be 3 letters')),
      );
      return;
    }

    setState(() => _verifying = true);

    try {
      final input = ReceiptInput(
        merchant: _merchantController.text.trim(),
        date: _dateController.text.trim(),
        currency: currency,
        subtotal: double.parse(_subtotalController.text),
        tax: double.parse(_taxController.text),
        total: double.parse(_totalController.text),
      );

      final canonicalText = _buildCanonicalText(input);
      final txSignature = _txController.text.trim();

      final result = await ApiService.verifyReceipt(canonicalText, txSignature);

      if (!mounted) return;
      setState(() => _verifying = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyResultScreen(
            verifyResult: result,
            receiptInput: input,
            certifiedSnapshot: _certifiedSnapshot,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Verification failed: $e')),
      );
    }
  }

  String _buildCanonicalText(ReceiptInput input) {
    String money(double v) => v.toStringAsFixed(2);
    final merchant = input.merchant.trim().toLowerCase();
    final date = input.date.trim();
    final currency = input.currency.trim().toUpperCase();

    return [
      'merchant=$merchant',
      'date=$date',
      'currency=$currency',
      'subtotal=${money(input.subtotal)}',
      'tax=${money(input.tax)}',
      'total=${money(input.total)}',
    ].join('\n');
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (text.startsWith('vericeipt://proof?tx=')) {
      final uri = Uri.tryParse(text);
      if (uri != null && uri.queryParameters['tx'] != null) {
        _txController.text = uri.queryParameters['tx']!;
        _fetchProof();
      }
    } else {
      _txController.text = text;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify Receipt')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_user, color: Colors.green.shade700),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Step 1: Paste proof link or tx signature',
                              style: TextStyle(color: Colors.green.shade900, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Scan QR, paste deep link (vericeipt://...), or enter tx',
                        style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _txController,
                decoration: InputDecoration(
                  labelText: 'Transaction Signature',
                  prefixIcon: const Icon(Icons.link),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(icon: const Icon(Icons.paste), onPressed: _pasteFromClipboard),
                      IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: _fetchingProof ? null : _fetchProof,
                      ),
                    ],
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
              ),

              if (_fetchingProof) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],

              if (_proofStatus == 'found' && _certifiedSnapshot != null) ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.blue.shade700, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Step 2: Local proof snapshot found ✓', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This tx was certified on this server. You can auto-load the certified data or enter different values to test tampering detection.',
                          style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _autofillFromCertified,
                          icon: const Icon(Icons.download),
                          label: const Text('Use Certified Data'),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              if (_proofStatus == 'not_found') ...[
                const SizedBox(height: 16),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'No local proof found. Chain verification will still attempt.',
                            style: TextStyle(fontSize: 12, color: Colors.orange.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Text('Step 3: Enter current receipt data', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),

              _field(_merchantController, 'Merchant', Icons.store),
              const SizedBox(height: 16),
              _dateField(),
              const SizedBox(height: 16),
              _currencyDropdown(),
              const SizedBox(height: 16),
              _numberField(_subtotalController, 'Subtotal'),
              const SizedBox(height: 16),
              _numberField(_taxController, 'Tax'),
              const SizedBox(height: 16),
              _numberField(_totalController, 'Total'),

              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _verifying ? null : _verify,
                icon: _verifying
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.verified_user),
                label: Text(_verifying ? 'Verifying...' : 'Verify on Blockchain'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _dateField() {
    return TextFormField(
      controller: _dateController,
      readOnly: true,
      decoration: InputDecoration(
        labelText: 'Date',
        prefixIcon: const Icon(Icons.calendar_today),
        suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar), onPressed: _pickDate),
      ),
      onTap: _pickDate,
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _currencyDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _selectedCurrency,
          decoration: const InputDecoration(labelText: 'Currency', prefixIcon: Icon(Icons.attach_money)),
          items: _commonCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
          onChanged: (v) => setState(() => _selectedCurrency = v ?? 'CAD'),
        ),
        if (_selectedCurrency == 'Custom') ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _customCurrencyController,
            decoration: const InputDecoration(
              labelText: 'Custom Currency Code',
              hintText: 'e.g., JPY, CHF',
              prefixIcon: Icon(Icons.edit),
            ),
            maxLength: 3,
            textCapitalization: TextCapitalization.characters,
            onChanged: (v) {
              _customCurrencyController.text = v.toUpperCase();
              _customCurrencyController.selection = TextSelection.fromPosition(
                TextPosition(offset: _customCurrencyController.text.length),
              );
            },
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (v.length != 3) return 'Must be 3 letters';
              return null;
            },
          ),
        ],
      ],
    );
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.receipt)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v) == null) return 'Invalid number';
        return null;
      },
    );
  }
}