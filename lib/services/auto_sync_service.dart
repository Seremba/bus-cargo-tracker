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

  // Phase 5: reduced from 30s → 5 minutes.
  // Write-triggered sync (SyncService.enqueue) handles immediate pushes.
  // This ticker is now a safety net for:
  //   • Failed pushes that need retry after backoff clears
  //   • Pull (receiving events written by other devices)
  //   • Devices returning from offline/background
  static const Duration _interval = Duration(minutes: 5);

  // Phase 4: prune once per week
  static const Duration _pruneInterval = Duration(days: 7);
  DateTime? _lastPrunedAt;

  bool get isStarted => _started;
  bool get isSyncing => _syncing;

  Future<void> start() async {
    if (_started) return;

    _started = true;
    WidgetsBinding.instance.addObserver(this);

    // Immediate sync on start — catches up from any offline period
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

    // Phase 5: sync on app resume — catches up from background/offline period
    if (state == AppLifecycleState.resumed) {
      _safeSync();
    }
  }

  Future<void> _safeSync() async {
    if (_syncing) return;

    _syncing = true;
    try {
      await SyncService.syncNow();

      // F5: TTL checks — internally rate-limited to once per calendar day
      await PropertyTtlService.runChecks();

      // Phase 4: weekly pruning
      await _maybePrune();
    } on StateError catch (e) {
      // Phase 1: surface API key config errors in debug builds.
      // These are configuration problems, not transient failures.
      final msg = e.message;
      if (msg.contains('API key') || msg.contains('SYNC_API_KEY')) {
        assert(false, '[AutoSyncService] $msg');
        // In release: silently stop until key is configured.
      }
      // All other StateErrors (HTTP 5xx, upstream timeouts) stay silent.
    } catch (_) {
      // Never crash the app due to background sync work.
    } finally {
      _syncing = false;
    }
  }

  // ── Phase 4: weekly pruning ────────────────────────────────────────────────

  Future<void> _maybePrune() async {
    final last = _lastPrunedAt;
    if (last != null && DateTime.now().difference(last) < _pruneInterval) {
      return;
    }

    try {
      final result = await SyncService.pruneStaleData();
      _lastPrunedAt = DateTime.now();

      if (result.totalDeleted > 0) {
        assert(() {
          // ignore: avoid_print
          print(
            '[AutoSyncService] Pruned ${result.totalDeleted} stale records: '
            '${result.syncEventsDeleted} sync events, '
            '${result.auditEventsDeleted} audit events, '
            '${result.outboundMessagesDeleted} outbound messages.',
          );
          return true;
        }());
      }
    } catch (_) {
      // Pruning failures are non-critical — boxes just grow a bit longer.
    }
  }

  // ── Phase 5: connectivity-restored trigger ─────────────────────────────────

  /// Call this when connectivity is restored to sync immediately
  /// instead of waiting for the next 5-minute ticker tick.
  ///
  /// Wire up in main.dart alongside AutoSyncService.instance.start():
  ///
  /// ```dart
  /// Connectivity().onConnectivityChanged.listen((result) {
  ///   if (result != ConnectivityResult.none) {
  ///     AutoSyncService.instance.triggerNow();
  ///   }
  /// });
  /// ```
  Future<void> triggerNow() => _safeSync();
}
