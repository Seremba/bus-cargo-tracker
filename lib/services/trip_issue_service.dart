import '../models/trip.dart';
import 'audit_service.dart';
import 'notification_service.dart';
import 'session.dart';
import 'sync_service.dart';

/// Issue categories a driver can report during a trip.
enum TripIssueCategory {
  customsDelay,
  breakdown,
  roadClosure,
  accident,
  policeStop,
  weatherDelay,
  other,
}

extension TripIssueCategoryLabel on TripIssueCategory {
  String get label {
    switch (this) {
      case TripIssueCategory.customsDelay:
        return 'Customs / Border delay';
      case TripIssueCategory.breakdown:
        return 'Vehicle breakdown';
      case TripIssueCategory.roadClosure:
        return 'Road closure / Diversion';
      case TripIssueCategory.accident:
        return 'Accident / Incident';
      case TripIssueCategory.policeStop:
        return 'Police checkpoint stop';
      case TripIssueCategory.weatherDelay:
        return 'Weather delay';
      case TripIssueCategory.other:
        return 'Other';
    }
  }

  String get icon {
    switch (this) {
      case TripIssueCategory.customsDelay:
        return '🛂';
      case TripIssueCategory.breakdown:
        return '🔧';
      case TripIssueCategory.roadClosure:
        return '🚧';
      case TripIssueCategory.accident:
        return '⚠️';
      case TripIssueCategory.policeStop:
        return '👮';
      case TripIssueCategory.weatherDelay:
        return '🌧️';
      case TripIssueCategory.other:
        return '📋';
    }
  }
}

class TripIssueService {
  TripIssueService._();

  /// Flags an issue on the active trip.
  ///
  /// Records to:
  ///   1. Audit log (local + synced via exceptionLogged)
  ///   2. Admin inbox notification
  ///   3. tripIssueFlagged sync event (pushes to Supabase)
  ///
  /// [gpsLat] and [gpsLng] are captured at the time of flagging and
  /// stored in the sync payload so admin can verify the driver's location.
  static Future<void> flagIssue({
    required Trip trip,
    required TripIssueCategory category,
    required String note,
    double? gpsLat,
    double? gpsLng,
  }) async {
    final actorId = (Session.currentUserId ?? '').trim();
    final driverName =
        (Session.currentUserFullName ?? 'Driver').trim();
    final categoryLabel = category.label;
    final noteClean = note.trim();
    final now = DateTime.now();

    final gpsLabel = (gpsLat != null && gpsLng != null)
        ? '${gpsLat.toStringAsFixed(5)}, ${gpsLng.toStringAsFixed(5)}'
        : 'GPS unavailable';

    final details =
        'Category: $categoryLabel | '
        'GPS: $gpsLabel | '
        'Note: ${noteClean.isEmpty ? '—' : noteClean}';

    // 1. Audit log
    await AuditService.log(
      action: 'TRIP_ISSUE_FLAGGED',
      tripId: trip.tripId,
      details: details,
    );

    // 2. Admin notification
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: '${category.icon} Trip issue: $categoryLabel',
      message:
          'Driver $driverName reported a $categoryLabel '
          'on trip ${trip.routeName}.\n'
          'GPS at time of report: $gpsLabel\n'
          '${noteClean.isEmpty ? '' : 'Note: $noteClean'}',
    );

    // 3. Sync event — pushes to Supabase for cross-device visibility
    await SyncService.enqueueTripIssueFlagged(
      tripId: trip.tripId,
      actorUserId: actorId.isEmpty ? 'system' : actorId,
      payload: {
        'tripId': trip.tripId,
        'routeName': trip.routeName,
        'driverUserId': trip.driverUserId,
        'driverName': driverName,
        'category': category.name,
        'categoryLabel': categoryLabel,
        'note': noteClean,
        'gpsLat': gpsLat,
        'gpsLng': gpsLng,
        'flaggedAt': now.toIso8601String(),
      },
    );
  }
}