import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import '../models/sync_run_result.dart';
import 'hive_service.dart';
import 'auth_service.dart';
import 'payment_service.dart';
import 'property_item_service.dart';
import 'property_service.dart';
import 'trip_service.dart';

class SyncService {
  static const String _baseUrl = 'https://bus-cargo-sync.pserembae.workers.dev';
  static const String _eventsBatchPath = '/events/batch';
  static const String _eventsPullPath = '/events';
  static final _uuid = const Uuid();

  // ── Settings keys ──────────────────────────────────────────────────────────

  static const String _cursorKey = 'lastSyncCursor';
  static const String _deviceIdKey = 'deviceId';
  static const String _apiKeySettingsKey = 'syncApiKey';

  // Backoff ladder (seconds): 10s, 30s, 1m, 3m, 8m, 15m
  static const List<int> _backoffSeconds = [10, 30, 60, 180, 480, 900];
  static int _consecutiveFailures = 0;
  static DateTime? _nextAllowedSyncAt;

  /// Fires a non-blocking background sync after every enqueue() call.

  static void _triggerBackgroundSync() {
    // ignore: discarded_futures
    Future.microtask(() async {
      try {
        await syncNow();
      } catch (_) {
        // Failures here are handled by the backoff ladder in syncNow().
        // AutoSyncService ticker acts as the retry safety net.
      }
    });
  }

  static String _getApiKey() {
    final box = HiveService.appSettingsBox();
    return (box.get(_apiKeySettingsKey) as String? ?? '').trim();
  }

  static Future<void> setApiKey(String key) async {
    final box = HiveService.appSettingsBox();
    await box.put(_apiKeySettingsKey, key.trim());
  }

  static bool hasApiKey() => _getApiKey().isNotEmpty;

  static Map<String, String> _headers() {
    final key = _getApiKey();
    return {
      'Content-Type': 'application/json',
      if (key.isNotEmpty) 'X-Api-Key': key,
    };
  }

