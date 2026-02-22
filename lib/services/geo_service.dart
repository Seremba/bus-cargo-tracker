import 'dart:math';

class GeoService {
  // Haversine distance (meters)
  static double distanceMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadius = 6371000.0; // meters
    final dLat = _degToRad(lat2 - lat1);
    final dLng = _degToRad(lng2 - lng1);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLng / 2) *
            sin(dLng / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  /// If accuracyMeters is provided (or non-zero), it expands the radius.
  static bool withinRadius({
    required double busLat,
    required double busLng,
    required double cpLat,
    required double cpLng,
    required double radiusMeters,
    double accuracyMeters = 0,
  }) {
    final d = distanceMeters(busLat, busLng, cpLat, cpLng);
    return d <= (radiusMeters + (accuracyMeters.isNaN ? 0 : accuracyMeters));
  }
}
