import '../models/audit_event.dart';
import 'hive_service.dart';
import 'session.dart';

class AuditService {
  static Future<void> log({
    required String action,
    String? propertyKey,
    String? tripId,
    String? details,
  }) async {
    final box = HiveService.auditBox(); // ✅ ALWAYS opened via HiveService

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
  }
}
