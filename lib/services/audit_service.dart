import '../models/audit_event.dart';
import '../models/sync_event_type.dart';
import 'hive_service.dart';
import 'session.dart';
import 'sync_service.dart';

class AuditService {
  static Future<void> log({
    required String action,
    String? propertyKey,
    String? tripId,
    String? details,
  }) async {
    final box = HiveService.auditBox();

    final event = AuditEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      at: DateTime.now(),
      action: action,
      actorUserId: Session.currentUserId,
      actorRole: Session.currentRole?.name,
      propertyKey: propertyKey,
      tripId: tripId,
      details: details,
    );

    await box.add(event);

    final actionLower = action.trim().toLowerCase();
    final looksExceptional =
        actionLower.contains('exception') ||
        actionLower.contains('failed') ||
        actionLower.contains('error') ||
        actionLower.contains('override');

    if (!looksExceptional) return;

    try {
      final actorUserId = (Session.currentUserId ?? '').trim().isEmpty
          ? 'system'
          : (Session.currentUserId ?? '').trim();

      final aggregateType = (propertyKey ?? '').trim().isNotEmpty
          ? 'property'
          : ((tripId ?? '').trim().isNotEmpty ? 'trip' : 'system');

      final aggregateId = (propertyKey ?? '').trim().isNotEmpty
          ? propertyKey!.trim()
          : ((tripId ?? '').trim().isNotEmpty ? tripId!.trim() : 'system');

      await SyncService.enqueueExceptionLogged(
        aggregateType: aggregateType,
        aggregateId: aggregateId,
        actorUserId: actorUserId,
        payload: {
          'action': action,
          'propertyKey': propertyKey ?? '',
          'tripId': tripId ?? '',
          'details': details ?? '',
          'loggedAt': event.at.toIso8601String(),
          'syncEventType': SyncEventType.exceptionLogged.name,
        },
      );
    } catch (_) {
      // Do not break audit logging if sync enqueue fails.
    }
  }
}
