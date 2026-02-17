import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/property_qr_service.dart';

class PropertyQrDisplayScreen extends StatelessWidget {
  final String propertyCode;
  const PropertyQrDisplayScreen({super.key, required this.propertyCode});

  @override
  Widget build(BuildContext context) {
    final code = propertyCode.trim();
    final payload = PropertyQrService.encodePropertyCode(code);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Property QR')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                QrImageView(
                  data: payload,
                  size: 220,
                ),
                const SizedBox(height: 12),
                Text(
                  code,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Stick this QR on the cargo/receipt.\nDesk Cargo Officer scans it to record payment.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy code'),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: code));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied ✅')),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.share),
                        label: const Text('Share'),
                        onPressed: () async {
                          await Share.share('Property Code: $code\nQR payload: $payload');
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
