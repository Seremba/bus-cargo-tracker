import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import '../models/sync_run_result.dart';
import 'hive_service.dart';
import 'payment_service.dart';
import 'property_item_service.dart';
import 'property_service.dart';
import 'trip_service.dart';

class SyncService {
  static const String _baseUrl = 'https://bus-cargo-sync.pserembae.workers.dev';
  static const String _eventsBatchPath = '/events/batch';
  static const String _eventsPullPath = '/events';
  static final _uuid = const Uuid();

  static const String _cursorKey = 'lastSyncCursor';
  static const String _deviceIdKey = 'deviceId';

  /// Phase 1: API key is stored in Hive appSettingsBox under this key.
  /// Set once at app init (from build config / secure storage handoff).
  static const String _apiKeySettingsKey = 'syncApiKey';

  /// Returns the sync API key stored in local settings, or empty string.
  static String _getApiKey() {
    final box = HiveService.appSettingsBox();
    return (box.get(_apiKeySettingsKey) as String? ?? '').trim();
  }

  /// Persists the sync API key to Hive settings.
  /// Call this once during first-run / provisioning, not on every sync.
  static Future<void> setApiKey(String key) async {
    final box = HiveService.appSettingsBox();
    await box.put(_apiKeySettingsKey, key.trim());
  }

  /// Whether an API key has been configured on this device.
  static bool hasApiKey() => _getApiKey().isNotEmpty;

  /// Builds request headers for all Worker calls.
  /// Includes Content-Type and the X-Api-Key auth header (Phase 1).
  static Map<String, String> _headers() {
    final key = _getApiKey();
    return {
      'Content-Type': 'application/json',
      if (key.isNotEmpty) 'X-Api-Key': key,
    };
  }

  static String newEventId() => _uuid.v4();

  static Map<String, dynamic> _jsonSafePayload(Map<String, dynamic> payload) {
    return Map<String, dynamic>.from(payload);
  }

  static String? getLastCursor() {
    final box = HiveService.appSettingsBox();
    return box.get(_cursorKey) as String?;
  }

  static Future<void> setLastCursor(String cursor) async {
    final box = HiveService.appSettingsBox();
    await box.put(_cursorKey, cursor);
  }

  static String? getDeviceId() {
    final box = HiveService.appSettingsBox();
    return box.get(_deviceIdKey) as String?;
  }

  static Future<String> ensureDeviceId() async {
    final box = HiveService.appSettingsBox();

    final existing = (box.get(_deviceIdKey) as String?)?.trim();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final timestamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final entropy = List.generate(
      12,
      (_) => random.nextInt(36).toRadixString(36),
    ).join().toUpperCase();

    final deviceId = 'DEV-$timestamp-$entropy';

    await box.put(_deviceIdKey, deviceId);
    return deviceId;
  }

  static Future<bool> isThisDeviceEvent(SyncEvent event) async {
    final current = await ensureDeviceId();
    return event.sourceDeviceId.trim() == current.trim();
  }

  static Future<SyncEvent> enqueue({
    required SyncEventType type,
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    int aggregateVersion = 1,
  }) async {
    final box = HiveService.syncEventBox();

    final cleanAggregateType = aggregateType.trim();
    final cleanAggregateId = aggregateId.trim();
    final cleanActorUserId = actorUserId.trim();

    if (cleanAggregateType.isEmpty) {
      throw ArgumentError('aggregateType cannot be empty');
    }
    if (cleanAggregateId.isEmpty) {
      throw ArgumentError('aggregateId cannot be empty');
    }

    final deviceId = await ensureDeviceId();

    final event = SyncEvent(
      eventId: newEventId(),
      type: type,
      aggregateType: cleanAggregateType,
      aggregateId: cleanAggregateId,
      actorUserId: cleanActorUserId,
      payload: _jsonSafePayload(payload),
      createdAt: DateTime.now(),
      sourceDeviceId: deviceId,
      aggregateVersion: aggregateVersion,
    );

    await box.put(event.eventId, event);
    return event;
  }

