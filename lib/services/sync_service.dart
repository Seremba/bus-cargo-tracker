import 'package:uuid/uuid.dart';

import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import 'hive_service.dart';

import 'property_service.dart';
import 'payment_service.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/sync_run_result.dart';

class SyncService {
  static const String _baseUrl = 'https://YOUR-CLOUDFLARE-WORKER-DOMAIN';
  static const String _eventsBatchPath = '/events/batch';
  static const String _eventsPullPath = '/events';
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

  static Future<void> applyEvent(SyncEvent event) async {
    if (event.appliedLocally) return;

    switch (event.type) {
      case SyncEventType.propertyCreated:
        await PropertyService.applyPropertyCreatedFromSync(event);
        break;

      case SyncEventType.paymentRecorded:
        await PaymentService.applyPaymentRecordedFromSync(event);
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

    final acceptedSet = accepted.map((e) => e.toString()).toSet();

    for (final event in pending) {
      if (!acceptedSet.contains(event.eventId)) {
        await markPushFailed(event.eventId, 'Server did not acknowledge event');
      }
    }

    return pushedCount;
  }

  static String? latestRemoteCursor() {
    final box = HiveService.syncEventBox();

    String? latest;
    for (final e in box.values) {
      final c = e.remoteCursor?.trim();
      if (c == null || c.isEmpty) continue;
      latest = c;
    }
    return latest;
  }

  static Future<Map<String, int>> pullRemoteEvents() async {
    final after = latestRemoteCursor();
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
