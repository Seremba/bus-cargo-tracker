import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import '../models/sync_run_result.dart';
import 'hive_service.dart';
import 'payment_service.dart';
import 'property_service.dart';
import 'trip_service.dart';

class SyncService {
  static const String _baseUrl = 'https://bus-cargo-sync.pserembae.workers.dev';
  static const String _eventsBatchPath = '/events/batch';
  static const String _eventsPullPath = '/events';
  static final _uuid = const Uuid();

  static String newEventId() => _uuid.v4();

  static Map<String, dynamic> _jsonSafePayload(Map<String, dynamic> payload) {
    return Map<String, dynamic>.from(payload);
  }

  static String? getLastCursor() {
    final box = HiveService.appSettingsBox();
    return box.get('lastSyncCursor') as String?;
  }

  static Future<void> setLastCursor(String cursor) async {
    final box = HiveService.appSettingsBox();
    await box.put('lastSyncCursor', cursor);
  }

  static String? getDeviceId() {
    final box = HiveService.appSettingsBox();
    return box.get('deviceId') as String?;
  }

  static Future<String> ensureDeviceId() async {
    final box = HiveService.appSettingsBox();

    final existing = (box.get('deviceId') as String?)?.trim();
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

    await box.put('deviceId', deviceId);
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

  static Future<void> applyEvent(SyncEvent event) async {
    if (event.appliedLocally) return;

    switch (event.type) {
      case SyncEventType.propertyCreated:
        await PropertyService.applyPropertyCreatedFromSync(event);
        break;

      case SyncEventType.paymentRecorded:
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

    final uri = Uri.parse('$_baseUrl$_eventsBatchPath');

    final body = jsonEncode({
      'events': pending.map((e) => e.toJson()).toList(),
    });

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: body,
    );

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
    final after = getLastCursor();

    final uri = Uri.parse(
      after == null || after.isEmpty
          ? '$_baseUrl$_eventsPullPath'
          : '$_baseUrl$_eventsPullPath?after=$after',
    );

    final response = await http.get(
      uri,
      headers: {'Content-Type': 'application/json'},
    );

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
