import 'package:geolocator/geolocator.dart';

/// Result of a location pre-flight check.
enum LocationStatus {
  /// Location services enabled and permission granted — ready to track.
  ready,

  /// Location services are disabled on the device (Settings → Location).
  serviceDisabled,

  /// App permission not yet granted — will prompt user.
  permissionDenied,

  /// App permission permanently denied — must go to app settings.
  permissionDeniedForever,
}

class LocationService {
  /// Full pre-flight check — returns the specific reason if location
  /// cannot be used so the UI can show the right message and action.
  static Future<LocationStatus> checkStatus() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return LocationStatus.serviceDisabled;

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) {
      return LocationStatus.permissionDeniedForever;
    }
    if (perm == LocationPermission.denied) {
      return LocationStatus.permissionDenied;
    }
    return LocationStatus.ready;
  }

  /// Request permission if not yet granted. Returns true if ready.
  static Future<bool> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }

  static Stream<Position> positionStream() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,

        // Lowered from 50m — triggers more frequently so checkpoints
        // near town centres and borders aren't missed
        distanceFilter: 20,

        intervalDuration: const Duration(seconds: 10),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationText: 'UNEX LOGISTICS is tracking your trip',
          notificationTitle: 'Trip in progress',
          enableWakeLock: true,
          setOngoing: true, // prevents notification from being dismissed
        ),
      ),
    );
  }
}