import '../models/property.dart';
import '../models/property_status.dart';
import '../models/trip.dart';
import '../models/trip_status.dart';
import 'hive_service.dart';
import 'property_service.dart';

class CargoException {
  final String title;
  final String subtitle;
  final Property property;

  CargoException({
    required this.title,
    required this.subtitle,
    required this.property,
  });
}

class TripException {
  final String title;
  final String subtitle;
  final Trip trip;

  TripException({
    required this.title,
    required this.subtitle,
    required this.trip,
  });
}

class ExceptionService {
  // =========================
  // Tunable thresholds
  // =========================
  static const Duration pendingTooLong = Duration(hours: 24);
  static const Duration inTransitTooLong = Duration(hours: 18);
  static const Duration deliveredNotPickedUpTooLong = Duration(days: 2);
  static const Duration tripNoProgressTooLong = Duration(minutes: 45);

  static bool _inRange(DateTime when, DateTime? startInclusive) {
    if (startInclusive == null) return true;
    return !when.isBefore(startInclusive);
  }

  // =========================
  // OTP exceptions
  // =========================
  static List<CargoException> lockedOtpCargo({DateTime? startInclusive}) {
    final props = HiveService.propertyBox().values.where((p) {
      if (p.status != PropertyStatus.delivered) return false;
      final base = p.deliveredAt ?? p.createdAt;
      if (!_inRange(base, startInclusive)) return false;
      return PropertyService.isOtpLocked(p);
    });

    final out = <CargoException>[];
    for (final p in props) {
      final mins = PropertyService.remainingLockMinutes(p);
      out.add(
        CargoException(
          title: '🔒 OTP locked',
          subtitle:
              '${p.receiverName} • ${p.receiverPhone} • Lock: $mins min • Station: ${p.destination}',
          property: p,
        ),
      );
    }

    out.sort((a, b) {
      final ad = a.property.deliveredAt ?? a.property.createdAt;
      final bd = b.property.deliveredAt ?? b.property.createdAt;
      return bd.compareTo(ad);
    });
    return out;
  }

  static List<CargoException> expiredOtpCargo({DateTime? startInclusive}) {
    final props = HiveService.propertyBox().values.where((p) {
      if (p.status != PropertyStatus.delivered) return false;
      final base = p.deliveredAt ?? p.createdAt;
      if (!_inRange(base, startInclusive)) return false;
      return PropertyService.isOtpExpired(p);
    });

    final out = <CargoException>[];
    for (final p in props) {
      out.add(
        CargoException(
          title: '⏱ OTP expired',
          subtitle:
              '${p.receiverName} • ${p.receiverPhone} • Station: ${p.destination}',
          property: p,
        ),
      );
    }

    out.sort((a, b) {
      final ad = a.property.deliveredAt ?? a.property.createdAt;
      final bd = b.property.deliveredAt ?? b.property.createdAt;
      return bd.compareTo(ad);
    });
    return out;
  }

  // =========================
  // Cargo stuck exceptions
  // =========================
  static List<CargoException> stuckPending({DateTime? startInclusive}) {
    final now = DateTime.now();

    final props = HiveService.propertyBox().values.where((p) {
      if (p.status != PropertyStatus.pending) return false;
      if (!_inRange(p.createdAt, startInclusive)) return false;
      return now.difference(p.createdAt) >= pendingTooLong;
    });

    final out = <CargoException>[];
    for (final p in props) {
      final age = now.difference(p.createdAt);
      out.add(
        CargoException(
          title: '🟡 Stuck pending',
          subtitle:
              '${p.receiverName} • ${p.receiverPhone} • Age: ${_fmtAge(age)} • Dest: ${p.destination}',
          property: p,
        ),
      );
    }

    out.sort((a, b) => b.property.createdAt.compareTo(a.property.createdAt));
    return out;
  }

