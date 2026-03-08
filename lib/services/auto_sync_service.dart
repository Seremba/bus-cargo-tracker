import 'dart:async';
import 'package:flutter/widgets.dart';

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
    } catch (_) {
      // Keep silent for now.
    } finally {
      _syncing = false;
    }
  }
}