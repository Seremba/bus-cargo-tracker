import 'package:uuid/uuid.dart';

import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import 'hive_service.dart';

class SyncService {
  static final _uuid = const Uuid();

  static String newEventId() => _uuid.v4();

  static Map<String, dynamic> _jsonSafePayload(Map<String, dynamic> payload) {
    return Map<String, dynamic>.from(payload);
  }

  static Future<SyncEvent> enqueue({
    required SyncEventType type,
    required String aggregateType,
    required String aggregateId,
    required String actorUserId,
    required Map<String, dynamic> payload,
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

    final event = SyncEvent(
      eventId: newEventId(),
      type: type,
      aggregateType: cleanAggregateType,
      aggregateId: cleanAggregateId,
      actorUserId: cleanActorUserId,
      payload: _jsonSafePayload(payload),
      createdAt: DateTime.now(),
    );

    await box.put(event.eventId, event);
    return event;
  }

  static Future<SyncEvent> enqueuePropertyCreated({
    required String propertyId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.propertyCreated,
      aggregateType: 'property',
      aggregateId: propertyId,
      actorUserId: actorUserId,
      payload: payload,
    );
  }

  static Future<SyncEvent> enqueuePaymentRecorded({
    required String paymentId,
    required String actorUserId,
    required Map<String, dynamic> payload,
  }) {
    return enqueue(
      type: SyncEventType.paymentRecorded,
      aggregateType: 'payment',
      aggregateId: paymentId,
      actorUserId: actorUserId,
      payload: payload,
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

    return box.values
        .where((e) => e.pendingPush && !e.pushed)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  static Future<void> markPushed(
    String eventId, {
    String? remoteCursor,
  }) async {
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

  static Future<void> markPushFailed(
    String eventId,
    String error,
  ) async {
    final event = getById(eventId);
    if (event == null) return;

    event.pendingPush = true;
    event.pushed = false;
    event.pushAttempts += 1;
    event.lastPushAttemptAt = DateTime.now();
    event.lastError = error.trim();

    await event.save();
  }

  static Future<void> resetForRetry(String eventId) async {
    final event = getById(eventId);
    if (event == null) return;

    event.pendingPush = true;
    event.pushed = false;
    event.lastError = '';

    await event.save();
  }

  static Future<void> markAppliedLocally(String eventId) async {
    final event = getById(eventId);
    if (event == null) return;

    event.appliedLocally = true;
    await event.save();
  }
}