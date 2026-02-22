import 'dart:async';
import 'package:hive/hive.dart';

import '../models/trip.dart';
import '../models/trip_status.dart';
import '../models/checkpoint.dart';
import '../services/session.dart';
import '../services/hive_service.dart';
import 'notification_service.dart';
import 'role_guard.dart';
import '../models/user_role.dart';
import 'geo_service.dart'; // use shared geo logic

class TripService {
  static Box<Trip> tripBox() => HiveService.tripBox();
  static Completer<void>? _checkpointLock;

  // -----------------------------
  // Detection tuning knobs
  // -----------------------------
  static const double _maxAccuracyMeters = 60; // ignore worse samples
  static const Duration _enterDwell = Duration(seconds: 25); // debounce
  static const double _exitPaddingMeters = 200; // hysteresis buffer
  static const int _minSecondsBetweenSamples = 2; // avoid spam writes

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

  ///  Returns the active trip for THIS driver + THIS route, or creates one if none exists.
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

  /// ✅ Robust checkpoint detection:
  /// - accuracy gate
  /// - debounce (dwell time)
  /// - hysteresis (enter vs exit boundary)
  /// - outlier rejection
  static Future<bool> updateCheckpointFromLocation({
    required double lat,
    required double lng,
    double? accuracyMeters,
  }) async {
    if (!_canTrackTrips()) return false;

    // Accuracy gate (if provided)
    if (accuracyMeters != null &&
        (accuracyMeters.isNaN || accuracyMeters > _maxAccuracyMeters)) {
      return false;
    }

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

      // Throttle very frequent calls (reduces Hive writes + jitter)
      if (currentTrip.lastGpsAt != null) {
        final dt = DateTime.now().difference(currentTrip.lastGpsAt!).inSeconds;
        if (dt >= 0 && dt < _minSecondsBetweenSamples) {
          return false;
        }
      }

      // Outlier rejection + store last GPS
      if (!_acceptSample(currentTrip, lat: lat, lng: lng)) {
        await currentTrip.save(); // save lastGpsAt updates
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

      // Accuracy-aware boundaries
      final enterRadius = nextCp.radiusMeters + acc;
      final exitRadius = nextCp.radiusMeters + _exitPaddingMeters + acc;

      final insideNow = dist <= enterRadius;
      final outsideNow = dist >= exitRadius;

      final isCandidateForThis =
          currentTrip.candidateCheckpointIndex == nextIndex;

      // Not inside: clear candidate to avoid false triggers
      if (!insideNow) {
        // If clearly outside, always clear
        if (outsideNow) {
          _clearCandidate(currentTrip);
        } else {
          // borderline zone: also clear (simpler + safer)
          _clearCandidate(currentTrip);
        }
        await currentTrip.save();
        return false;
      }

      // Inside now: start or continue dwell timer
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
        // Still dwelling inside radius; do not confirm yet.
        await currentTrip.save(); // persist lastGpsAt etc.
        return false;
      }

      // ✅ Confirm reached checkpoint
      nextCp.reachedAt = DateTime.now();
      currentTrip.lastCheckpointIndex = nextIndex;
      _clearCandidate(currentTrip);

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

  static void _clearCandidate(Trip trip) {
    trip.candidateCheckpointIndex = null;
    trip.candidateSince = null;
  }

  /// Reject impossible jumps and persist last sample fields.
  /// Conservative rules: if it jumps >1000m in <5 seconds, ignore it.
  static bool _acceptSample(Trip trip,
      {required double lat, required double lng}) {
    final prevLat = trip.lastGpsLat;
    final prevLng = trip.lastGpsLng;
    final prevAt = trip.lastGpsAt;

    final now = DateTime.now();

    // Update stored fields
    trip.lastGpsLat = lat;
    trip.lastGpsLng = lng;
    trip.lastGpsAt = now;

    if (prevLat == null || prevLng == null || prevAt == null) return true;

    final dt = now.difference(prevAt).inSeconds;
    if (dt <= 0) return true;

    final d = GeoService.distanceMeters(prevLat, prevLng, lat, lng);

    if (dt < 5 && d > 1000) {
      // Likely a bad GPS spike; ignore this sample.
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