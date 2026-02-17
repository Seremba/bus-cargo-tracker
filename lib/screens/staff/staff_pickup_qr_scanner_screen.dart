import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/pickup_qr_service.dart';

class StaffPickupQrScannerScreen extends StatefulWidget {
  const StaffPickupQrScannerScreen({super.key});

  @override
  State<StaffPickupQrScannerScreen> createState() =>
      _StaffPickupQrScannerScreenState();
}

class _StaffPickupQrScannerScreenState extends State<StaffPickupQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose(); // ✅ release camera
    super.dispose();
  }

  Future<void> _stopCameraSafe() async {
    try {
      await _controller.stop();
    } catch (_) {
      // ignore (already stopped/disposed)
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Scan Pickup QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) async {
          if (_done) return;

          final codes = capture.barcodes;
          if (codes.isEmpty) return;

          final raw = codes.first.rawValue;
          if (raw == null) return;

          final value = raw.trim();
          if (value.isEmpty) return;

          // ✅ Validate QR format before proceeding
          final parsed = PickupQrService.parsePayload(value);
          if (parsed == null) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid pickup QR')),
            );
            return;
          }

          _done = true;

          // ✅ stop camera ASAP to prevent double fires
          await _stopCameraSafe();

          if (!context.mounted) return;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}
