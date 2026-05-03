import 'package:flutter/material.dart';

import '../../services/twilio_service.dart';
import '../../ui/app_colors.dart';

/// SMS Settings screen — read-only status view.
///
/// Twilio credentials (accountSid, authToken, from) now live exclusively
/// as secrets on the Cloudflare Worker. The Flutter app never sees them.
/// SMS is sent via Worker POST /sms. This screen lets admin send a test SMS
/// to verify the Worker is correctly configured.
class SmsSettingsScreen extends StatefulWidget {
  const SmsSettingsScreen({super.key});

  @override
  State<SmsSettingsScreen> createState() => _SmsSettingsScreenState();
}

class _SmsSettingsScreenState extends State<SmsSettingsScreen> {
  bool _testing = false;
  String? _testResult;

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
              labelText: 'Phone number',
              hintText: '+256700000000',
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
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final err = await TwilioService.sendSms(
        toPhone: phone,
        body: 'UNEx Logistics test message. SMS is working correctly.',
      );
      setState(
        () => _testResult = err == null ? 'Sent successfully ✅' : 'Failed: $err',
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('SMS Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'Credentials secured on server',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Twilio credentials are stored as secrets on the Cloudflare Worker '
                  'and never sent to this device. All SMS are routed through the Worker.\n\n'
                  'To update credentials, use the Cloudflare Workers dashboard and '
                  'update the TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, and TWILIO_FROM secrets.',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Coverage',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  _coverageRow('Uganda (+256)'),
                  _coverageRow('Kenya (+254)'),
                  _coverageRow('South Sudan (+211)'),
                  _coverageRow('Rwanda (+250)'),
                  _coverageRow('DR Congo (+243)'),
                  _coverageRow('Tanzania (+255)'),
                  _coverageRow('International (all E.164)'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
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

  Widget _coverageRow(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, size: 15, color: Colors.green),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }
}