  static List<CargoException> stuckInTransit({DateTime? startInclusive}) {
    final now = DateTime.now();

    final props = HiveService.propertyBox().values.where((p) {
      if (p.status != PropertyStatus.inTransit) return false;

      final started = p.inTransitAt ?? p.createdAt;
      if (!_inRange(started, startInclusive)) return false;

      return now.difference(started) >= inTransitTooLong;
    });

    final out = <CargoException>[];
    for (final p in props) {
      final since = p.inTransitAt ?? p.createdAt;
      final age = now.difference(since);
      out.add(
        CargoException(
          title: '🔵 Stuck in transit',
          subtitle:
              '${p.receiverName} • ${p.receiverPhone} • '
              '${p.routeName.trim().isEmpty ? '—' : p.routeName} • '
              'Age: ${_fmtAge(age)}',

          property: p,
        ),
      );
    }

    out.sort((a, b) {
      final aSince = a.property.inTransitAt ?? a.property.createdAt;
      final bSince = b.property.inTransitAt ?? b.property.createdAt;
      return bSince.compareTo(aSince);
    });
    return out;
  }

  static List<CargoException> deliveredNotPickedUp({DateTime? startInclusive}) {
    final now = DateTime.now();

    final props = HiveService.propertyBox().values.where((p) {
      if (p.status != PropertyStatus.delivered) return false;
      final deliveredAt = p.deliveredAt;
      if (deliveredAt == null) return false;

      if (!_inRange(deliveredAt, startInclusive)) return false;
      return now.difference(deliveredAt) >= deliveredNotPickedUpTooLong;
    });

    final out = <CargoException>[];
    for (final p in props) {
      final age = now.difference(p.deliveredAt!);
      out.add(
        CargoException(
          title: '🟢 Delivered but not picked up',
          subtitle:
              '${p.receiverName} • ${p.receiverPhone} • Station: ${p.destination} • Age: ${_fmtAge(age)}',
          property: p,
        ),
      );
    }

    out.sort(
      (a, b) => b.property.deliveredAt!.compareTo(a.property.deliveredAt!),
    );
    return out;
  }

  // =========================
  // Trips: no progress
  // =========================
  static List<TripException> noProgressTrips({DateTime? startInclusive}) {
    final now = DateTime.now();

    final trips = HiveService.tripBox().values.where((t) {
      if (t.status != TripStatus.active) return false;
      if (!_inRange(t.startedAt, startInclusive)) return false;

      final lastProgressAt = _tripLastProgressAt(t) ?? t.startedAt;
      return now.difference(lastProgressAt) >= tripNoProgressTooLong;
    });

    final out = <TripException>[];
    for (final t in trips) {
      final lastProgressAt = _tripLastProgressAt(t) ?? t.startedAt;
      final age = now.difference(lastProgressAt);

      final lastIndex = t.lastCheckpointIndex;
      final lastName = (lastIndex >= 0 && lastIndex < t.checkpoints.length)
          ? t.checkpoints[lastIndex].name
          : 'No checkpoint yet';

      out.add(
        TripException(
          title: '🚍 Trip stalled',
          subtitle:
              '${t.routeName} • Driver: ${t.driverUserId} • Last: $lastName • Since: ${_fmtAge(age)}',
          trip: t,
        ),
      );
    }

    out.sort((a, b) => b.trip.startedAt.compareTo(a.trip.startedAt));
    return out;
  }

  static DateTime? _tripLastProgressAt(Trip t) {
    final i = t.lastCheckpointIndex;
    if (i >= 0 && i < t.checkpoints.length) {
      return t.checkpoints[i].reachedAt;
    }
    return null;
  }

  static String _fmtAge(Duration d) {
    final mins = d.inMinutes;
    if (mins < 60) return '${mins}m';
    final h = mins ~/ 60;
    final m = mins % 60;
    if (h < 48) return '${h}h ${m}m';
    final days = d.inDays;
    return '${days}d';
  }
}
