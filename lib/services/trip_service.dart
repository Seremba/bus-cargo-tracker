import 'dart:async';

import 'package:hive/hive.dart';

import '../models/checkpoint.dart';
import '../models/sync_event.dart';
import '../models/trip.dart';
import '../models/trip_status.dart';
import '../models/user_role.dart';
import '../services/hive_service.dart';
import '../services/session.dart';
import 'geo_service.dart';
import 'notification_service.dart';
import 'role_guard.dart';
import 'sync_service.dart';

class TripService {
  static Box<Trip> tripBox() => HiveService.tripBox();

  static Completer<void>? _checkpointLock;

  static const double _maxAccuracyMeters = 60;
  static const Duration _enterDwell = Duration(seconds: 25);
  static const double _exitPaddingMeters = 200;
  static const int _minSecondsBetweenSamples = 2;

  static bool _canTrackTrips() =>
      RoleGuard.hasAny({UserRole.driver, UserRole.admin});

  static Future<T> _runWithCheckpointLock<T>(
    Future<T> Function() action,
  ) async {
    while (_checkpointLock != null) {
      await _checkpointLock!.future;
    }
    _checkpointLock = Completer<void>();
    try {
      return await action();
    } finally {
      _checkpointLock?.complete();
      _checkpointLock = null;
    }
  }

