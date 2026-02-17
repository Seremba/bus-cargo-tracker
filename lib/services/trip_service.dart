import 'dart:async';
import 'dart:math';
import 'package:hive/hive.dart';

import '../models/trip.dart';
import '../models/trip_status.dart';
import '../models/checkpoint.dart';
import '../services/session.dart';
import '../services/hive_service.dart';
import 'notification_service.dart';
import 'role_guard.dart';
import '../models/user_role.dart';

class TripService {
  static Box<Trip> tripBox() => HiveService.tripBox();
  static Completer<void>? _checkpointLock;

  static bool _canTrackTrips() =>
      RoleGuard.hasAny({UserRole.driver, UserRole.admin});

  static Future<T> _runWithCheckpointLock<T>(Future<T> Function() action) async {
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

  /// ✅ Returns the active trip for THIS driver + THIS route, or creates one if none exists.
  static Future<Trip> ensureActiveTrip({
    required String routeId,
    required String routeName,
    required List<Checkpoint> checkpoints,
  }) async {
    if (!_canTrackTrips()) {
      throw StateError('Not authorized to create/ensure trips');
    }

    final driverId = Session.currentUserId!;
    final box = tripBox();

    final existing = box.values.where((t) =>
        t.driverUserId == driverId &&
        t.status == TripStatus.active &&
        t.routeId == routeId);

    if (existing.isNotEmpty) return existing.first;

    // Safety: prevent >1 active trip per driver
    final otherActive = box.values.where(
      (t) => t.driverUserId == driverId && t.status == TripStatus.active,
    );

    if (otherActive.isNotEmpty) {
      await NotificationService.notify(
        targetUserId: NotificationService.adminInbox,
        title: 'Driver already has active trip',
        message:
            'Driver $driverId tried to start "$routeName" while another trip is active (${otherActive.first.routeName}). Blocked to avoid mixing routes.',
      );

      // ✅ BLOCK by returning existing active trip (do not create a new one)
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
    );

    await box.add(trip);
    return trip;
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
  }) async {
    if (!_canTrackTrips()) return false;

    return _runWithCheckpointLock(() async {
      final driverId = Session.currentUserId!;
      final box = tripBox();

      final activeTrips = box.values.where(
        (t) => t.driverUserId == driverId && t.status == TripStatus.active,
      );

      if (activeTrips.isEmpty) return false;

      final trips = activeTrips.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      final currentTrip = trips.first;

      final nextIndex = currentTrip.lastCheckpointIndex + 1;
      if (nextIndex < 0 || nextIndex >= currentTrip.checkpoints.length) {
        return false;
      }

      final nextCp = currentTrip.checkpoints[nextIndex];
      if (nextCp.reachedAt != null) return false;

      final dist = _distanceMeters(
        lat1: lat,
        lng1: lng,
        lat2: nextCp.lat,
        lng2: nextCp.lng,
      );

      if (dist > nextCp.radiusMeters) return false;

      nextCp.reachedAt ??= DateTime.now();
      currentTrip.lastCheckpointIndex = nextIndex;

      await currentTrip.save();

      await _notifyCheckpointReached(trip: currentTrip, checkpoint: nextCp);

      final isFinalCheckpoint =
          nextIndex == (currentTrip.checkpoints.length - 1);
      if (isFinalCheckpoint && currentTrip.status == TripStatus.active) {
        await _autoEndTrip(currentTrip);
      }

      return true;
    });
  }

  static Future<void> _notifyCheckpointReached({
    required Trip trip,
    required Checkpoint checkpoint,
  }) async {
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip checkpoint reached',
      message:
          '${trip.routeName}: Reached ${checkpoint.name} at ${checkpoint.reachedAt!.toLocal().toString().substring(0, 16)} (Driver: ${trip.driverUserId}).',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);
    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Bus reached ${checkpoint.name}',
        message:
            'Your cargo is progressing on ${trip.routeName}. Latest checkpoint: ${checkpoint.name}.',
      );
    }
  }

  static double _distanceMeters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    const R = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  static Future<void> _autoEndTrip(Trip trip) async {
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.ended;
    trip.endedAt ??= DateTime.now();
    await trip.save();

    await _notifyTripEnded(trip);
  }

  // ✅ Manual end (admin button)
  static Future<void> endTrip(Trip trip) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.ended;
    trip.endedAt ??= DateTime.now();
    await trip.save();

    await _notifyTripEnded(trip);
  }

  static Future<void> _notifyTripEnded(Trip trip) async {
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip ended',
      message:
          '${trip.routeName} ended at ${trip.endedAt!.toLocal().toString().substring(0, 16)} (Driver: ${trip.driverUserId}).',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);
    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Trip ended',
        message:
            'Trip ${trip.routeName} has ended. Your cargo should be arriving at the destination station.',
      );
    }
  }

  // ✅ Manual cancel (admin only)
  static Future<void> cancelTrip(Trip trip, {String? reason}) async {
    if (!RoleGuard.hasRole(UserRole.admin)) return;
    if (trip.status != TripStatus.active) return;

    trip.status = TripStatus.cancelled;
    trip.endedAt ??= DateTime.now();
    await trip.save();

    final when = trip.endedAt!.toLocal().toString().substring(0, 16);
    final why = (reason != null && reason.trim().isNotEmpty)
        ? ' Reason: ${reason.trim()}.'
        : '';

    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Trip cancelled',
      message:
          '${trip.routeName} was cancelled at $when (Driver: ${trip.driverUserId}).$why',
    );

    final pBox = HiveService.propertyBox();
    final cargoOnTrip = pBox.values.where((p) => p.tripId == trip.tripId);
    final senderIds = cargoOnTrip.map((p) => p.createdByUserId).toSet();

    for (final senderId in senderIds) {
      await NotificationService.notify(
        targetUserId: senderId,
        title: 'Trip cancelled',
        message:
            'Trip ${trip.routeName} was cancelled.$why Please contact support or wait for an update.',
      );
    }
  }
}
