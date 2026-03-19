import '../models/property_status.dart';
import '../models/trip_status.dart';

class PropertyStatusLabels {
  static String text(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.pending:
        return 'Pending';
      case PropertyStatus.loaded:
        return 'Loaded';
      case PropertyStatus.inTransit:
        return 'In Transit';
      case PropertyStatus.delivered:
        return 'Delivered';
      case PropertyStatus.pickedUp:
        return 'Picked Up';
      case PropertyStatus.rejected:
        return 'Rejected';
      case PropertyStatus.expired:
        return 'Expired';
      case PropertyStatus.underReview:
        return 'Under Review';
    }
  }
}

class TripStatusLabels {
  static String text(TripStatus s) {
    switch (s) {
      case TripStatus.active:
        return 'Active';
      case TripStatus.ended:
        return 'Ended';
      case TripStatus.cancelled:
        return 'Cancelled';
    }
  }
}