  static Future<SyncEvent> enqueuePropertyCreated({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    int aggregateVersion = 1,
  }) {
    return enqueue(
      type: SyncEventType.propertyCreated,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePaymentRecorded({
    required String paymentId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    int aggregateVersion = 1,
  }) {
    return enqueue(
      type: SyncEventType.paymentRecorded,
      aggregateType: 'payment',
      aggregateId: paymentId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePaymentRefunded({
    required String paymentId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.paymentRefunded,
      aggregateType: 'payment',
      aggregateId: paymentId,
      actorUserId: actorUserId,
      aggregateVersion: aggregateVersion,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePaymentAdjusted({
    required String paymentId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.paymentAdjusted,
      aggregateType: 'payment',
      aggregateId: paymentId,
      actorUserId: actorUserId,
      aggregateVersion: aggregateVersion,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueueTripStarted({
    required String tripId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    int aggregateVersion = 1,
  }) {
    return enqueue(
      type: SyncEventType.tripStarted,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueueTripCheckpointReached({
    required String tripId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.tripCheckpointReached,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueueTripEnded({
    required String tripId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.tripEnded,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueueTripCancelled({
    required String tripId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.tripCancelled,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<void> enqueueItemsLoadedPartial({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) async {
    await enqueue(
      type: SyncEventType.itemsLoadedPartial,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      aggregateVersion: aggregateVersion,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePropertyInTransit({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.propertyInTransit,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePropertyDelivered({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.propertyDelivered,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePropertyPickedUp({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.propertyPickedUp,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueueItemEvent({
    required SyncEventType type,
    required String itemId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: type,
      aggregateType: 'propertyItem',
      aggregateId: itemId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueuePropertyItemLoaded({
    required String itemId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueueItemEvent(
      type: SyncEventType.propertyItemLoaded,
      itemId: itemId,
      actorUserId: actorUserId,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePropertyItemInTransit({
    required String itemId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueueItemEvent(
      type: SyncEventType.propertyItemInTransit,
      itemId: itemId,
      actorUserId: actorUserId,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePropertyItemDelivered({
    required String itemId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueueItemEvent(
      type: SyncEventType.propertyItemDelivered,
      itemId: itemId,
      actorUserId: actorUserId,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePropertyItemPickedUp({
    required String itemId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueueItemEvent(
      type: SyncEventType.propertyItemPickedUp,
      itemId: itemId,
      actorUserId: actorUserId,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueueExceptionLogged({
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.exceptionLogged,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueAdminOverrideApplied({
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.adminOverrideApplied,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static bool exists(String eventId) {
    final box = HiveService.syncEventBox();
    return box.containsKey(eventId.trim());
  }

  static SyncEvent? getById(String eventId) {
    final box = HiveService.syncEventBox();
    return box.get(eventId.trim());
  }

  static List<SyncEvent> pendingPushEvents() {
    final box = HiveService.syncEventBox();

    return box.values.where((e) => e.pendingPush && !e.pushed).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> markPushed(String eventId, {String? remoteCursor}) async {
    final event = getById(eventId);
    if (event == null) return;

    event.pendingPush = false;
    event.pushed = true;
    event.lastError = '';

    if (remoteCursor != null && remoteCursor.trim().isNotEmpty) {
      event.remoteCursor = remoteCursor.trim();
    }

    await event.save();
  }

  static Future<void> markPushFailed(String eventId, String error) async {
    final event = getById(eventId);
    if (event == null) return;

    event.pendingPush = true;
    event.pushed = false;
    event.pushAttempts += 1;
    event.lastPushAttemptAt = DateTime.now();
    event.lastError = error.trim();

    await event.save();
  }

  static Future<void> markAppliedLocally(String eventId) async {
    final event = getById(eventId);
    if (event == null) return;

    event.appliedLocally = true;
    await event.save();
  }

  /// Applies a remote event to local Hive state.
  ///
  /// Phase 2 conflict guard: each aggregate-level apply method is already
  /// responsible for checking `aggregateVersion` before mutating state
  /// (pattern: `if (property.aggregateVersion >= incomingVersion) return`).
  /// That guard is the single source of truth — we do not duplicate it here.
  ///
  /// What we add here is an event-level guard for events that carry a
  /// version in their payload but whose apply handler does NOT yet check it
  /// (e.g. exceptionLogged, adminOverrideApplied, item-level events).
  /// For those we skip silently — they are audit / observational events
  /// that carry no local state mutation requiring ordering protection.
  static Future<void> applyEvent(SyncEvent event) async {
    if (event.appliedLocally) return;

    switch (event.type) {
      case SyncEventType.propertyCreated:
        await PropertyService.applyPropertyCreatedFromSync(event);
        break;

      case SyncEventType.paymentRecorded:
      case SyncEventType.paymentRefunded:
      case SyncEventType.paymentAdjusted:
        await PaymentService.applyPaymentRecordedFromSync(event);
        break;

      case SyncEventType.tripStarted:
        await TripService.applyTripStartedFromSync(event);
        break;

      case SyncEventType.tripCheckpointReached:
        await TripService.applyTripCheckpointReachedFromSync(event);
        break;

      case SyncEventType.tripEnded:
        await TripService.applyTripEndedFromSync(event);
        break;

      case SyncEventType.tripCancelled:
        await TripService.applyTripCancelledFromSync(event);
        break;

      case SyncEventType.itemsLoadedPartial:
        await PropertyService.applyItemsLoadedPartialFromSync(event);
        break;

      case SyncEventType.propertyInTransit:
        await PropertyService.applyPropertyInTransitFromSync(event);
        break;

      case SyncEventType.propertyDelivered:
        await PropertyService.applyPropertyDeliveredFromSync(event);
        break;

      case SyncEventType.propertyPickedUp:
        await PropertyService.applyPropertyPickedUpFromSync(event);
        break;

      case SyncEventType.propertyItemLoaded:
        await PropertyItemService.applyPropertyItemLoadedFromSync(event);
        break;

      case SyncEventType.propertyItemInTransit:
        await PropertyItemService.applyPropertyItemInTransitFromSync(event);
        break;

      case SyncEventType.propertyItemDelivered:
        await PropertyItemService.applyPropertyItemDeliveredFromSync(event);
        break;

      case SyncEventType.propertyItemPickedUp:
        await PropertyItemService.applyPropertyItemPickedUpFromSync(event);
        break;

      // Observational / audit-only events — no local state mutation needed.
      case SyncEventType.exceptionLogged:
      case SyncEventType.adminOverrideApplied:
        break;

      default:
        throw UnsupportedError(
          'Sync event type not supported yet: ${event.type}',
        );
    }

    await markAppliedLocally(event.eventId);
  }

  static Future<int> pushPendingEvents() async {
    final pending = pendingPushEvents();
    if (pending.isEmpty) return 0;

    // Phase 1: abort push if no API key is configured.
    // This prevents silently hitting a 401 on every sync.
    if (!hasApiKey()) {
      throw StateError(
        'Sync API key not configured. '
        'Call SyncService.setApiKey() during app init.',
      );
    }

    final uri = Uri.parse('$_baseUrl$_eventsBatchPath');

    final body = jsonEncode({
      'events': pending.map((e) => e.toJson()).toList(),
    });

    // Phase 1: _headers() injects X-Api-Key
    final response = await http.post(uri, headers: _headers(), body: body);

    if (response.statusCode == 401) {
      // API key wrong / missing — do not mark events as failed, just surface
      // the error so the caller can handle it without burning retry budget.
      throw StateError(
        'Sync push rejected: invalid API key (HTTP 401). '
        'Check syncApiKey in app settings.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      for (final event in pending) {
        await markPushFailed(
          event.eventId,
          'HTTP ${response.statusCode}: ${response.body}',
        );
      }
      throw StateError('Push failed with HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final accepted =
        (decoded['acceptedEventIds'] as List?)?.cast<dynamic>() ?? const [];

    int pushedCount = 0;

    for (final rawId in accepted) {
      final eventId = rawId.toString();
      await markPushed(eventId);
      pushedCount += 1;
    }

    return pushedCount;
  }

  static Future<Map<String, int>> pullRemoteEvents() async {
    // Phase 1: abort pull if no API key is configured.
    if (!hasApiKey()) {
      throw StateError(
        'Sync API key not configured. '
        'Call SyncService.setApiKey() during app init.',
      );
    }

    final after = getLastCursor();

    final uri = Uri.parse(
      after == null || after.isEmpty
          ? '$_baseUrl$_eventsPullPath'
          : '$_baseUrl$_eventsPullPath?after=$after',
    );

    // Phase 1: _headers() injects X-Api-Key
    final response = await http.get(uri, headers: _headers());

    if (response.statusCode == 401) {
      throw StateError(
        'Sync pull rejected: invalid API key (HTTP 401). '
        'Check syncApiKey in app settings.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Pull failed with HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final rawEvents = (decoded['events'] as List?) ?? const [];

    int pulled = 0;
    int applied = 0;
    int failed = 0;

    for (final raw in rawEvents) {
      pulled += 1;

      try {
        final event = SyncEvent.fromJson(Map<String, dynamic>.from(raw as Map));

        if (await isThisDeviceEvent(event)) {
          // This device originated the event — mark self-echo as applied.
          final existingSelf = getById(event.eventId);
          if (existingSelf != null && !existingSelf.appliedLocally) {
            await markAppliedLocally(existingSelf.eventId);
          }
          continue;
        }

        final existing = getById(event.eventId);

        if (existing != null) {
          if (!existing.appliedLocally) {
            await applyEvent(existing);
            applied += 1;
          }
          continue;
        }

        // Phase 2: SyncEvent.fromJson already reads aggregateVersion from
        // the JSON. The apply handlers enforce the version guard internally.
        await HiveService.syncEventBox().put(event.eventId, event);
        await applyEvent(event);
        applied += 1;
      } catch (_) {
        failed += 1;
      }
    }

    final nextCursor = decoded['nextCursor']?.toString();
    if (nextCursor != null && nextCursor.isNotEmpty) {
      await setLastCursor(nextCursor);
    }

    return {'pulled': pulled, 'applied': applied, 'failed': failed};
  }

  static Future<SyncRunResult> syncNow() async {
    int pushed = 0;
    int pulled = 0;
    int applied = 0;
    int failed = 0;

    pushed = await pushPendingEvents();

    final pull = await pullRemoteEvents();

    pulled = pull['pulled'] ?? 0;
    applied = pull['applied'] ?? 0;
    failed = pull['failed'] ?? 0;

    return SyncRunResult(
      pushed: pushed,
      pulled: pulled,
      applied: applied,
      failed: failed,
    );
  }
}
