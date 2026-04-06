import 'package:flutter/material.dart';

import '../../../../models/twilio_settings.dart';
import '../../../../services/africas_talking_service.dart';
import '../../../../services/at_settings_service.dart';
import '../../../../services/twilio_service.dart';
import '../../../../services/twilio_settings_service.dart';
import '../../../../ui/app_colors.dart';

class AtSettingsScreen extends StatefulWidget {
  const AtSettingsScreen({super.key});

  @override
  State<AtSettingsScreen> createState() => _AtSettingsScreenState();
}

class _AtSettingsScreenState extends State<AtSettingsScreen> {
  // ── AT controllers ──
  late final TextEditingController _atApiKey;
  late final TextEditingController _atUsername;
  late final TextEditingController _atSenderId;
  late bool _isSandbox;

  // ── Twilio controllers ──
  late final TextEditingController _twilioSid;
  late final TextEditingController _twilioToken;
  late final TextEditingController _twilioFrom;

  bool _saving = false;
  bool _testingAt = false;
  bool _testingTwilio = false;
  String? _atTestResult;
  String? _twilioTestResult;

  @override
  void initState() {
    super.initState();
    final at = AtSettingsService.getOrCreate();
    _atApiKey   = TextEditingController(text: at.apiKey);
    _atUsername = TextEditingController(text: at.username);
    _atSenderId = TextEditingController(text: at.senderId);
    _isSandbox  = at.isSandbox;

    final tw = TwilioSettingsService.getOrCreate();
    _twilioSid   = TextEditingController(text: tw.accountSid);
    _twilioToken = TextEditingController(text: tw.authToken);
    _twilioFrom  = TextEditingController(text: tw.from);
  }

  @override
  void dispose() {
    _atApiKey.dispose();
    _atUsername.dispose();
    _atSenderId.dispose();
    _twilioSid.dispose();
    _twilioToken.dispose();
    _twilioFrom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      // Save AT settings
      final at = AtSettingsService.getOrCreate();
      at.apiKey   = _atApiKey.text.trim();
      at.username = _atUsername.text.trim();
      at.senderId = _atSenderId.text.trim();
      at.isSandbox = _isSandbox;
      await AtSettingsService.save(at);

      // Save Twilio settings
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

  Future<String?> _askPhone() async {
    return showDialog<String>(
      context: context,
      builder: (_) {
        final c = TextEditingController();
        return AlertDialog(
          title: const Text('Test SMS'),
          content: TextField(
            controller: c,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Phone (e.g. +256704811862)',
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
  }

  Future<void> _testAt() async {
    final phone = await _askPhone();
    if (phone == null || phone.isEmpty) return;
    setState(() { _testingAt = true; _atTestResult = null; });
    try {
      final err = await AfricasTalkingService.sendSms(
        toPhone: phone,
        body: 'UNEx Logistics test message via Africa\'s Talking. SMS is working.',
      );
      setState(() => _atTestResult = err == null ? 'Sent ✅' : 'Failed: $err');
    } finally {
      if (mounted) setState(() => _testingAt = false);
    }
  }

  Future<void> _testTwilio() async {
    final phone = await _askPhone();
    if (phone == null || phone.isEmpty) return;
    setState(() { _testingTwilio = true; _twilioTestResult = null; });
    try {
      final err = await TwilioService.sendSms(
        toPhone: phone,
        body: 'UNEx Logistics test message via Twilio. SMS is working.',
      );
      setState(() => _twilioTestResult = err == null ? 'Sent ✅' : 'Failed: $err');
    } finally {
      if (mounted) setState(() => _testingTwilio = false);
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

          // ── Routing info ──────────────────────────────────────────────
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
                Icon(Icons.alt_route_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Smart routing: Uganda numbers (+256) use Africa\'s Talking. '
                    'International numbers (Kenya, South Sudan, Rwanda, DRC) use Twilio. '
                    'Each provider falls back to the other if the primary fails.',
                    style: TextStyle(fontSize: 12, color: cs.onSurface.withValues(alpha: 0.80)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ════════════════════════════════════════════════════════════════
          // AFRICA'S TALKING
          // ════════════════════════════════════════════════════════════════
          _sectionHeader('Africa\'s Talking', 'Uganda numbers', Icons.sms_outlined, cs),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Environment', cs),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sandbox mode'),
                    subtitle: Text(
                      _isSandbox
                          ? 'Using sandbox — SMS are simulated, not delivered.'
                          : 'Using production — SMS will be delivered and billed.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                    value: _isSandbox,
                    onChanged: (v) => setState(() => _isSandbox = v),
                  ),
                  if (!_isSandbox)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.30)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_outlined, size: 16, color: Colors.orange),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Production mode — real SMS will be sent and charged.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Credentials', cs),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _atUsername,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'unex-logistics',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _atApiKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find your API key at account.africastalking.com → Settings → API Key',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Sender ID', cs),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _atSenderId,
                    maxLength: 11,
                    decoration: const InputDecoration(
                      labelText: 'Sender name (max 11 chars)',
                      hintText: 'e.g. ATInfo',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Leave empty to use Africa\'s Talking default shortcode. '
                    'Alphanumeric sender IDs require approval from AT.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // AT test button
          OutlinedButton.icon(
            icon: _testingAt
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sms_outlined),
            label: const Text('Test Africa\'s Talking SMS'),
            onPressed: _testingAt ? null : _testAt,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
            ),
          ),

          if (_atTestResult != null) ...[
            const SizedBox(height: 8),
            _resultBox(_atTestResult!),
          ],

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // ════════════════════════════════════════════════════════════════
          // TWILIO
          // ════════════════════════════════════════════════════════════════
          _sectionHeader('Twilio', 'International numbers', Icons.public_outlined, cs),
          const SizedBox(height: 8),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Credentials', cs),
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
                      hintText: '+16416145221',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find these at console.twilio.com. '
                    'Trial accounts can only send to verified numbers.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Twilio test button
          OutlinedButton.icon(
            icon: _testingTwilio
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.public_outlined),
            label: const Text('Test Twilio SMS'),
            onPressed: _testingTwilio ? null : _testTwilio,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 48),
              foregroundColor: Colors.blue.shade700,
              side: BorderSide(color: Colors.blue.shade700),
            ),
          ),

          if (_twilioTestResult != null) ...[
            const SizedBox(height: 8),
            _resultBox(_twilioTestResult!),
          ],

          const SizedBox(height: 24),

          // ── Save button ──────────────────────────────────────────────
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save_outlined),
            label: const Text('Save Settings'),
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, IconData icon, ColorScheme cs) {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
            Text(subtitle, style: TextStyle(fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
          ],
        ),
      ],
    );
  }

  Widget _sectionLabel(String text, ColorScheme cs) {
    return Row(children: [
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }

  Widget _resultBox(String result) {
    final ok = result.contains('✅');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ok ? Colors.green.withValues(alpha: 0.08) : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ok ? Colors.green.withValues(alpha: 0.30) : Colors.red.withValues(alpha: 0.30),
        ),
      ),
      child: Text(
        result,
        style: TextStyle(fontSize: 13, color: ok ? Colors.green.shade700 : Colors.red.shade700),
      ),
    );
  }
}