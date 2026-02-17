import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class DeskPropertyQrScannerScreen extends StatefulWidget {
  const DeskPropertyQrScannerScreen({super.key});

  @override
  State<DeskPropertyQrScannerScreen> createState() => _DeskPropertyQrScannerScreenState();
}

class _DeskPropertyQrScannerScreenState extends State<DeskPropertyQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Scan Property QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) async {
          if (_done) return;

          final codes = capture.barcodes;
          if (codes.isEmpty) return;

          final raw = codes.first.rawValue;
          if (raw == null || raw.trim().isEmpty) return;

          setState(() => _done = true);

          // stop camera ASAP to prevent double fires
          await _controller.stop();

          if (!context.mounted) return;
          Navigator.pop(context, raw.trim());
        },
      ),
    );
  }
}