  /// Returns true if the device has any non-none connectivity.
  /// Requires connectivity_plus: ^6.0.0 in pubspec.yaml.
  static Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // If the connectivity API misbehaves, assume online and let the
      // HTTP call fail naturally.
      return true;
    }
  }

  static bool _isInBackoff() {
    final next = _nextAllowedSyncAt;
    if (next == null) return false;
    return DateTime.now().isBefore(next);
  }

  static void _recordFailure() {
    _consecutiveFailures += 1;
    final index = (_consecutiveFailures - 1).clamp(
      0,
      _backoffSeconds.length - 1,
    );
    _nextAllowedSyncAt = DateTime.now().add(
      Duration(seconds: _backoffSeconds[index]),
    );
  }

  static void _recordSuccess() {
    _consecutiveFailures = 0;
    _nextAllowedSyncAt = null;
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
    if (existing != null && existing.isNotEmpty) return existing;

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

    // Phase 5: fire-and-forget sync immediately after every local write.
    _triggerBackgroundSync();

    return event;
  }

  // ── Typed enqueue helpers ──────────────────────────────────────────────────

  // Property

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

  static Future<SyncEvent> enqueuePropertyCommitted({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.propertyCommitted,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePropertyLoaded({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.propertyLoaded,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePropertyStatusManuallyChanged({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.propertyStatusManuallyChanged,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
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

  // Payment

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

  static Future<SyncEvent> enqueuePaymentVoided({
    required String paymentId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.paymentVoided,
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

  static Future<SyncEvent> enqueueReceiptPrinted({
    required String paymentId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.receiptPrinted,
      aggregateType: 'payment',
      aggregateId: paymentId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  // Pickup / security

  static Future<SyncEvent> enqueuePickupOtpGenerated({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.pickupOtpGenerated,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePickupOtpReset({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.pickupOtpReset,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePickupConfirmed({
    required String propertyId,
    required String actorUserId,
    required int aggregateVersion,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.pickupConfirmed,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: aggregateVersion,
    );
  }

  static Future<SyncEvent> enqueuePickupAttemptFailed({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.pickupAttemptFailed,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      // Observational — does not advance aggregateVersion
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueuePickupLockedOut({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.pickupLockedOut,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueQrNonceRotated({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.qrNonceRotated,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  // Items

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

  // Trip

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

  /// Phase 3: renamed from enqueueTripEnded → enqueueTripCompleted.
  /// Update all call sites in trip_service.dart accordingly.
  static Future<SyncEvent> enqueueTripCompleted({
    required String tripId,
    required String actorUserId,
    required Map<String, dynamic> payload,
    required int aggregateVersion,
  }) {
    return enqueue(
      type: SyncEventType.tripCompleted,
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

  // Receiver / tracking

  static Future<SyncEvent> enqueueTrackingCodeGenerated({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.trackingCodeGenerated,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueReceiverNotificationsEnabled({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.receiverNotificationsEnabled,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueReceiverNotificationQueued({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.receiverNotificationQueued,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueReceiverNotificationSent({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.receiverNotificationSent,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  static Future<SyncEvent> enqueueReceiverNotificationFailed({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.receiverNotificationFailed,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
      aggregateVersion: 1,
    );
  }

  // Misc

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

  // ── Read helpers ───────────────────────────────────────────────────────────

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

  // ── State mutators ─────────────────────────────────────────────────────────

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

  // ── applyEvent ─────────────────────────────────────────────────────────────

  static Future<void> applyEvent(SyncEvent event) async {
    if (event.appliedLocally) return;

    switch (event.type) {
      case SyncEventType.propertyCreated:
        await PropertyService.applyPropertyCreatedFromSync(event);
        break;

      case SyncEventType.paymentRecorded:
      case SyncEventType.paymentVoided:
      case SyncEventType.paymentAdjusted:
        await PaymentService.applyPaymentRecordedFromSync(event);
        break;

      case SyncEventType.tripStarted:
        await TripService.applyTripStartedFromSync(event);
        break;

      case SyncEventType.tripCheckpointReached:
      case SyncEventType.checkpointReached: // legacy alias — same handler
        await TripService.applyTripCheckpointReachedFromSync(event);
        break;

      case SyncEventType.tripCompleted:
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

      // Observational / audit-only events — recorded for the remote event
      // store but require no local Hive state mutation on other devices.
      case SyncEventType.exceptionLogged:
      case SyncEventType.adminOverrideApplied:
      case SyncEventType.propertyCommitted:
      case SyncEventType.propertyLoaded:
      case SyncEventType.propertyStatusManuallyChanged:
      case SyncEventType.receiptPrinted:
      case SyncEventType.pickupOtpGenerated:
      case SyncEventType.pickupOtpReset:
      case SyncEventType.pickupConfirmed:
      case SyncEventType.pickupAttemptFailed:
      case SyncEventType.pickupLockedOut:
      case SyncEventType.qrNonceRotated:
      case SyncEventType.propertyItemCreated:
      case SyncEventType.propertyItemDeferred:
      case SyncEventType.tripCreated:
      case SyncEventType.tripUpdated:
      case SyncEventType.trackingCodeGenerated:
      case SyncEventType.receiverNotificationsEnabled:
      case SyncEventType.receiverNotificationQueued:
      case SyncEventType.receiverNotificationSent:
      case SyncEventType.receiverNotificationFailed:
      case SyncEventType.userCreated:
      case SyncEventType.userUpdated:
        await AuthService.applyUserSyncEvent(event.payload);
        break;

      case SyncEventType.senderNotifyRequested:
      case SyncEventType.partialLoadNotifyRequested:
      case SyncEventType.passwordResetOtpRequested:
      case SyncEventType.pickupOtpVerified: // legacy
      case SyncEventType.receiverNotifyRequested: // legacy
        break;
    }

    await markAppliedLocally(event.eventId);
  }

  // ── Phase 4: pruning ───────────────────────────────────────────────────────

  /// Deletes stale local data to prevent Hive boxes growing indefinitely.
  /// Called weekly from AutoSyncService.
  static Future<PruneResult> pruneStaleData() async {
    int syncEventsDeleted = 0;
    int auditEventsDeleted = 0;
    int outboundMessagesDeleted = 0;

    final now = DateTime.now();

    // SyncEvents
    final syncBox = HiveService.syncEventBox();
    final syncKeysToDelete = <dynamic>[];

    for (final event in syncBox.values) {
      final age = now.difference(event.createdAt);
      final isComplete =
          !event.pendingPush && event.pushed && event.appliedLocally;
      if (isComplete && age.inDays >= 7) {
        syncKeysToDelete.add(event.key);
        continue;
      }
      final isFailed = event.pushAttempts > 0 && !event.pushed;
      if (isFailed && age.inDays >= 30) {
        syncKeysToDelete.add(event.key);
      }
    }

    for (final key in syncKeysToDelete) {
      await syncBox.delete(key);
      syncEventsDeleted++;
    }

    // AuditEvents
    final auditBox = HiveService.auditBox();
    final auditKeysToDelete = <dynamic>[];

    for (final entry in auditBox.values) {
      if (now.difference(entry.at).inDays >= 30) {
        auditKeysToDelete.add(entry.key);
      }
    }

    for (final key in auditKeysToDelete) {
      await auditBox.delete(key);
      auditEventsDeleted++;
    }

    // OutboundMessages
    final msgBox = HiveService.outboundMessageBox();
    final msgKeysToDelete = <dynamic>[];

    for (final msg in msgBox.values) {
      final age = now.difference(msg.createdAt);
      final status = msg.status.trim().toLowerCase();
      if (status == 'sent' && age.inDays >= 3) {
        msgKeysToDelete.add(msg.key);
        continue;
      }
      if (status == 'failed' && age.inDays >= 7) {
        msgKeysToDelete.add(msg.key);
      }
    }

    for (final key in msgKeysToDelete) {
      await msgBox.delete(key);
      outboundMessagesDeleted++;
    }

    return PruneResult(
      syncEventsDeleted: syncEventsDeleted,
      auditEventsDeleted: auditEventsDeleted,
      outboundMessagesDeleted: outboundMessagesDeleted,
    );
  }

  // ── Push ───────────────────────────────────────────────────────────────────

  static Future<int> pushPendingEvents() async {
    final pending = pendingPushEvents();
    if (pending.isEmpty) return 0;

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

    final response = await http.post(uri, headers: _headers(), body: body);

    if (response.statusCode == 401) {
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
      await markPushed(rawId.toString());
      pushedCount++;
    }

    return pushedCount;
  }

  // ── Pull ───────────────────────────────────────────────────────────────────

  static Future<Map<String, int>> pullRemoteEvents() async {
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
      pulled++;
      try {
        final event = SyncEvent.fromJson(Map<String, dynamic>.from(raw as Map));

        if (await isThisDeviceEvent(event)) {
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
            applied++;
          }
          continue;
        }

        await HiveService.syncEventBox().put(event.eventId, event);
        await applyEvent(event);
        applied++;
      } catch (_) {
        failed++;
      }
    }

    final nextCursor = decoded['nextCursor']?.toString();
    if (nextCursor != null && nextCursor.isNotEmpty) {
      await setLastCursor(nextCursor);
    }

    return {'pulled': pulled, 'applied': applied, 'failed': failed};
  }

  // ── syncNow (Phase 5: connectivity + backoff guards) ──────────────────────

  static Future<SyncRunResult> syncNow() async {
    if (_isInBackoff()) {
      return SyncRunResult(pushed: 0, pulled: 0, applied: 0, failed: 0);
    }

    if (!await _isOnline()) {
      return SyncRunResult(pushed: 0, pulled: 0, applied: 0, failed: 0);
    }

    int pushed = 0;
    int pulled = 0;
    int applied = 0;
    int failed = 0;

    try {
      pushed = await pushPendingEvents();
      final pull = await pullRemoteEvents();
      pulled = pull['pulled'] ?? 0;
      applied = pull['applied'] ?? 0;
      failed = pull['failed'] ?? 0;
      _recordSuccess();
    } catch (_) {
      _recordFailure();
      rethrow;
    }

    return SyncRunResult(
      pushed: pushed,
      pulled: pulled,
      applied: applied,
      failed: failed,
    );
  }
}

// ── PruneResult ────────────────────────────────────────────────────────────────

class PruneResult {
  final int syncEventsDeleted;
  final int auditEventsDeleted;
  final int outboundMessagesDeleted;

  const PruneResult({
    required this.syncEventsDeleted,
    required this.auditEventsDeleted,
    required this.outboundMessagesDeleted,
  });

  int get totalDeleted =>
      syncEventsDeleted + auditEventsDeleted + outboundMessagesDeleted;

  @override
  String toString() =>
      'PruneResult(syncEvents: $syncEventsDeleted, '
      'auditEvents: $auditEventsDeleted, '
      'outboundMessages: $outboundMessagesDeleted)';
}
