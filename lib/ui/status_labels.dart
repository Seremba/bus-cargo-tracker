import '../models/property_status.dart';
import '../models/trip_status.dart';

class PropertyStatusLabels {
  static String text(PropertyStatus s) {
    switch (s) {
      case PropertyStatus.pending:
        return 'Pending';
      case PropertyStatus.inTransit:
        return 'In Transit';
      case PropertyStatus.delivered:
        return 'Delivered';
      case PropertyStatus.pickedUp:
        return 'Picked Up';
    }
  }
}

class TripStatusLabels {
  static String text(TripStatus s) {
    return s.name; // fine default
  }
}