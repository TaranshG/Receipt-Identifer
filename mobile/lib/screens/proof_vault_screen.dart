import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class ProofVaultScreen extends StatefulWidget {
  const ProofVaultScreen({super.key});

  @override
  State<ProofVaultScreen> createState() => _ProofVaultScreenState();
}

class _ProofVaultScreenState extends State<ProofVaultScreen> {
  List<Map<String, dynamic>> _proofs = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProofs();
  }

  Future<void> _loadProofs() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await ApiService.getProofs();
      if (!mounted) return;

      final proofs = (response['proofs'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      setState(() {
        _proofs = proofs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Proof Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadProofs,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                        const SizedBox(height: 16),
                        Text('Error loading proofs', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadProofs, child: const Text('Retry')),
                      ],
                    ),
                  ),
                )
              : _proofs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_open, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('No proofs yet', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          const Text('Create a proof to see it here'),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _proofs.length,
                      itemBuilder: (_, i) => _proofCard(_proofs[i]),
                    ),
    );
  }

  Widget _proofCard(Map<String, dynamic> proof) {
    final tx = proof['txSignature']?.toString() ?? '';
    final canonical = proof['canonicalText']?.toString() ?? '';
    final lastSeen = proof['lastSeenAt']?.toString();
    final seenCount = proof['seenCount'] as int? ?? 1;
    final duplicate = seenCount > 1;

    final merchant = _extractField(canonical, 'merchant');
    final total = _extractField(canonical, 'total');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Proof Details'),
              content: SelectableText(
                'Tx: $tx\n\nCanonical:\n$canonical',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ],
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(duplicate ? Icons.warning : Icons.verified, color: duplicate ? Colors.orange : Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      merchant.isEmpty ? 'Receipt' : merchant,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (duplicate)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Seen ${seenCount}x',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange.shade900),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Total: $total',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              if (lastSeen != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formatDate(lastSeen),
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _extractField(String canonical, String field) {
    final lines = canonical.split('\n');
    for (final line in lines) {
      if (line.startsWith('$field=')) {
        return line.substring(field.length + 1).trim();
      }
    }
    return '';
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('MMM d, y h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }
}