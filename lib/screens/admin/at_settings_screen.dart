import 'package:flutter/material.dart';

import '../../../../services/at_settings_service.dart';
import '../../../../services/africas_talking_service.dart';
import '../../../../ui/app_colors.dart';

class AtSettingsScreen extends StatefulWidget {
  const AtSettingsScreen({super.key});

  @override
  State<AtSettingsScreen> createState() => _AtSettingsScreenState();
}

class _AtSettingsScreenState extends State<AtSettingsScreen> {
  late final TextEditingController _apiKey;
  late final TextEditingController _username;
  late final TextEditingController _senderId;
  late bool _isSandbox;
  bool _saving = false;
  bool _testing = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    final s = AtSettingsService.getOrCreate();
    _apiKey    = TextEditingController(text: s.apiKey);
    _username  = TextEditingController(text: s.username);
    _senderId  = TextEditingController(text: s.senderId);
    _isSandbox = s.isSandbox;
  }

  @override
  void dispose() {
    _apiKey.dispose();
    _username.dispose();
    _senderId.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final s = AtSettingsService.getOrCreate();
      s.apiKey   = _apiKey.text.trim();
      s.username = _username.text.trim();
      s.senderId = _senderId.text.trim();
      s.isSandbox = _isSandbox;
      await AtSettingsService.save(s);
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
              labelText: 'Phone number (e.g. 0700123456)',
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
      final err = await AfricasTalkingService.sendSms(
        toPhone: phone,
        body: 'UNEx Logistics test message. If you receive this, SMS is working ✅',
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
        title: const Text('SMS Settings (Africa\'s Talking)'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // ── Mode toggle ──
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
                        border: Border.all(
                            color: Colors.orange.withValues(alpha: 0.30)),
                      ),
                      child: const Row(children: [
                        Icon(Icons.warning_amber_outlined,
                            size: 16, color: Colors.orange),
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
          const SizedBox(height: 12),

          // ── Credentials ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Credentials', cs),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _username,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      hintText: 'sandbox (for testing) or your AT username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _apiKey,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: 'From Africa\'s Talking → Settings → API Key',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Find your API key at account.africastalking.com → '
                    'Settings → API Key',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Sender ID ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionLabel('Sender ID', cs),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _senderId,
                    maxLength: 11,
                    decoration: const InputDecoration(
                      labelText: 'Sender name (max 11 chars)',
                      hintText: 'e.g. UNExLogstx',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This is what receivers see as the SMS sender. '
                    'Leave empty to use Africa\'s Talking default shortcode. '
                    'Alphanumeric sender IDs require approval from AT for production.',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Save button ──
          ElevatedButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
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

          // ── Test SMS button ──
          OutlinedButton.icon(
            icon: _testing
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
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
            const SizedBox(height: 10),
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
    return Row(children: [
      Container(
        width: 3, height: 16,
        decoration: BoxDecoration(
            color: cs.primary, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 8),
      Text(text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]);
  }
}