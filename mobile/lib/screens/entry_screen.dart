import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import '../models/receipt_input.dart';
import '../models/receipt_analysis.dart';
import '../services/api_service.dart';
import 'result_screen.dart';

class EntryScreen extends StatefulWidget {
  final ReceiptInput? initialInput;
  const EntryScreen({super.key, this.initialInput});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _merchantController;
  late TextEditingController _dateController;
  late TextEditingController _subtotalController;
  late TextEditingController _taxController;
  late TextEditingController _totalController;
  late TextEditingController _customCurrencyController;

  bool _analyzing = false;
  bool _extracting = false;

  final List<String> _commonCurrencies = ['CAD', 'USD', 'EUR', 'GBP', 'INR', 'AUD', 'Custom'];
  String _selectedCurrency = 'CAD';

  @override
  void initState() {
    super.initState();
    final input = widget.initialInput ?? ReceiptInput.empty();
    _merchantController = TextEditingController(text: input.merchant);
    _dateController = TextEditingController(text: input.date);
    _subtotalController = TextEditingController(text: input.subtotal > 0 ? input.subtotal.toStringAsFixed(2) : '');
    _taxController = TextEditingController(text: input.tax > 0 ? input.tax.toStringAsFixed(2) : '');
    _totalController = TextEditingController(text: input.total > 0 ? input.total.toStringAsFixed(2) : '');
    _customCurrencyController = TextEditingController();

    if (input.currency.isNotEmpty && _commonCurrencies.contains(input.currency)) {
      _selectedCurrency = input.currency;
    } else if (input.currency.isNotEmpty) {
      _selectedCurrency = 'Custom';
      _customCurrencyController.text = input.currency;
    }

    if (_dateController.text.isEmpty) {
      _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    }
  }

  @override
  void dispose() {
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

  Future<void> _pickImage() async {
    try {
      setState(() => _extracting = true);

      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) {
        setState(() => _extracting = false);
        return;
      }

      final bytes = await image.readAsBytes();
      final base64Image = base64Encode(bytes);

      final resultJson = await ApiService.analyzeReceipt({'imageBase64': base64Image});
      final analysis = ReceiptAnalysis.fromJson(resultJson);

      if (!mounted) return;
      setState(() => _extracting = false);

      _merchantController.text = analysis.merchant;
      _dateController.text = analysis.date.isNotEmpty ? analysis.date : DateFormat('yyyy-MM-dd').format(DateTime.now());

      if (_commonCurrencies.contains(analysis.currency)) {
        _selectedCurrency = analysis.currency;
      } else {
        _selectedCurrency = 'Custom';
        _customCurrencyController.text = analysis.currency;
      }

      _subtotalController.text = analysis.subtotal.toStringAsFixed(2);
      _taxController.text = analysis.tax.toStringAsFixed(2);
      _totalController.text = analysis.total.toStringAsFixed(2);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Fields extracted! Review and analyze.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _extracting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Extraction failed: $e')),
      );
    }
  }

  Future<void> _analyze() async {
    if (!_formKey.currentState!.validate()) return;

    final currency = _effectiveCurrency;
    if (currency.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Currency must be 3 letters (e.g., CAD, USD)')),
      );
      return;
    }

    setState(() => _analyzing = true);

    try {
      final input = ReceiptInput(
        merchant: _merchantController.text.trim(),
        date: _dateController.text.trim(),
        currency: currency,
        subtotal: double.parse(_subtotalController.text),
        tax: double.parse(_taxController.text),
        total: double.parse(_totalController.text),
      );

      final resultJson = await ApiService.analyzeReceipt(input.toJson());
      final analysis = ReceiptAnalysis.fromJson(resultJson);

      if (!mounted) return;
      setState(() => _analyzing = false);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ResultScreen(analysis: analysis, receiptInput: input),
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
      appBar: AppBar(title: const Text('Create Proof')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.camera_alt, color: Colors.blue.shade700),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Upload image or enter manually',
                          style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              OutlinedButton.icon(
                onPressed: _extracting ? null : _pickImage,
                icon: _extracting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.upload_file),
                label: Text(_extracting ? 'Extracting...' : 'Upload Receipt Image'),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              Text('Receipt Details', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),

              _field(_merchantController, 'Merchant', Icons.store),
              const SizedBox(height: 16),
              _dateField(),
              const SizedBox(height: 16),
              _currencyDropdown(),
              const SizedBox(height: 24),
              Text('Amounts', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 12),
              _numberField(_subtotalController, 'Subtotal', Icons.receipt),
              const SizedBox(height: 16),
              _numberField(_taxController, 'Tax', Icons.percent),
              const SizedBox(height: 16),
              _numberField(_totalController, 'Total', Icons.payment),
              const SizedBox(height: 32),

              ElevatedButton.icon(
                onPressed: _analyzing ? null : _analyze,
                icon: _analyzing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.analytics),
                label: Text(_analyzing ? 'Analyzing...' : 'Analyze Receipt'),
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
        suffixIcon: IconButton(
          icon: const Icon(Icons.edit_calendar),
          onPressed: _pickDate,
        ),
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
          decoration: const InputDecoration(
            labelText: 'Currency',
            prefixIcon: Icon(Icons.attach_money),
          ),
          items: _commonCurrencies.map((c) {
            return DropdownMenuItem(value: c, child: Text(c));
          }).toList(),
          onChanged: (v) {
            setState(() => _selectedCurrency = v ?? 'CAD');
          },
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

  Widget _numberField(TextEditingController controller, String label, IconData icon) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return 'Required';
        if (double.tryParse(v) == null) return 'Invalid number';
        return null;
      },
    );
  }
}