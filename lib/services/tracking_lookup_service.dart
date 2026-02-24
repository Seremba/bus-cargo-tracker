import '../models/property.dart';
import '../models/property_status.dart';
import 'hive_service.dart';

class TrackingLookupResult {
  final Property property;
  final String statusLabel;
  final DateTime lastUpdatedAt;

  TrackingLookupResult({
    required this.property,
    required this.statusLabel,
    required this.lastUpdatedAt,
  });
}

class TrackingLookupService {
  TrackingLookupService._();

  static String normalize(String raw) => raw.trim().toUpperCase();

  static TrackingLookupResult? findByCode(String rawCode) {
    final code = normalize(rawCode);
    if (code.isEmpty) return null;

    final box = HiveService.propertyBox();

    Property? match;
    for (final p in box.values.whereType<Property>()) {
      if (p.trackingCode.trim().toUpperCase() == code) {
        match = p;
        break;
      }
    }

    if (match == null) return null;

    return TrackingLookupResult(
      property: match,
      statusLabel: _friendlyStatus(match),
      lastUpdatedAt: _lastUpdated(match),
    );
  }

  static String _friendlyStatus(Property p) {
    // your "loaded" milestone is timestamp-based
    final isLoadedMilestone =
        p.loadedAt != null && p.status == PropertyStatus.pending;

    if (isLoadedMilestone) return 'LOADED';

    switch (p.status) {
      case PropertyStatus.pending:
        return 'PENDING';
      case PropertyStatus.inTransit:
        return 'IN TRANSIT';
      case PropertyStatus.delivered:
        return 'DELIVERED';
      case PropertyStatus.pickedUp:
        return 'PICKED UP';
    }
  }

  static DateTime _lastUpdated(Property p) {
    return p.pickedUpAt ??
        p.deliveredAt ??
        p.inTransitAt ??
        p.loadedAt ??
        p.createdAt;
  }
}