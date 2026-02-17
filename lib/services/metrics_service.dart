import 'package:hive/hive.dart';

import '../models/property.dart';
import '../models/property_status.dart';
import '../models/trip.dart';
import '../models/trip_status.dart';
import '../models/audit_event.dart'; 
import 'hive_service.dart';

class DriverMetric {
  final String driverId;
  final int score; 
  final int active;
  final int ended;
  final int cancelled;

  DriverMetric({
    required this.driverId,
    required this.score,
    required this.active,
    required this.ended,
    required this.cancelled,
  });
}

class StationMetric {
  final String station;
  final int deliveredOrPickedUp;
  final int pickedUp;

  StationMetric({
    required this.station,
    required this.deliveredOrPickedUp,
    required this.pickedUp,
  });
}

/// audit-based OTP abuse metric (rank actors: staff/admin)
class OtpAbuseStat {
  final String actorUserId;
  final String actorRole;

  int otpFailed = 0;
  int otpOk = 0;
  int adminUnlocks = 0;
  int adminResets = 0;

  int score = 0;

  OtpAbuseStat({
    required this.actorUserId,
    required this.actorRole,
  });
}

class DeliveryAverages {
  final Duration? avgPendingToTransit;
  final Duration? avgTransitToDelivered;
  final Duration? avgDeliveredToPickup;

  DeliveryAverages({
    required this.avgPendingToTransit,
    required this.avgTransitToDelivered,
    required this.avgDeliveredToPickup,
  });
}

class MetricsService {
  static Box<Property> _pBox() => HiveService.propertyBox();
  static Box<Trip> _tBox() => HiveService.tripBox();
  static Box<AuditEvent> _aBox() => HiveService.auditBox(); // ✅ NEW

  static bool _inRange(DateTime when, DateTime? startInclusive) {
    if (startInclusive == null) return true;
    return !when.isBefore(startInclusive);
  }

  static List<DriverMetric> topDrivers({
    DateTime? startInclusive,
    int limit = 10,
  }) {
    final trips = _tBox().values.where((t) {
      return _inRange(t.startedAt, startInclusive);
    });

    final map = <String, _DriverAgg>{};

    for (final t in trips) {
      final id = t.driverUserId;
      map.putIfAbsent(id, () => _DriverAgg());

      final agg = map[id]!;
      // progress points: lastCheckpointIndex + 1 (min 0)
      final prog = (t.lastCheckpointIndex + 1);
      agg.score += prog < 0 ? 0 : prog;

      if (t.status == TripStatus.active) agg.active++;
      if (t.status == TripStatus.ended) agg.ended++;
      if (t.status == TripStatus.cancelled) agg.cancelled++;
    }

    final out =
        map.entries
            .map(
              (e) => DriverMetric(
                driverId: e.key,
                score: e.value.score,
                active: e.value.active,
                ended: e.value.ended,
                cancelled: e.value.cancelled,
              ),
            )
            .toList()
          ..sort((a, b) {
            final byScore = b.score.compareTo(a.score);
            if (byScore != 0) return byScore;
            return b.ended.compareTo(a.ended);
          });

    return out.take(limit).toList();
  }

  static List<StationMetric> topStations({
    DateTime? startInclusive,
    int limit = 10,
  }) {
    final props = _pBox().values.where((p) {
      // Count if delivered or picked up (i.e. reached station at some point)
      final deliveredAt = p.deliveredAt;
      if (deliveredAt == null) return false;
      return _inRange(deliveredAt, startInclusive);
    });

    final map = <String, _StationAgg>{};

    for (final p in props) {
      final station = p.destination.trim().isEmpty ? '—' : p.destination.trim();
      map.putIfAbsent(station, () => _StationAgg());

      final agg = map[station]!;
      agg.deliveredOrPickedUp++;

      if (p.status == PropertyStatus.pickedUp || p.pickedUpAt != null) {
        agg.pickedUp++;
      }
    }

    final out =
        map.entries
            .map(
              (e) => StationMetric(
                station: e.key,
                deliveredOrPickedUp: e.value.deliveredOrPickedUp,
                pickedUp: e.value.pickedUp,
              ),
            )
            .toList()
          ..sort(
            (a, b) => b.deliveredOrPickedUp.compareTo(a.deliveredOrPickedUp),
          );

    return out.take(limit).toList();
  }

