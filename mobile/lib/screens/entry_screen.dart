// lib/screens/entry_screen.dart

import 'package:flutter/material.dart';
import '../models/receipt_input.dart';
import '../models/receipt_analysis.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

/// Manual receipt entry screen.
/// Sends data to backend -> Gemini -> returns fraud analysis.
class EntryScreen extends StatefulWidget {
  final ReceiptInput? initialInput;

  const EntryScreen({super.key, this.initialInput});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _merchantController;
  late final TextEditingController _dateController;
  late final TextEditingController _currencyController;
  late final TextEditingController _subtotalController;
  late final TextEditingController _taxController;
  late final TextEditingController _totalController;

  bool _analyzing = false;

  @override
  void initState() {
    super.initState();
    final input = widget.initialInput ?? ReceiptInput.empty();

    _merchantController = TextEditingController(text: input.merchant);
    _dateController = TextEditingController(text: input.date);
    _currencyController = TextEditingController(text: input.currency);
    _subtotalController = TextEditingController(
      text: input.subtotal > 0 ? input.subtotal.toStringAsFixed(2) : '',
    );
    _taxController = TextEditingController(
      text: input.tax > 0 ? input.tax.toStringAsFixed(2) : '',
    );
    _totalController = TextEditingController(
      text: input.total > 0 ? input.total.toStringAsFixed(2) : '',
    );
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

  Future<void> _analyze() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _analyzing = true);

    try {
      final input = ReceiptInput(
        merchant: _merchantController.text.trim(),
        date: _dateController.text.trim(),
        currency: _currencyController.text.trim().toUpperCase(),
        subtotal: double.parse(_subtotalController.text),
        tax: double.parse(_taxController.text),
        total: double.parse(_totalController.text),
      );

      final resultJson = await ApiService.analyzeReceipt({
        'merchant': input.merchant,
        'date': input.date,
        'currency': input.currency,
        'subtotal': input.subtotal,
        'tax': input.tax,
        'total': input.total,
      });

      final analysis = ReceiptAnalysis.fromJson(resultJson);

      if (!mounted) return;
      setState(() => _analyzing = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(
            analysis: analysis,
            receiptInput: input,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _analyzing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Analysis failed: $e')),
      );
    }
  }

  void _autofill() {
    final now = DateTime.now();
    if (_dateController.text.isEmpty) {
      _dateController.text =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    }
    if (_currencyController.text.isEmpty) {
      _currencyController.text = 'CAD';
    }
  }

  String? _validateDate(String? v) {
    if (v == null || v.trim().isEmpty) return 'Required';

    // Accept "YYYY-MM-DD" OR "YYYY-MM-DD HH:MM"
    final s = v.trim();
    final re1 = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    final re2 = RegExp(r'^\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}$');

    if (!re1.hasMatch(s) && !re2.hasMatch(s)) {
      return 'Use YYYY-MM-DD (or YYYY-MM-DD HH:MM)';
    }

    // Basic range checks
    final datePart = s.split(' ').first;
    final parts = datePart.split('-').map(int.parse).toList();
    final m = parts[1], d = parts[2];

    if (m < 1 || m > 12) return 'Month must be 01–12';
    if (d < 1 || d > 31) return 'Day must be 01–31';

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Enter Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome),
            onPressed: _autofill,
            tooltip: 'Auto-fill date & currency',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enter receipt fields manually. AI will check for inconsistencies.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              _field(
                controller: _merchantController,
                label: 'Merchant / Store Name',
                icon: Icons.store,
              ),
              const SizedBox(height: 16),

              _field(
                controller: _dateController,
                label: 'Date (YYYY-MM-DD)',
                icon: Icons.calendar_today,
                hint: '2026-02-07',
                validator: _validateDate,
              ),
              const SizedBox(height: 16),

              _field(
                controller: _currencyController,
                label: 'Currency',
                icon: Icons.attach_money,
                hint: 'CAD',
                maxLength: 3,
              ),
              const SizedBox(height: 16),

              _numberField(
                controller: _subtotalController,
                label: 'Subtotal',
                icon: Icons.receipt,
              ),
              const SizedBox(height: 16),

              _numberField(
                controller: _taxController,
                label: 'Tax',
                icon: Icons.percent,
              ),
              const SizedBox(height: 16),

              _numberField(
                controller: _totalController,
                label: 'Total',
                icon: Icons.payment,
              ),
              const SizedBox(height: 24),

              ElevatedButton.icon(
                onPressed: _analyzing ? null : _analyze,
                icon: _analyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.analytics),
                label: Text(_analyzing ? 'Analyzing…' : 'Analyze Receipt'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: _analyzing ? null : () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      maxLength: maxLength,
      decoration: InputDecoration(
        labelText: '$label *',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
        hintText: hint,
      ),
      validator: validator ??
          (v) => v == null || v.trim().isEmpty ? 'Required' : null,
    );
  }

  Widget _numberField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: '$label *',
        border: const OutlineInputBorder(),
        prefixIcon: Icon(icon),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v) == null) return 'Invalid number';
        return null;
      },
    );
  }
}
