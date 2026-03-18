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
      // per calendar day, so calling it here is safe even at 30-min intervals.
      await PropertyTtlService.runChecks();
    } catch (_) {
      // Keep silent — never crash the app due to background work.
    } finally {
      _syncing = false;
    }
  }
}