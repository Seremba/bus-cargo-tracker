import 'package:flutter/material.dart';

import '../../../../models/twilio_settings.dart';
import '../../../../services/twilio_service.dart';
import '../../../../services/twilio_settings_service.dart';
import '../../../../ui/app_colors.dart';

class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  late final TextEditingController _twilioSid;
  late final TextEditingController _twilioToken;
  late final TextEditingController _twilioFrom;

  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final tw = TwilioSettingsService.getOrCreate();
    _twilioSid   = TextEditingController(text: tw.accountSid);
    _twilioToken = TextEditingController(text: tw.authToken);
    _twilioFrom  = TextEditingController(text: tw.from);
  }

  @override
  void dispose() {
    _twilioSid.dispose();
    _twilioToken.dispose();
    _twilioFrom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await TwilioSettingsService.save(
        TwilioSettings(
          accountSid: _twilioSid.text.trim(),
          authToken:  _twilioToken.text.trim(),
          from:       _twilioFrom.text.trim(),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved ✅')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _testSms() async {
    final phone = await showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Test SMS'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (e.g. +256700000000)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, c.text.trim()),
              child: const Text('Send test'),
            ),
          ],
        );
      },
    );

    if (phone == null || phone.isEmpty) return;
    setState(() { _testing = true; _testResult = null; });
    try {
      final err = await TwilioService.sendSms(
        toPhone: phone,
        body: 'UNEx Logistics test message. SMS is working.',
      );
      setState(() => _testResult = err == null ? 'Sent ✅' : 'Failed: $err');
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('SMS Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [

          // ── Info banner ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.public_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All SMS — OTPs, notifications and alerts — are sent via Twilio. '
                    'Covers Uganda, Kenya, South Sudan, Rwanda, DRC and all international numbers.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.80),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Credentials ───────────────────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Twilio Credentials', cs),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _twilioSid,
                    decoration: const InputDecoration(
                      labelText: 'Account SID',
                      hintText: 'ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _twilioToken,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Auth Token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _twilioFrom,
                    decoration: const InputDecoration(
                      labelText: 'From Number',
                      hintText: '+1XXXXXXXXXX',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find these at console.twilio.com.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Save button ───────────────────────────────────────────────
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Save Settings'),
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 12),

          // ── Test button ───────────────────────────────────────────────
          OutlinedButton.icon(
            icon: _testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sms_outlined),
            label: const Text('Send Test SMS'),
            onPressed: _testing ? null : _testSms,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
            ),
          ),

          if (_testResult != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.contains('✅')
                    ? Colors.green.withValues(alpha: 0.08)
                    : Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: _testResult!.contains('✅')
                      ? Colors.green.withValues(alpha: 0.30)
                      : Colors.red.withValues(alpha: 0.30),
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  fontSize: 13,
                  color: _testResult!.contains('✅')
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}