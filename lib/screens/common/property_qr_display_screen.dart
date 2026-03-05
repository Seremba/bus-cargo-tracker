import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/property_qr_service.dart';

class PropertyQrDisplayScreen extends StatefulWidget {
  final String propertyCode;

  const PropertyQrDisplayScreen({super.key, required this.propertyCode});

  @override
  State<PropertyQrDisplayScreen> createState() =>
      _PropertyQrDisplayScreenState();
}

class _PropertyQrDisplayScreenState extends State<PropertyQrDisplayScreen> {
  @override
  void initState() {
    super.initState();

    // ✅ Kill any SnackBars queued during transition from previous screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final m = ScaffoldMessenger.of(context);
      m.clearSnackBars();
      m.hideCurrentSnackBar();
    });
  }

  Future<void> _copy(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;

    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(
      const SnackBar(
        content: Text('Property code copied ✅'),
        duration: Duration(milliseconds: 1200),
      ),
    );
  }

  Future<void> _share(String code) async {
    await Share.share(
      'Property Code: $code\n\nUse this code for payment and lookup.',
    );
  }

  void _done() {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.hideCurrentSnackBar();

    if (Navigator.canPop(context)) {
      // ✅ return "true" to tell previous screen to go to My Properties
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.propertyCode.trim();
    final payload = PropertyQrService.encodePropertyCode(code);
    final muted = Theme.of(context).colorScheme.onSurface.withOpacity(0.70);

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
        _done();
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: const Text('Property QR'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _done,
          ),
          actions: [TextButton(onPressed: _done, child: const Text('DONE'))],
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(data: payload, size: 240),
                  const SizedBox(height: 14),
                  SelectableText(
                    code,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stick this QR on the cargo/receipt.\nDesk Cargo Officer scans it to record payment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy code'),
                          onPressed: () => _copy(code),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Share'),
                          onPressed: () => _share(code),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _done,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
