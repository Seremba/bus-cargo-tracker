import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/pickup_qr_service.dart';

class PickupQrScannerScreen extends StatefulWidget {
  const PickupQrScannerScreen({super.key});

  @override
  State<PickupQrScannerScreen> createState() => _PickupQrScannerScreenState();
}

class _PickupQrScannerScreenState extends State<PickupQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose(); // release camera
    super.dispose();
  }

  Future<void> _stopCameraSafe() async {
    try {
      await _controller.stop();
    } catch (_) {
      // ignore: controller may already be stopped/disposed
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Pickup QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) async {
          if (_done) return;

          final barcodes = capture.barcodes;
          if (barcodes.isEmpty) return;

          final raw = barcodes.first.rawValue;
          if (raw == null) return;

          final value = raw.trim();
          if (value.isEmpty) return;

          // Validate it matches your pickup payload format before returning
          final parsed = PickupQrService.parsePayload(value);
          if (parsed == null) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid pickup QR')),
            );
            return;
          }

          _done = true;

          //  stop camera ASAP to avoid double fires
          await _stopCameraSafe();

          if (!context.mounted) return;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}
