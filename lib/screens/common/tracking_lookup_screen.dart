import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/tracking_lookup_service.dart';

import '../desk/desk_property_qr_scanner_screen.dart';

class TrackingLookupScreen extends StatefulWidget {
  final String? initialCode;
  const TrackingLookupScreen({super.key, this.initialCode});

  @override
  State<TrackingLookupScreen> createState() => _TrackingLookupScreenState();
}

class _TrackingLookupScreenState extends State<TrackingLookupScreen> {
  final _code = TextEditingController();
  TrackingLookupResult? _result;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = (widget.initialCode ?? '').trim();
    if (initial.isNotEmpty) {
      _code.text = initial;
      // Auto-lookup when opened via deep link
      WidgetsBinding.instance.addPostFrameCallback((_) => _lookup(initial));
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  String _fmt16(DateTime d) => d.toLocal().toString().substring(0, 16);

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied ✅')));
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

  // Status color (matches app-wide status pill colors)

  Color _statusColor(String label) {
    final l = label.toLowerCase();
    if (l.contains('transit')) return Colors.blue;
    if (l.contains('deliver')) return Colors.green;
    if (l.contains('picked')) return Colors.teal;
    if (l.contains('loaded')) return AppColors.primary;
    if (l.contains('pending')) return Colors.amber.shade700;
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = _result;

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Tracking Lookup'),
        actions: [
          IconButton(
            tooltip: 'Scan QR',
            icon: const Icon(Icons.qr_code_scanner_outlined),
            onPressed: _busy ? null : _scanQr,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          // ── Search card ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Section title: 3px primary left border + icon + bold text
                  Row(
                    children: [
                      Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.search_outlined, size: 17),
                      const SizedBox(width: 6),
                      const Text(
                        'Enter tracking code',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Input field — filled style matching app-wide pattern
                  TextField(
                    controller: _code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'e.g. BC-482190-AX',
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withValues(
                        alpha: 0.30,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: cs.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(
                          color: AppColors.primary,
                          width: 2,
                        ),
                      ),
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                    onSubmitted: _lookup,
                  ),
                  const SizedBox(height: 12),

                  // Lookup + Scan buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _busy ? null : () => _lookup(_code.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.search_outlined, size: 18),
                          label: Text(
                            _busy ? 'Working...' : 'Lookup',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _scanQr,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          side: BorderSide(color: AppColors.primary),
                          foregroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(
                          Icons.qr_code_scanner_outlined,
                          size: 18,
                        ),
                        label: const Text(
                          'Scan',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),

                  // Error state — icon + message row
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 16,
                          color: Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Result card ──
          if (r != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status header row
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.local_shipping_outlined, size: 17),
                        const SizedBox(width: 6),
                        const Text(
                          'Tracking Result',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Status pill + last updated
                    Row(
                      children: [
                        _statusPill(r.statusLabel),
                        const Spacer(),
                        Icon(
                          Icons.access_time_outlined,
                          size: 13,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _fmt16(r.lastUpdatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.45),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    Divider(
                      height: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 14),

                    // KV rows
                    _kv(
                      icon: Icons.qr_code_outlined,
                      label: 'Tracking',
                      value: r.property.trackingCode.trim().isEmpty
                          ? '—'
                          : r.property.trackingCode.trim(),
                      copy: true,
                    ),
                    _kv(
                      icon: Icons.person_outline,
                      label: 'Receiver',
                      value: r.property.receiverName.trim().isEmpty
                          ? '—'
                          : r.property.receiverName.trim(),
                    ),
                    _kv(
                      icon: Icons.phone_outlined,
                      label: 'Phone',
                      value: r.property.receiverPhone.trim().isEmpty
                          ? '—'
                          : r.property.receiverPhone.trim(),
                      copy: true,
                    ),
                    _kv(
                      icon: Icons.place_outlined,
                      label: 'Destination',
                      value: r.property.destination.trim().isEmpty
                          ? '—'
                          : r.property.destination.trim(),
                    ),
                    _kv(
                      icon: Icons.route_outlined,
                      label: 'Route',
                      value: r.property.routeName.trim().isEmpty
                          ? '—'
                          : r.property.routeName.trim(),
                    ),
                    _kv(
                      icon: Icons.inventory_2_outlined,
                      label: 'Property',
                      value: r.property.propertyCode.trim().isEmpty
                          ? r.property.key.toString()
                          : r.property.propertyCode.trim(),
                      copy: true,
                      isLast: true,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Helpers

  /// Status pill: inline Container, not Flutter Chip
  Widget _statusPill(String label) {
    final color = _statusColor(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  /// Key-value row with leading icon and optional copy button
  Widget _kv({
    required IconData icon,
    required String label,
    required String value,
    bool copy = false,
    bool isLast = false,
  }) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.50);

    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: muted),
          const SizedBox(width: 8),
          SizedBox(
            width: 84,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: muted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (copy && value.trim().isNotEmpty && value.trim() != '—')
            GestureDetector(
              onTap: () => _copy(label, value),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.copy_outlined, size: 16, color: muted),
              ),
            ),
        ],
      ),
    );
  }
}