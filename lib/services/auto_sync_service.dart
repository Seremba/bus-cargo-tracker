import 'dart:async';
import 'package:flutter/widgets.dart';

import 'property_ttl_service.dart';
import 'sync_service.dart';

class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();

  Timer? _timer;
  bool _started = false;
  bool _syncing = false;

  // Phase 5 (upcoming): interval will be reduced to 5 minutes.
  // Keeping at 30 s for now until Phase 5 connectivity-aware strategy lands.
  static const Duration _interval = Duration(seconds: 30);

  bool get isStarted => _started;
  bool get isSyncing => _syncing;

  Future<void> start() async {
    if (_started) return;

    _started = true;
    WidgetsBinding.instance.addObserver(this);

    _safeSync();

    _timer = Timer.periodic(_interval, (_) {
      _safeSync();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }

    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;

    if (state == AppLifecycleState.resumed) {
      _safeSync();
    }
  }

  Future<void> _safeSync() async {
    if (_syncing) return;

    _syncing = true;
    try {
      await SyncService.syncNow();

      // F5: run TTL checks on every sync tick.
      // PropertyTtlService.runChecks() is internally rate-limited to once
      // per calendar day, so calling it here is safe even at 30-s intervals.
      await PropertyTtlService.runChecks();
    } on StateError catch (e) {
     
      final msg = e.message;
      if (msg.contains('API key') || msg.contains('SYNC_API_KEY')) {
        // Do not crash the app, but assert in debug mode so devs catch it fast.
        assert(false, '[AutoSyncService] $msg');
        // In release mode, silently stop retrying until the key is set.
        // Optionally: emit to a stream that the admin dashboard listens to.
      }
      // All other StateErrors (HTTP 5xx, upstream timeouts) stay silent.
    } catch (_) {
      // Catch-all: never crash the app due to background sync work.
    } finally {
      _syncing = false;
    }
  }
}