  //  UPDATED: audit-based OTP abuse leaderboard (by actorUserId)
  static List<OtpAbuseStat> otpAbuse({
    DateTime? startInclusive,
    int limit = 15,
  }) {
    final events = _aBox().values.where((e) {
      if (!_inRange(e.at, startInclusive)) return false;

      return e.action == 'staff_confirm_pickup_failed' ||
          e.action == 'staff_confirm_pickup_ok' ||
          e.action == 'admin_unlock_otp' ||
          e.action == 'admin_reset_otp';
    });

    final Map<String, OtpAbuseStat> map = {};

    for (final e in events) {
      final actor = (e.actorUserId == null || e.actorUserId!.trim().isEmpty)
          ? 'UNKNOWN'
          : e.actorUserId!.trim();

      final stat = map.putIfAbsent(
        actor,
        () => OtpAbuseStat(
          actorUserId: actor,
          actorRole: (e.actorRole == null || e.actorRole!.trim().isEmpty)
              ? 'unknown'
              : e.actorRole!.trim(),
        ),
      );

      switch (e.action) {
        case 'staff_confirm_pickup_failed':
          stat.otpFailed++;
          break;
        case 'staff_confirm_pickup_ok':
          stat.otpOk++;
          break;
        case 'admin_unlock_otp':
          stat.adminUnlocks++;
          break;
        case 'admin_reset_otp':
          stat.adminResets++;
          break;
      }
    }

    final list = map.values.toList();

    // Score weights:
    // - failed OTP = heavier (3)
    // - reset OTP = medium (2)
    // - unlock = light (1)
    for (final s in list) {
      s.score = (s.otpFailed * 3) + (s.adminResets * 2) + (s.adminUnlocks);
    }

    list.sort((a, b) => b.score.compareTo(a.score));

    return list.take(limit).toList();
  }

  static DeliveryAverages deliveryAverages({DateTime? startInclusive}) {
    final props = _pBox().values.where((p) {
      // use createdAt for range since it's always present
      return _inRange(p.createdAt, startInclusive);
    }).toList();

    Duration? avg(List<Duration> ds) {
      if (ds.isEmpty) return null;
      final totalMs = ds.fold<int>(0, (sum, d) => sum + d.inMilliseconds);
      return Duration(milliseconds: totalMs ~/ ds.length);
    }

    final pendingToTransit = <Duration>[];
    final transitToDelivered = <Duration>[];
    final deliveredToPickup = <Duration>[];

    for (final p in props) {
      if (p.inTransitAt != null) {
        pendingToTransit.add(p.inTransitAt!.difference(p.createdAt));
      }
      if (p.inTransitAt != null && p.deliveredAt != null) {
        transitToDelivered.add(p.deliveredAt!.difference(p.inTransitAt!));
      }
      if (p.deliveredAt != null && p.pickedUpAt != null) {
        deliveredToPickup.add(p.pickedUpAt!.difference(p.deliveredAt!));
      }
    }

    return DeliveryAverages(
      avgPendingToTransit: avg(pendingToTransit),
      avgTransitToDelivered: avg(transitToDelivered),
      avgDeliveredToPickup: avg(deliveredToPickup),
    );
  }
}

class _DriverAgg {
  int score = 0;
  int active = 0;
  int ended = 0;
  int cancelled = 0;
}

class _StationAgg {
  int deliveredOrPickedUp = 0;
  int pickedUp = 0;
}
