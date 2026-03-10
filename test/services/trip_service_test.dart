import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/models/checkpoint.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/models/trip.dart';
import 'package:bus_cargo_tracker/models/trip_status.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/trip_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_trip_service_test_',
    );

    Hive.init(tempDir.path);

    if (!Hive.isAdapterRegistered(2)) {
      Hive.registerAdapter(CheckpointAdapter());
    }
    if (!Hive.isAdapterRegistered(6)) {
      Hive.registerAdapter(TripStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(7)) {
      Hive.registerAdapter(TripAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(SyncEventAdapter());
    }

    await HiveService.openTripBox();
    await HiveService.openSyncEventBox();

    Session.currentUserId = 'driver-1';
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
  });

  tearDown(() async {
    Session.currentUserId = null;
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;

    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Trip _makeTrip({
    required String tripId,
    int aggregateVersion = 1,
    int lastCheckpointIndex = -1,
    TripStatus status = TripStatus.active,
    DateTime? endedAt,
  }) {
    return Trip(
      tripId: tripId,
      routeId: 'route-1',
      routeName: 'Kampala → Juba',
      driverUserId: 'driver-1',
      startedAt: DateTime.parse('2026-03-10T08:00:00Z'),
      endedAt: endedAt,
      status: status,
      checkpoints: [
        Checkpoint(
          name: 'Checkpoint A',
          lat: 0.3136,
          lng: 32.5811,
          radiusMeters: 300,
        ),
        Checkpoint(
          name: 'Checkpoint B',
          lat: 0.4000,
          lng: 32.7000,
          radiusMeters: 300,
        ),
        Checkpoint(
          name: 'Checkpoint C',
          lat: 0.5000,
          lng: 32.8000,
          radiusMeters: 300,
        ),
      ],
      lastCheckpointIndex: lastCheckpointIndex,
      aggregateVersion: aggregateVersion,
    );
  }

  SyncEvent _makeCheckpointEvent({
    required String tripId,
    required int checkpointIndex,
    required int aggregateVersion,
    String reachedAt = '2026-03-10T10:00:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-checkpoint-$tripId-$checkpointIndex-$aggregateVersion',
      type: SyncEventType.tripCheckpointReached,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: 'driver-remote',
      payload: {
        'tripId': tripId,
        'checkpointIndex': checkpointIndex,
        'checkpointName': 'Checkpoint $checkpointIndex',
        'reachedAt': reachedAt,
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T10:00:01Z'),
      aggregateVersion: aggregateVersion,
      pendingPush: false,
      pushed: true,
      appliedLocally: false,
    );
  }

  SyncEvent _makeEndedEvent({
    required String tripId,
    required int aggregateVersion,
    String endedAt = '2026-03-10T11:30:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-ended-$tripId-$aggregateVersion',
      type: SyncEventType.tripEnded,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: 'driver-remote',
      payload: {
        'tripId': tripId,
        'endedAt': endedAt,
        'status': 'ended',
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T11:31:00Z'),
      aggregateVersion: aggregateVersion,
      pendingPush: false,
      pushed: true,
      appliedLocally: false,
    );
  }

  SyncEvent _makeCancelledEvent({
    required String tripId,
    required int aggregateVersion,
    String endedAt = '2026-03-10T11:45:00Z',
  }) {
    return SyncEvent(
      eventId: 'evt-cancelled-$tripId-$aggregateVersion',
      type: SyncEventType.tripCancelled,
      aggregateType: 'trip',
      aggregateId: tripId,
      actorUserId: 'admin-remote',
      payload: {
        'tripId': tripId,
        'endedAt': endedAt,
        'status': 'cancelled',
        'aggregateVersion': aggregateVersion,
      },
      createdAt: DateTime.parse('2026-03-10T11:46:00Z'),
      aggregateVersion: aggregateVersion,
      pendingPush: false,
      pushed: true,
      appliedLocally: false,
    );
  }

  Future<void> _saveTrip(Trip trip) async {
    await HiveService.tripBox().add(trip);
  }

  Trip _getTrip(String tripId) {
    return HiveService.tripBox().values.firstWhere(
      (t) => t.tripId == tripId,
    ) as Trip;
  }

  group('TripService sync replay', () {
    test('applies checkpoint replay once', () async {
      final trip = _makeTrip(tripId: 'trip-1', aggregateVersion: 1);
      await _saveTrip(trip);

      final event = _makeCheckpointEvent(
        tripId: 'trip-1',
        checkpointIndex: 0,
        aggregateVersion: 2,
      );

      await TripService.applyTripCheckpointReachedFromSync(event);

      final updated = _getTrip('trip-1');
      expect(updated.lastCheckpointIndex, 0);
      expect(updated.aggregateVersion, 2);
      expect(updated.checkpoints[0].reachedAt, isNotNull);

      await TripService.applyTripCheckpointReachedFromSync(event);

      final replayedAgain = _getTrip('trip-1');
      expect(replayedAgain.lastCheckpointIndex, 0);
      expect(replayedAgain.aggregateVersion, 2);
    });

    test('ignores stale checkpoint replay by aggregate version', () async {
      final trip = _makeTrip(
        tripId: 'trip-2',
        aggregateVersion: 5,
        lastCheckpointIndex: 1,
      );
      await _saveTrip(trip);

      final staleEvent = _makeCheckpointEvent(
        tripId: 'trip-2',
        checkpointIndex: 2,
        aggregateVersion: 4,
      );

      await TripService.applyTripCheckpointReachedFromSync(staleEvent);

      final updated = _getTrip('trip-2');
      expect(updated.aggregateVersion, 5);
      expect(updated.lastCheckpointIndex, 1);
      expect(updated.checkpoints[2].reachedAt, isNull);
    });

    test('ignores backward checkpoint replay even if version is newer', () async {
      final trip = _makeTrip(
        tripId: 'trip-3',
        aggregateVersion: 2,
        lastCheckpointIndex: 2,
      );
      await _saveTrip(trip);

      final backwardEvent = _makeCheckpointEvent(
        tripId: 'trip-3',
        checkpointIndex: 1,
        aggregateVersion: 6,
      );

      await TripService.applyTripCheckpointReachedFromSync(backwardEvent);

      final updated = _getTrip('trip-3');
      expect(updated.aggregateVersion, 2);
      expect(updated.lastCheckpointIndex, 2);
    });

    test('ignores same checkpoint replay even if version is newer', () async {
      final trip = _makeTrip(
        tripId: 'trip-4',
        aggregateVersion: 2,
        lastCheckpointIndex: 1,
      );
      await _saveTrip(trip);

      final duplicateIndexEvent = _makeCheckpointEvent(
        tripId: 'trip-4',
        checkpointIndex: 1,
        aggregateVersion: 3,
      );

      await TripService.applyTripCheckpointReachedFromSync(
        duplicateIndexEvent,
      );

      final updated = _getTrip('trip-4');
      expect(updated.aggregateVersion, 2);
      expect(updated.lastCheckpointIndex, 1);
    });

    test('ignores checkpoint replay for missing trip', () async {
      final event = _makeCheckpointEvent(
        tripId: 'missing-trip',
        checkpointIndex: 0,
        aggregateVersion: 2,
      );

      await TripService.applyTripCheckpointReachedFromSync(event);

      expect(HiveService.tripBox().values, isEmpty);
    });

    test('ignores malformed checkpoint replay', () async {
      final trip = _makeTrip(tripId: 'trip-5', aggregateVersion: 1);
      await _saveTrip(trip);

      final malformed = SyncEvent(
        eventId: 'evt-bad',
        type: SyncEventType.tripCheckpointReached,
        aggregateType: 'trip',
        aggregateId: 'trip-5',
        actorUserId: 'driver-remote',
        payload: {
          'tripId': 'trip-5',
          'checkpointIndex': 0,
          'reachedAt': 'not-a-date',
          'aggregateVersion': 2,
        },
        createdAt: DateTime.parse('2026-03-10T10:00:01Z'),
        aggregateVersion: 2,
        pendingPush: false,
        pushed: true,
        appliedLocally: false,
      );

      await TripService.applyTripCheckpointReachedFromSync(malformed);

      final updated = _getTrip('trip-5');
      expect(updated.aggregateVersion, 1);
      expect(updated.lastCheckpointIndex, -1);
      expect(updated.checkpoints[0].reachedAt, isNull);
    });

    test('applies trip ended replay safely', () async {
      final trip = _makeTrip(
        tripId: 'trip-6',
        aggregateVersion: 2,
        status: TripStatus.active,
      );
      await _saveTrip(trip);

      final event = _makeEndedEvent(
        tripId: 'trip-6',
        aggregateVersion: 3,
      );

      await TripService.applyTripEndedFromSync(event);

      final updated = _getTrip('trip-6');
      expect(updated.status, TripStatus.ended);
      expect(updated.endedAt, isNotNull);
      expect(updated.aggregateVersion, 3);
    });

    test('applies trip cancelled replay as cancelled', () async {
      final trip = _makeTrip(
        tripId: 'trip-7',
        aggregateVersion: 2,
        status: TripStatus.active,
      );
      await _saveTrip(trip);

      final event = _makeCancelledEvent(
        tripId: 'trip-7',
        aggregateVersion: 3,
      );

      await TripService.applyTripCancelledFromSync(event);

      final updated = _getTrip('trip-7');
      expect(updated.status, TripStatus.cancelled);
      expect(updated.endedAt, isNotNull);
      expect(updated.aggregateVersion, 3);
    });
  });
}