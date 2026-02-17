import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/user_role.dart';
import '../../services/pickup_qr_service.dart';
import '../../services/role_guard.dart';

class StaffConfirmPickupScreen extends StatefulWidget {
  final int propertyKey;
  final String nonce;
  const StaffConfirmPickupScreen({
    super.key,
    required this.propertyKey,
    required this.nonce,
  });

  @override
  State<StaffConfirmPickupScreen> createState() => _StaffConfirmPickupScreenState();
}

class _StaffConfirmPickupScreenState extends State<StaffConfirmPickupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _otp = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    _otp.dispose();
    super.dispose();
  }

  bool get _canUse => RoleGuard.hasAny({UserRole.staff, UserRole.admin});

  @override
  Widget build(BuildContext context) {
    if (!_canUse) return const Scaffold(body: Center(child: Text('Not authorized')));

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Confirm Pickup')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'PropertyKey: ${widget.propertyKey}\n\n'
                    'Now enter the OTP from the sender/receiver.',
                  ),
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _otp,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                decoration: const InputDecoration(
                  labelText: 'OTP',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isEmpty) return 'OTP required';
                  if (t.length < 4) return 'OTP too short';
                  return null;
                },
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                child: Text(_saving ? 'Confirming...' : 'Confirm Pickup'),
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

    setState(() => _saving = true);
    try {
      final err = await PickupQrService.confirmPickup(
        propertyKey: widget.propertyKey,
        scannedNonce: widget.nonce,
        enteredOtp: _otp.text.trim(),
      );

      if (!mounted) return;

      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pickup confirmed ✅')),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
