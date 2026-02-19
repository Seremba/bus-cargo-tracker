import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

import '../../services/printing/printer_service.dart';
import '../../services/printing/printer_settings_service.dart';

class PrinterSetupScreen extends StatefulWidget {
  const PrinterSetupScreen({super.key});

  @override
  State<PrinterSetupScreen> createState() => _PrinterSetupScreenState();
}

class _PrinterSetupScreenState extends State<PrinterSetupScreen> {
  bool _scanning = false;
  final bool _isBle = false; // keep false for classic Bluetooth printers first
  List<PrinterDevice> _devices = [];
  PrinterDevice? _connected;

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _devices = [];
    });

    await for (final list in PrinterService.scanBluetooth(isBle: _isBle)) {
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
      messenger.showSnackBar(const SnackBar(content: Text('Connect failed ❌')));
      return;
    }

    setState(() => _connected = d);

    PrinterSettingsService.saveBluetooth(
      address: d.address ?? '',
      name: d.name,
      paperMm: 58,
    );

    final label = d.name.isNotEmpty ? d.name : (d.address ?? 'Printer');
    messenger.showSnackBar(SnackBar(content: Text('Connected ✅ $label')));
  }

  Future<void> _testPrint() async {
    final messenger = ScaffoldMessenger.of(context);

    // init only (ESC @)
    final bytes = Uint8List.fromList([0x1B, 0x40]);

    final ok = await PrinterService.printBytesBluetooth(bytes);
    if (!mounted) return;

    messenger.showSnackBar(
      SnackBar(content: Text(ok ? 'Test sent ✅' : 'Print failed ❌')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Printer Setup (Bluetooth)')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.search),
                    label: Text(_scanning ? 'Scanning...' : 'Scan Printers'),
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
            Expanded(
              child: _devices.isEmpty
                  ? const Center(child: Text('No printers found yet.'))
                  : ListView.builder(
                      itemCount: _devices.length,
                      itemBuilder: (_, i) {
                        final d = _devices[i];
                        final isConnected = _connected?.address == d.address;
                        return Card(
                          child: ListTile(
                            title: Text(
                              d.name.isNotEmpty
                                  ? d.name
                                  : (d.address ?? 'Printer'),
                            ),
                            subtitle: Text(d.address ?? '—'),
                            trailing: isConnected
                                ? const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                  )
                                : const Icon(Icons.bluetooth),
                            onTap: () => _connect(d),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
