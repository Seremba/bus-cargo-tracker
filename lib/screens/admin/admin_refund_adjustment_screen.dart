import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/payment_record.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/payment_service.dart';
import '../../services/role_guard.dart';

class AdminRefundAdjustmentScreen extends StatefulWidget {
  final PaymentRecord payment;
  const AdminRefundAdjustmentScreen({super.key, required this.payment});

  @override
  State<AdminRefundAdjustmentScreen> createState() =>
      _AdminRefundAdjustmentScreenState();
}

class _AdminRefundAdjustmentScreenState
    extends State<AdminRefundAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  String _kind = 'refund'; // refund / adjustment
  String _refundMethod = 'cash'; // cash/momo/bank (refund only)
  String _adjustDirection = 'add'; // add/subtract (adjustment only)

  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final pay = widget.payment;
    final propBox = HiveService.propertyBox();
    final prop = propBox.get(int.tryParse(pay.propertyKey));

    final propLabel =
        (prop?.propertyCode.trim().isNotEmpty == true) ? prop!.propertyCode.trim() : pay.propertyKey;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Refund / Adjustment'),
      ),
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
                      Text(
                        'Original: UGX ${pay.amount} • ${pay.method}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('Station: ${pay.station.trim().isEmpty ? '—' : pay.station.trim()}'),
                      Text('TxnRef: ${pay.txnRef.trim().isEmpty ? '—' : pay.txnRef.trim()}'),
                      const SizedBox(height: 6),
                      Text('Property: $propLabel'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _kind,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'refund',
                    child: Text('Refund (negative)'),
                  ),
                  DropdownMenuItem(
                    value: 'adjustment',
                    child: Text('Adjustment (+/-)'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  _kind = v ?? 'refund';
                }),
              ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: InputDecoration(
                  labelText: _kind == 'refund'
                      ? 'Refund amount (UGX)'
                      : 'Adjustment amount (UGX)',
                  border: const OutlineInputBorder(),
                  helperText: _kind == 'refund'
                      ? 'This will subtract from total paid.'
                      : 'This will add or subtract based on direction.',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').trim());
                  if (n == null) return 'Enter a valid amount';
                  if (n <= 0) return 'Amount must be > 0';
                  return null;
                },
              ),

              const SizedBox(height: 12),

              if (_kind == 'adjustment')
                DropdownButtonFormField<String>(
                  initialValue: _adjustDirection,
                  decoration: const InputDecoration(
                    labelText: 'Adjustment direction',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'add', child: Text('Add (+)')),
                    DropdownMenuItem(
                      value: 'subtract',
                      child: Text('Subtract (-)'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => _adjustDirection = v ?? 'add'),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: _refundMethod,
                  decoration: const InputDecoration(
                    labelText: 'Refund method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(
                      value: 'momo',
                      child: Text('Mobile Money'),
                    ),
                    DropdownMenuItem(value: 'bank', child: Text('Bank')),
                  ],
                  onChanged: (v) =>
                      setState(() => _refundMethod = v ?? 'cash'),
                ),

              const SizedBox(height: 12),

              TextFormField(
                controller: _note,
                decoration: const InputDecoration(
                  labelText: 'Reason / note',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.length < 4) {
                    return 'Please write a short reason (min 4 chars)';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final pay = widget.payment;
    final propBox = HiveService.propertyBox();
    final prop = propBox.get(int.tryParse(pay.propertyKey));

    // ✅ Capture these BEFORE any await (avoids async-gap warnings)
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    if (prop == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Property not found for this record ❌')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final amount = int.parse(_amount.text.trim());

      int signedAmount;
      String method;

      if (_kind == 'refund') {
        signedAmount = -amount;
        method = _refundMethod; // cash/momo/bank
      } else {
        signedAmount = (_adjustDirection == 'subtract') ? -amount : amount;
        method = 'adjustment';
      }

      await PaymentService.recordPayment(
        property: prop,
        amount: signedAmount,
        currency: 'UGX',
        method: method,
        txnRef: pay.txnRef,
        station: pay.station,
        kind: _kind,
        note: _note.text.trim(),
      );

      messenger.showSnackBar(
        const SnackBar(content: Text('Saved ✅')),
      );
      nav.pop(true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