  static String _newTripId() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<Trip> ensureActiveTrip({
    required String routeId,
    required String routeName,
    required List<Checkpoint> checkpoints,
  }) async {
    if (!_canTrackTrips()) {
      throw StateError('Not authorized to create/ensure trips');
    }

    final driverId = Session.currentUserId;
    if (driverId == null || driverId.trim().isEmpty) {
      throw StateError('No active session userId (cannot start trip)');
    }

    final box = tripBox();

    final existing = box.values.where(
      (t) =>
          t.driverUserId == driverId &&
          t.status == TripStatus.active &&
          t.routeId == routeId,
    );

    if (existing.isNotEmpty) return existing.first;

    final otherActive = box.values.where(
      (t) => t.driverUserId == driverId && t.status == TripStatus.active,
    );

    if (otherActive.isNotEmpty) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Driver already has active trip',
        message:
            'Driver $driverId tried to start "$routeName" while another trip is active '
            '(${otherActive.first.routeName}).\nBlocked to avoid mixing routes.',
      );
      return otherActive.first;
    }

    final trip = Trip(
      tripId: _newTripId(),
      routeId: routeId,
      routeName: routeName,
      driverUserId: driverId,
      startedAt: DateTime.now(),
      status: TripStatus.active,
      checkpoints: checkpoints,
      lastCheckpointIndex: -1,
      aggregateVersion: 1,
    );

    await box.add(trip);

    await SyncService.enqueueTripStarted(
      tripId: trip.tripId,
      actorUserId: driverId,
      aggregateVersion: trip.aggregateVersion,
      payload: {
        'tripId': trip.tripId,
        'routeId': trip.routeId,
        'routeName': trip.routeName,
        'driverUserId': trip.driverUserId,
        'startedAt': trip.startedAt.toIso8601String(),
        'status': trip.status.name,
        'lastCheckpointIndex': trip.lastCheckpointIndex,
        'aggregateVersion': trip.aggregateVersion,
        'checkpoints': trip.checkpoints
            .map(
              (cp) => {
                'name': cp.name,
                'lat': cp.lat,
                'lng': cp.lng,
                'radiusMeters': cp.radiusMeters,
                'reachedAt': cp.reachedAt?.toIso8601String(),
              },
            )
            .toList(),
      },
    );

    return trip;
  }

  static Future<void> applyTripStartedFromSync(SyncEvent event) async {
    final payload = event.payload;
    final box = tripBox();

    final tripId = (payload['tripId'] ?? '').toString().trim();
    if (tripId.isEmpty) {
      throw StateError('tripStarted sync event missing tripId');
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    for (final t in box.values) {
      if (t.tripId.trim() == tripId && t.aggregateVersion >= incomingVersion) {
        return;
      }
    }

    final rawCheckpoints = (payload['checkpoints'] as List?) ?? const [];
    final checkpoints = <Checkpoint>[];

    for (final raw in rawCheckpoints) {
      final map = Map<String, dynamic>.from(raw as Map);
      checkpoints.add(
        Checkpoint(
          name: (map['name'] ?? '').toString(),
          lat: (map['lat'] as num).toDouble(),
          lng: (map['lng'] as num).toDouble(),
          radiusMeters: (map['radiusMeters'] as num?)?.toDouble() ?? 500,
          reachedAt: (map['reachedAt'] == null ||
                  (map['reachedAt'] as String).trim().isEmpty)
              ? null
              : DateTime.parse(map['reachedAt'] as String),
        ),
      );
    }

    final trip = Trip(
      tripId: tripId,
      routeId: (payload['routeId'] ?? '').toString(),
      routeName: (payload['routeName'] ?? '').toString(),
      driverUserId: (payload['driverUserId'] ?? '').toString(),
      startedAt: DateTime.parse((payload['startedAt'] ?? '').toString()),
      status: TripStatus.values.byName(
        (payload['status'] ?? 'active').toString(),
      ),
      checkpoints: checkpoints,
      lastCheckpointIndex:
          (payload['lastCheckpointIndex'] as num?)?.toInt() ?? -1,
      aggregateVersion: incomingVersion,
    );

    await box.add(trip);
  }

  static Future<void> applyTripCheckpointReachedFromSync(
    SyncEvent event,
  ) async {
    final payload = event.payload;
    final tripId = (payload['tripId'] ?? '').toString().trim();
    if (tripId.isEmpty) {
      throw StateError('tripCheckpointReached event missing tripId');
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    final box = tripBox();
    Trip? trip;

    for (final t in box.values) {
      if (t.tripId.trim() == tripId) {
        trip = t;
        break;
      }
    }

    if (trip == null) {
      throw StateError('Trip $tripId not found for checkpoint replay');
    }

    if (trip.aggregateVersion >= incomingVersion) {
      return;
    }

    final checkpointIndex = (payload['checkpointIndex'] as num).toInt();
    final reachedAt = DateTime.parse((payload['reachedAt'] ?? '').toString());

    if (checkpointIndex < 0 || checkpointIndex >= trip.checkpoints.length) {
      throw StateError('Invalid checkpointIndex for trip $tripId');
    }

    trip.checkpoints[checkpointIndex].reachedAt = reachedAt;
    trip.lastCheckpointIndex = checkpointIndex;
    trip.aggregateVersion = incomingVersion;

    await trip.save();
  }

  static Future<void> applyTripEndedFromSync(SyncEvent event) async {
    final payload = event.payload;
    final tripId = (payload['tripId'] ?? '').toString().trim();
    if (tripId.isEmpty) {
      throw StateError('tripEnded event missing tripId');
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    final box = tripBox();
    Trip? trip;

    for (final t in box.values) {
      if (t.tripId.trim() == tripId) {
        trip = t;
        break;
      }
    }

    if (trip == null) {
      throw StateError('Trip $tripId not found for tripEnded replay');
    }

    if (trip.aggregateVersion >= incomingVersion) {
      return;
    }

    trip.status = TripStatus.ended;
    trip.endedAt = DateTime.parse((payload['endedAt'] ?? '').toString());
    trip.aggregateVersion = incomingVersion;

    await trip.save();
  }

  static Future<void> applyTripCancelledFromSync(SyncEvent event) async {
    final payload = event.payload;
    final tripId = (payload['tripId'] ?? '').toString().trim();
    if (tripId.isEmpty) {
      throw StateError('tripCancelled event missing tripId');
    }

    final incomingVersion =
        (payload['aggregateVersion'] as num?)?.toInt() ??
        event.aggregateVersion;

    final box = tripBox();
    Trip? trip;

    for (final t in box.values) {
      if (t.tripId.trim() == tripId) {
        trip = t;
        break;
      }
    }

    if (trip == null) {
      throw StateError('Trip $tripId not found for tripCancelled replay');
    }

    if (trip.aggregateVersion >= incomingVersion) {
      return;
    }

    trip.status = TripStatus.cancelled;
    trip.endedAt = DateTime.parse((payload['endedAt'] ?? '').toString());
    trip.aggregateVersion = incomingVersion;

    await trip.save();
  }

  static Trip? getActiveTripForCurrentDriver({String? routeId}) {
    final driverId = Session.currentUserId;
    if (driverId == null) return null;

    final box = tripBox();
    try {
      return box.values.firstWhere((t) {
        final matchesDriver =
            t.driverUserId == driverId && t.status == TripStatus.active;
        if (!matchesDriver) return false;
        if (routeId == null || routeId.trim().isEmpty) return true;
        return t.routeId == routeId;
      });
    } catch (_) {
      return null;
    }
  }

  static Future<bool> updateCheckpointFromLocation({
    required double lat,
    required double lng,
    double? accuracyMeters,
  }) async {
    if (!_canTrackTrips()) return false;

    if (accuracyMeters != null &&
        (accuracyMeters.isNaN || accuracyMeters > _maxAccuracyMeters)) {
      return false;
    }

    return _runWithCheckpointLock(() async {
      final driverId = Session.currentUserId;
      if (driverId == null || driverId.trim().isEmpty) return false;

      final box = tripBox();
      final activeTrips = box.values.where(
        (t) => t.driverUserId == driverId && t.status == TripStatus.active,
      );

      if (activeTrips.isEmpty) return false;

      final trips = activeTrips.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

      final currentTrip = trips.first;

      if (currentTrip.lastGpsAt != null) {
        final dt = DateTime.now().difference(currentTrip.lastGpsAt!).inSeconds;
        if (dt >= 0 && dt < _minSecondsBetweenSamples) {
          return false;
        }
      }

      if (!_acceptSample(currentTrip, lat: lat, lng: lng)) {
        await currentTrip.save();
        return false;
      }

      final nextIndex = currentTrip.lastCheckpointIndex + 1;
      if (nextIndex < 0 || nextIndex >= currentTrip.checkpoints.length) {
        _clearCandidate(currentTrip);
        await currentTrip.save();
        return false;
      }

      final nextCp = currentTrip.checkpoints[nextIndex];
      if (nextCp.reachedAt != null) {
        _clearCandidate(currentTrip);
        await currentTrip.save();
        return false;
      }

      final dist = GeoService.distanceMeters(lat, lng, nextCp.lat, nextCp.lng);
      final acc = (accuracyMeters ?? 0).isNaN ? 0.0 : (accuracyMeters ?? 0);

      final enterRadius = nextCp.radiusMeters + acc;
      final exitRadius = nextCp.radiusMeters + _exitPaddingMeters + acc;

      final insideNow = dist <= enterRadius;
      final outsideNow = dist >= exitRadius;

      final isCandidateForThis =
          currentTrip.candidateCheckpointIndex == nextIndex;

      if (!insideNow) {
        if (outsideNow) {
          _clearCandidate(currentTrip);
        } else {
          _clearCandidate(currentTrip);
        }
        await currentTrip.save();
        return false;
      }

      if (!isCandidateForThis) {
        currentTrip.candidateCheckpointIndex = nextIndex;
        currentTrip.candidateSince = DateTime.now();
        await currentTrip.save();
        return false;
      }

      final since = currentTrip.candidateSince;
      if (since == null) {
        currentTrip.candidateSince = DateTime.now();
        await currentTrip.save();
        return false;
      }

      if (DateTime.now().difference(since) < _enterDwell) {
        await currentTrip.save();
        return false;
      }

      nextCp.reachedAt = DateTime.now();
      currentTrip.lastCheckpointIndex = nextIndex;
      currentTrip.aggregateVersion += 1;
      _clearCandidate(currentTrip);

      await currentTrip.save();

      await SyncService.enqueueTripCheckpointReached(
        tripId: currentTrip.tripId,
        actorUserId: currentTrip.driverUserId,
        aggregateVersion: currentTrip.aggregateVersion,
        payload: {
          'tripId': currentTrip.tripId,
          'checkpointIndex': nextIndex,
          'checkpointName': nextCp.name,
          'reachedAt': nextCp.reachedAt!.toIso8601String(),
          'aggregateVersion': currentTrip.aggregateVersion,
        },
      );

      await _notifyCheckpointReached(trip: currentTrip, checkpoint: nextCp);

      final isFinalCheckpoint =
          nextIndex == (currentTrip.checkpoints.length - 1);

      if (isFinalCheckpoint && currentTrip.status == TripStatus.active) {
        await _autoEndTrip(currentTrip);
      }

      return true;
    });
  }

  static void _clearCandidate(Trip trip) {
    trip.candidateCheckpointIndex = null;
    trip.candidateSince = null;
  }

  static bool _acceptSample(
    Trip trip, {
    required double lat,
    required double lng,
  }) {
    final prevLat = trip.lastGpsLat;
    final prevLng = trip.lastGpsLng;
    final prevAt = trip.lastGpsAt;
    final now = DateTime.now();

    trip.lastGpsLat = lat;
    trip.lastGpsLng = lng;
    trip.lastGpsAt = now;

    if (prevLat == null || prevLng == null || prevAt == null) return true;

    final dt = now.difference(prevAt).inSeconds;
    if (dt <= 0) return true;

    final d = GeoService.distanceMeters(prevLat, prevLng, lat, lng);
    if (dt < 5 && d > 1000) {
      return false;
    }

    return true;
  }

  static Future<void> _notifyCheckpointReached({
    required Trip trip,
    required Checkpoint checkpoint,
  }) async {
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip checkpoint reached',
      message:
          '${trip.routeName}: Reached ${checkpoint.name} at '
          '${checkpoint.reachedAt!.toLocal().toString().substring(0, 16)} '
          '(Driver: ${trip.driverUserId}).',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);

    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Bus reached ${checkpoint.name}',
        message:
            'Your cargo is progressing on ${trip.routeName}.\n'
            'Latest checkpoint: ${checkpoint.name}.',
      );
    }
  }

  static Future<void> _autoEndTrip(Trip trip) async {
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.ended;
    trip.endedAt ??= DateTime.now();
    trip.aggregateVersion += 1;
    await trip.save();

    await SyncService.enqueueTripEnded(
      tripId: trip.tripId,
      actorUserId: trip.driverUserId,
      aggregateVersion: trip.aggregateVersion,
      payload: {
        'tripId': trip.tripId,
        'endedAt': trip.endedAt!.toIso8601String(),
        'status': trip.status.name,
        'aggregateVersion': trip.aggregateVersion,
      },
    );

    await _notifyTripEnded(trip);
  }

  static Future<void> endTrip(Trip trip) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.ended;
    trip.endedAt ??= DateTime.now();
    trip.aggregateVersion += 1;
    await trip.save();

    await SyncService.enqueueTripEnded(
      tripId: trip.tripId,
      actorUserId: trip.driverUserId,
      aggregateVersion: trip.aggregateVersion,
      payload: {
        'tripId': trip.tripId,
        'endedAt': trip.endedAt!.toIso8601String(),
        'status': trip.status.name,
        'aggregateVersion': trip.aggregateVersion,
      },
    );

    await _notifyTripEnded(trip);
  }

  static Future<void> _notifyTripEnded(Trip trip) async {
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip ended',
      message:
          '${trip.routeName} ended at '
          '${trip.endedAt!.toLocal().toString().substring(0, 16)} '
          '(Driver: ${trip.driverUserId}).',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);

    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Trip ended',
        message:
            'Trip ${trip.routeName} has ended.\n'
            'Your cargo should be arriving at the destination station.',
      );
    }
  }

  static Future<void> cancelTrip(Trip trip, {String? reason}) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.cancelled;
    trip.endedAt ??= DateTime.now();
    trip.aggregateVersion += 1;
    await trip.save();

    await SyncService.enqueueTripCancelled(
      tripId: trip.tripId,
      actorUserId: (Session.currentUserId ?? '').trim().isEmpty
          ? 'system'
          : (Session.currentUserId ?? '').trim(),
      aggregateVersion: trip.aggregateVersion,
      payload: {
        'tripId': trip.tripId,
        'endedAt': trip.endedAt!.toIso8601String(),
        'status': trip.status.name,
        'reason': reason?.trim() ?? '',
        'aggregateVersion': trip.aggregateVersion,
      },
    );

    final when = trip.endedAt!.toLocal().toString().substring(0, 16);
    final why = (reason != null && reason.trim().isNotEmpty)
        ? ' Reason: ${reason.trim()}.'
        : '';

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip cancelled',
      message:
          '${trip.routeName} was cancelled at $when '
          '(Driver: ${trip.driverUserId}).$why',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);

    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Trip cancelled',
        message:
            'Trip ${trip.routeName} was cancelled.$why '
            'Please contact support or wait for an update.',
      );
    }
  }
}