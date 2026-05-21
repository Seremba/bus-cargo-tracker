import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart'
    hide PrinterType;

import '../../models/printer_settings.dart';
import '../../services/printing/printer_auto_detect_service.dart';
import '../../services/printing/printer_service.dart';
import '../../services/printing/printer_settings_service.dart';
import '../../services/printing/urovo_printer_service.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  bool _scanning = false;
  final bool _isBle = false;
  List<PrinterDevice> _devices = [];
  PrinterDevice? _connected;
  int _paperMm = 58;
  PrinterType _selectedType = PrinterType.auto;
  String _detectedDevice = 'Detecting...';
  PrinterType _detectedType = PrinterType.auto;

  @override
  void initState() {
    super.initState();
    final s = PrinterSettingsService.getOrCreate();
    _paperMm = s.paperMm;
    _selectedType = s.printerType;
    _loadDetectedDevice();
  }

  Future<void> _loadDetectedDevice() async {
    final summary =
        await PrinterAutoDetectService.detectedDeviceSummary();
    final detected = await PrinterAutoDetectService.detect();
    if (!mounted) return;
    setState(() {
      _detectedDevice = summary;
      _detectedType = detected;
    });
  }

  String _detectedTypeLabel(PrinterType t) {
    switch (t) {
      case PrinterType.urovoInternal:
        return 'Built-in Urovo printer';
      case PrinterType.sunmiInternal:
        return 'Built-in Sunmi printer';
      case PrinterType.serialInternal:
        return 'Built-in serial printer';
      case PrinterType.bluetooth:
        return 'Bluetooth printer';
      default:
        return 'Unknown';
    }
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });
    await for (final list
        in PrinterService.scanBluetooth(isBle: _isBle)) {
      if (!mounted) return;
      setState(() => _devices = list);
    }
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connect(PrinterDevice d) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await PrinterService.connectBluetooth(d, isBle: _isBle);
    if (!mounted) return;
    if (!ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Connect failed ❌')));
      return;
    }
    setState(() => _connected = d);
    await PrinterSettingsService.saveBluetooth(
      address: d.address ?? '',
      name: d.name,
      paperMm: _paperMm,
    );
    final label = d.name.isNotEmpty ? d.name : (d.address ?? 'Printer');
    messenger
        .showSnackBar(SnackBar(content: Text('Connected ✅ $label')));
  }

  Future<void> _testPrint() async {
    final messenger = ScaffoldMessenger.of(context);
    final effective = await PrinterSettingsService.effectiveType();

    bool ok;
    if (effective == PrinterType.urovoInternal) {
      ok = await UrovoPrinterService.testPrint();
    } else {
      final bytes = Uint8List.fromList([
        0x1B, 0x40,
        ...'UNEX TEST\n\n'.codeUnits,
      ]);
      ok = await PrinterService.printBytesBluetooth(bytes);
    }

    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(
          content: Text(ok ? 'Test printed ✅' : 'Print failed ❌')),
    );
  }

  Widget _paperToggle() {
    return Row(
      children: [
        const Text('Paper:'),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('58mm'),
          selected: _paperMm == 58,
          onSelected: (_) => setState(() => _paperMm = 58),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('80mm'),
          selected: _paperMm == 80,
          onSelected: (_) => setState(() => _paperMm = 80),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Printer Setup')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [

          // ── Auto-detect info card ──────────────────────────────────
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: cs.primary.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.device_unknown_outlined,
                        size: 16, color: cs.primary),
                    const SizedBox(width: 8),
                    const Text(
                      'Detected device',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_detectedDevice,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  'Auto-selected: ${_detectedTypeLabel(_detectedType)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Printer type tiles ─────────────────────────────────────
          const Text(
            'Printer mode',
            style:
                TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 8),

          _printerTypeTile(
            icon: Icons.auto_fix_high,
            title: 'Auto-detect (recommended)',
            subtitle:
                'App detects the device automatically — works on any POS',
            selected: _selectedType == PrinterType.auto,
            onTap: () async {
              setState(() => _selectedType = PrinterType.auto);
              await PrinterSettingsService.saveAutoDetect(
                  paperMm: _paperMm);
              if (!mounted) return;
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Auto-detect enabled ✅')),
              );
            },
          ),
          const SizedBox(height: 8),

          _printerTypeTile(
            icon: Icons.print,
            title: 'Built-in printer (Urovo Q2I)',
            subtitle:
                'Force use of Urovo internal printer on this device',
            selected: _selectedType == PrinterType.urovoInternal,
            onTap: () async {
              setState(
                  () => _selectedType = PrinterType.urovoInternal);
              await PrinterSettingsService.saveUrovoInternal(
                  paperMm: _paperMm);
              if (!mounted) return;
              // ignore: use_build_context_synchronously
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content:
                        Text('Built-in printer configured ✅')),
              );
            },
          ),
          const SizedBox(height: 8),

          _printerTypeTile(
            icon: Icons.bluetooth,
            title: 'Bluetooth printer',
            subtitle:
                'Connect to an external Bluetooth thermal printer',
            selected: _selectedType == PrinterType.bluetooth,
            onTap: () =>
                setState(() => _selectedType = PrinterType.bluetooth),
          ),
          const SizedBox(height: 16),

          _paperToggle(),
          const SizedBox(height: 16),

          // ── Bluetooth scan ─────────────────────────────────────────
          if (_selectedType == PrinterType.bluetooth) ...[
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text(
                        _scanning ? 'Scanning...' : 'Scan Printers'),
                    onPressed: _scanning ? null : _scan,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _connected == null ? null : _testPrint,
                  child: const Text('Test'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_devices.isEmpty)
              const Center(child: Text('No printers found yet.'))
            else
              ...(_devices.map((d) {
                final isConnected = _connected?.address == d.address;
                final title =
                    d.name.isNotEmpty ? d.name : (d.address ?? 'Printer');
                return Card(
                  child: ListTile(
                    title: Text(title),
                    subtitle: Text(d.address ?? '—'),
                    trailing: isConnected
                        ? const Icon(Icons.check_circle,
                            color: Colors.green)
                        : const Icon(Icons.bluetooth),
                    onTap: () => _connect(d),
                  ),
                );
              })),
          ],

          // ── Internal printer test ──────────────────────────────────
          if (_selectedType != PrinterType.bluetooth) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.print_outlined),
                label: const Text('Test printer'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: cs.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _testPrint,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _printerTypeTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? cs.primary : Colors.grey,
                size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.primary : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: cs.primary, size: 22),
          ],
        ),
      ),
    );
  }
}