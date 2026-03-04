import 'dart:async';

import 'outbound_message_service.dart';

class OutboundQueueRunner {
  OutboundQueueRunner._();

  static Timer? _timer;
  static bool _busy = false;

  // How often to check if something is queued/failed and due.
  static const Duration tick = Duration(seconds: 20);

  static void start() {
    if (_timer != null) return;

    _timer = Timer.periodic(tick, (_) async {
      if (_busy) return;
      _busy = true;

      try {
        // This will open WhatsApp/SMS composer if something is due.
        await OutboundMessageService.processQueueOpenNext();
      } catch (_) {
        // Never crash the app due to background retry loop.
      } finally {
        _busy = false;
      }
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _busy = false;
  }
}