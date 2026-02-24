import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tracking_lookup_service.dart';
import '../desk/desk_property_qr_scanner_screen.dart';

class TrackingLookupScreen extends StatefulWidget {
  const TrackingLookupScreen({super.key});

  @override
  State<TrackingLookupScreen> createState() => _TrackingLookupScreenState();
}

class _TrackingLookupScreenState extends State<TrackingLookupScreen> {
  final _code = TextEditingController();
  TrackingLookupResult? _result;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied ✅')),
    );
  }

  void _lookup(String raw) {
    final code = raw.trim().toUpperCase();
    if (code.isEmpty) return;

    final found = TrackingLookupService.findByCode(code);

    setState(() {
      _result = found;
      _error = (found == null) ? 'No match found for: $code' : null;
    });
  }

  Future<void> _scanQr() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      final raw = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (_) => const DeskPropertyQrScannerScreen()),
      );

      if (!mounted) return;

      final code = (raw ?? '').trim();
      if (code.isEmpty) return;

      _code.text = code.toUpperCase();
      _lookup(code);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Scan failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Tracking Lookup'),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: _busy ? null : _scanQr,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Enter tracking code',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      hintText: 'e.g. BC-482190-AX',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: _lookup,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _lookup(_code.text),
                          icon: const Icon(Icons.search),
                          label: Text(_busy ? 'Working...' : 'Lookup'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _scanQr,
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          if (r != null)
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
                            'Status: ${r.statusLabel}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _fmt16(r.lastUpdatedAt),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 18),
                    _kv('Tracking', r.property.trackingCode.trim().isEmpty
                        ? '—'
                        : r.property.trackingCode.trim(),
                        copy: true),
                    _kv('Receiver', r.property.receiverName.trim().isEmpty
                        ? '—'
                        : r.property.receiverName.trim()),
                    _kv('Phone', r.property.receiverPhone.trim().isEmpty
                        ? '—'
                        : r.property.receiverPhone.trim(),
                        copy: true),
                    _kv('Destination', r.property.destination.trim().isEmpty
                        ? '—'
                        : r.property.destination.trim()),
                    _kv('Route', r.property.routeName.trim().isEmpty
                        ? '—'
                        : r.property.routeName.trim()),
                    _kv('Property', r.property.propertyCode.trim().isEmpty
                        ? r.property.key.toString()
                        : r.property.propertyCode.trim(),
                        copy: true),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, {bool copy = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 95,
            child: Text(
              '$k:',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Colors.black54,
              ),
            ),
          ),
          Expanded(child: Text(v)),
          if (copy && v.trim().isNotEmpty && v.trim() != '—')
            IconButton(
              tooltip: 'Copy $k',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () => _copy(k, v),
            ),
        ],
      ),
    );
  }
}