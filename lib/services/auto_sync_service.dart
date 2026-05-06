import 'dart:async';
import 'package:flutter/widgets.dart';

import 'property_ttl_service.dart';
import 'session.dart';
import 'sync_service.dart';

class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();

  Timer? _timer;
  Timer? _foregroundTimer;
  bool _started = false;
  bool _syncing = false;
  bool _inForeground = true;

  // Background safety net — catches up from offline/background periods.
  static const Duration _backgroundInterval = Duration(minutes: 1);

  // Foreground aggressive pull — near-realtime for desk officers and admin.
  // 15s means maximum 15s delay between a sender registering and the
  // property appearing on the desk officer's screen.
  static const Duration _foregroundInterval = Duration(seconds: 15);

  // Phase 4: prune once per week
  static const Duration _pruneInterval = Duration(days: 7);
  DateTime? _lastPrunedAt;

  bool get isStarted => _started;
  bool get isSyncing => _syncing;

  Future<void> start() async {
    if (_started) return;

    _started = true;
    _inForeground = true;
    WidgetsBinding.instance.addObserver(this);

    // Immediate sync on start
    _safeSync();

    // Aggressive foreground ticker — near-realtime pull
    _startForegroundTimer();

    // Background safety net
    _timer = Timer.periodic(_backgroundInterval, (_) {
      if (!_inForeground) _safeSync();
    });
  }

  void _startForegroundTimer() {
    _foregroundTimer?.cancel();
    _foregroundTimer = Timer.periodic(_foregroundInterval, (_) {
      if (_inForeground) _safeSync();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _foregroundTimer?.cancel();
    _timer = null;
    _foregroundTimer = null;

    if (_started) {
      WidgetsBinding.instance.removeObserver(this);
    }

    _started = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;

    if (state == AppLifecycleState.resumed) {
      _inForeground = true;
      _startForegroundTimer();
      // Immediate sync on resume to catch up from background
      _safeSync();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _inForeground = false;
      // Stop aggressive polling when app is in background
      _foregroundTimer?.cancel();
      _foregroundTimer = null;
    }
  }

  Future<void> _safeSync() async {
    // Don't sync until a user is logged in.
    // On a fresh install, pulling remote user events before login creates
    // password-less shells that interfere with authentication.
    // Sync only makes sense when there is an active session anyway.
    if (Session.currentUserId == null ||
        (Session.currentUserId ?? '').trim().isEmpty) {
      return;
    }

    if (_syncing) return;

    _syncing = true;
    try {
      await SyncService.syncNow();

      // TTL checks — internally rate-limited to once per calendar day
      await PropertyTtlService.runChecks();

      // Phase 4: weekly pruning
      await _maybePrune();
    } on StateError catch (e) {
      // Surface API key config errors in debug builds.
      final msg = e.message;
      if (msg.contains('API key') || msg.contains('SYNC_API_KEY')) {
        assert(false, '[AutoSyncService] $msg');
      }
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

  /// Triggers an immediate sync when connectivity is restored.
  /// Already wired in main.dart via Connectivity().onConnectivityChanged.
  Future<void> triggerNow() => _safeSync();
}