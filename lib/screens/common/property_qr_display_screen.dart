import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/property_lookup_service.dart';
import '../../services/property_qr_service.dart';
import '../../services/property_service.dart';

class PropertyQrDisplayScreen extends StatefulWidget {
  final String propertyCode;

  const PropertyQrDisplayScreen({super.key, required this.propertyCode});

  @override
  State<PropertyQrDisplayScreen> createState() =>
      _PropertyQrDisplayScreenState();
}

class _PropertyQrDisplayScreenState extends State<PropertyQrDisplayScreen> {
  // Key used to capture the QR widget as an image
  final GlobalKey _qrKey = GlobalKey();
  bool _saving = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final m = ScaffoldMessenger.of(context);
      m.clearSnackBars();
      m.hideCurrentSnackBar();

      final property = PropertyLookupService.findByPropertyCode(
        widget.propertyCode.trim(),
      );
      if (property != null) {
        PropertyService.lockProperty(property).catchError((_) {});
      }
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

  /// Captures the QR widget as a PNG and saves it to the device's
  /// Downloads or Documents folder, then shares it so the user can
  /// save it to their gallery or send it via WhatsApp/SMS.
  Future<void> _saveQr(String code) async {
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Capture the QR widget as an image
      final boundary = _qrKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _snack('Could not capture QR. Try again.');
        return;
      }

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        _snack('Could not generate image. Try again.');
        return;
      }

      final pngBytes = byteData.buffer.asUint8List();

      // Save to a temp file
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/unex_qr_$code.png');
      await file.writeAsBytes(pngBytes);

      if (!mounted) return;

      // Share the image — user can save to gallery or send via any app
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        text: 'UNEx Logistics QR — Property: $code',
        subject: 'UNEx QR Code',
      );
    } catch (e) {
      if (mounted) _snack('Failed to save QR: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.showSnackBar(SnackBar(content: Text(msg)));
  }

  void _done() {
    final m = ScaffoldMessenger.of(context);
    m.clearSnackBars();
    m.hideCurrentSnackBar();

    if (Navigator.canPop(context)) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.propertyCode.trim();
    final payload = PropertyQrService.encodePropertyCode(code);
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.70);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
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
                  // Wrap QR in RepaintBoundary so we can capture it as image
                  RepaintBoundary(
                    key: _qrKey,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          QrImageView(data: payload, size: 240),
                          const SizedBox(height: 8),
                          Text(
                            code,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.6,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'UNEx Logistics',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

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
                    'Show this QR to the Desk Cargo Officer.\nSave or share it so you always have it ready.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),

                  const SizedBox(height: 14),

                  // ── Copy + Share row ──────────────────────────────────
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
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.share),
                          label: const Text('Share code'),
                          onPressed: () => _share(code),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // ── Save QR image button ──────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download_outlined),
                      label: Text(_saving ? 'Saving…' : 'Save QR Image'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: cs.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _saving ? null : () => _saveQr(code),
                    ),
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