import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class PropertyQrScannerScreen extends StatefulWidget {
  const PropertyQrScannerScreen({super.key});

  @override
  State<PropertyQrScannerScreen> createState() => _PropertyQrScannerScreenState();
}

class _PropertyQrScannerScreenState extends State<PropertyQrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _reset() => setState(() => _done = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Property QR'),
        actions: [
          IconButton(
            tooltip: 'Torch',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_done) return;

              final barcodes = capture.barcodes;
              if (barcodes.isEmpty) return;

              final raw = barcodes.first.rawValue;
              if (raw == null || raw.trim().isEmpty) return;

              setState(() => _done = true);
              Navigator.pop(context, raw.trim());
            },
          ),

          if (_done)
            Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                child: InkWell(
                  onTap: _reset,
                  child: const Center(
                    child: Text(
                      'Scanned ✅\nTap to scan again',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
