import 'package:geolocator/geolocator.dart';

class LocationService {
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