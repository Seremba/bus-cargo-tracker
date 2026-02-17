import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/property.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/payment_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';

class DeskRecordPaymentScreen extends StatefulWidget {
  final Property property;
  const DeskRecordPaymentScreen({super.key, required this.property});

  @override
  State<DeskRecordPaymentScreen> createState() => _DeskRecordPaymentScreenState();
}

class _DeskRecordPaymentScreenState extends State<DeskRecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();

  final _amount = TextEditingController();
  final _txnRef = TextEditingController();
  String _method = 'cash';

  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _txnRef.dispose();
    super.dispose();
  }

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied ✅')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUse) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final station = (Session.currentStationName ?? '').trim();
    if (station.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No station set for this user ❌')),
      );
    }

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(widget.property.key) ?? widget.property;

    final displayCode = fresh.propertyCode.trim().isEmpty
        ? fresh.key.toString()
        : fresh.propertyCode.trim();

    final displayCurrency =
        fresh.currency.trim().isEmpty ? 'UGX' : fresh.currency.trim();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Record Payment')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Property: $displayCode',
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (fresh.propertyCode.trim().isNotEmpty)
                            IconButton(
                              tooltip: 'Copy code',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () =>
                                  _copy(context, 'Property code', displayCode),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Receiver: ${fresh.receiverName}'),
                      Text('Phone: ${fresh.receiverPhone}'),
                      Text(
                        'Route: ${fresh.routeName.trim().isEmpty ? '—' : fresh.routeName.trim()}',
                      ),
                      Text('Destination: ${fresh.destination}'),
                      const SizedBox(height: 6),
                      Text('Station: $station'),
                      const SizedBox(height: 6),
                      Text(
                        'Total Paid: $displayCurrency ${fresh.amountPaidTotal}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount (UGX)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  final n = int.tryParse(t);
                  if (n == null) return 'Enter a valid amount';
                  if (n <= 0) return 'Amount must be > 0';
                  return null;
                },
              ),

              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'momo', child: Text('Mobile Money')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                ],
                onChanged: (v) => setState(() => _method = (v ?? 'cash')),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _txnRef,
                decoration: const InputDecoration(
                  labelText: 'Txn ref (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_saving ? 'Saving...' : 'Save Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canUse) return;
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final station = (Session.currentStationName ?? '').trim();
    if (station.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No station set for this user ❌')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context); // ✅ capture BEFORE async gap
    setState(() => _saving = true);

    try {
      final amount = int.parse(_amount.text.trim());

      try {
        await PaymentService.recordPayment(
          property: widget.property,
          amount: amount,
          currency: 'UGX',
          method: _method,
          txnRef: _txnRef.text.trim(),
          station: station,
          kind: 'payment',
        );

        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Payment recorded ✅')),
        );
        Navigator.pop(context, true);
      } catch (e) {
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
