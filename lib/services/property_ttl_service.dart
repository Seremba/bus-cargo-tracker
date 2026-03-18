import '../models/property.dart';
import '../models/property_status.dart';
import 'audit_service.dart';
import 'hive_service.dart';
import 'notification_service.dart';
import 'payment_service.dart';
import 'session.dart';
import 'sync_service.dart';

/// F5: Property TTL service.
///
/// Rules (unpaid pending properties only):
///   • Day 3+  → send a daily warning notification to sender + admin
///               until the property is paid, expired, or restored.
///   • Day 10+ → auto-expire: set status to PropertyStatus.expired.
///
/// The last-warned timestamp is stored on the Property via a sentinel in
/// the audit log — we avoid adding a new Hive field by tracking the
/// warning day-count from createdAt and comparing to DateTime.now().
///
/// "Unpaid" means no PaymentRecord with amount > 0 exists for the property.
class PropertyTtlService {
  PropertyTtlService._();

  // ── Thresholds ────────────────────────────────────────────────────────────
  static const int _warnAfterDays = 3;
  static const int _expireAfterDays = 10;

  // Key used in appSettingsBox to track the last date we ran TTL checks,
  // so we only emit one warning per calendar day even if the 30-min ticker
  // fires multiple times.
  static const String _lastRunDateKey = 'property_ttl_last_run_date';

  // ── Public entry point ───────────────────────────────────────────────────

  /// Call this on app startup and from the AutoSyncService ticker.
  /// Returns counts of warned and expired properties for logging.
  static Future<({int warned, int expired})> runChecks() async {
    final today = _dateOnly(DateTime.now());

    // Rate-limit: only process once per calendar day.
    // This prevents the 30-min ticker from spamming notifications.
    final box = HiveService.appSettingsBox();
    final lastRunRaw = box.get(_lastRunDateKey) as String?;
    if (lastRunRaw != null) {
      final lastRun = DateTime.tryParse(lastRunRaw);
      if (lastRun != null && _dateOnly(lastRun) == today) {
        return (warned: 0, expired: 0);
      }
    }

    // Mark today as processed before doing any work (idempotent on re-run)
    await box.put(_lastRunDateKey, today.toIso8601String());

    int warned = 0;
    int expired = 0;

    final propBox = HiveService.propertyBox();
    final now = DateTime.now();

    for (final p in propBox.values.toList()) {
      // Only unpaid pending properties are eligible
      if (p.status != PropertyStatus.pending) continue;
      if (_isPaid(p)) continue;

      final ageInDays = now.difference(p.createdAt).inDays;

      if (ageInDays >= _expireAfterDays) {
        await _expireProperty(p, now: now);
        expired++;
      } else if (ageInDays >= _warnAfterDays) {
        await _warnProperty(p, ageInDays: ageInDays);
        warned++;
      }
    }

    if (warned > 0 || expired > 0) {
      await AuditService.log(
        action: 'PROPERTY_TTL_CHECK',
        details:
            'TTL run: warned=$warned expired=$expired date=${today.toIso8601String()}',
      );
    }

    return (warned: warned, expired: expired);
  }

  // ── Admin restore: expired → pending ─────────────────────────────────────

  /// Restores an expired property back to pending.
  /// Only callable by admin. Clears the expiry so TTL won't immediately
  /// re-expire it (it will get a fresh createdAt-relative countdown).
  static Future<bool> adminRestoreExpired(Property p) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;
    if (fresh.status != PropertyStatus.expired) return false;

    final actorId = (Session.currentUserId ?? '').trim();

    fresh.status = PropertyStatus.pending;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_EXPIRED_RESTORED',
      propertyKey: fresh.key.toString(),
      details:
          'Admin $actorId restored expired property ${fresh.propertyCode} to pending.',
    );

    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property restored',
      message:
          'Admin has restored your expired property (${fresh.propertyCode}). '
          'Please bring it to the desk as soon as possible.',
    );

    return true;
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static bool _isPaid(Property p) {
    return PaymentService.hasValidPaymentForProperty(p.key.toString());
  }

  static DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  static Future<void> _warnProperty(
    Property p, {
    required int ageInDays,
  }) async {
    final daysLeft = _expireAfterDays - ageInDays;
    final code = p.propertyCode.trim().isEmpty
        ? p.key.toString()
        : p.propertyCode.trim();

    // Notify sender
    await NotificationService.notify(
      targetUserId: p.createdByUserId,
      title:
          'Property pending payment — expires in $daysLeft day${daysLeft == 1 ? '' : 's'}',
      message:
          'Your property ($code) for ${p.receiverName} to ${p.destination} '
          'has not been paid at the desk yet.\n'
          'It will be automatically expired in $daysLeft day${daysLeft == 1 ? '' : 's'} '
          'if no payment is recorded.\n'
          'Please visit the desk to complete payment.',
    );

    // Notify admin inbox
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title:
          'TTL warning: property unpaid ($daysLeft day${daysLeft == 1 ? '' : 's'} left)',
      message:
          'Property $code for ${p.receiverName} → ${p.destination} '
          'is $ageInDays day${ageInDays == 1 ? '' : 's'} old with no payment. '
          'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}.',
    );

    await AuditService.log(
      action: 'PROPERTY_TTL_WARNED',
      propertyKey: p.key.toString(),
      details:
          'TTL warning sent. Age=${ageInDays}d daysLeft=$daysLeft code=$code',
    );
  }

  static Future<void> _expireProperty(
    Property p, {
    required DateTime now,
  }) async {
    final fresh = HiveService.propertyBox().get(p.key) ?? p;

    // Double-check it hasn't been paid or status-changed since we started
    if (fresh.status != PropertyStatus.pending) return;
    if (_isPaid(fresh)) return;

    final code = fresh.propertyCode.trim().isEmpty
        ? fresh.key.toString()
        : fresh.propertyCode.trim();

    fresh.status = PropertyStatus.expired;
    fresh.aggregateVersion += 1;
    await fresh.save();

    await AuditService.log(
      action: 'PROPERTY_TTL_EXPIRED',
      propertyKey: fresh.key.toString(),
      details:
          'Auto-expired after ${_expireAfterDays}d with no payment. code=$code '
          'receiver=${fresh.receiverName} destination=${fresh.destination}',
    );

    await SyncService.enqueueAdminOverrideApplied(
      aggregateType: 'property',
      aggregateId: fresh.propertyCode.trim(),
      actorUserId: 'system',
      payload: {
        'propertyCode': fresh.propertyCode,
        'fromStatus': PropertyStatus.pending.name,
        'toStatus': PropertyStatus.expired.name,
        'reason': 'auto_ttl',
        'expiredAt': now.toIso8601String(),
        'aggregateVersion': fresh.aggregateVersion,
      },
    );

    // Notify sender
    await NotificationService.notify(
      targetUserId: fresh.createdByUserId,
      title: 'Property expired',
      message:
          'Your property ($code) for ${fresh.receiverName} to ${fresh.destination} '
          'has expired because no payment was recorded within $_expireAfterDays days.\n'
          'Please contact the desk or admin to have it restored.',
    );

    // Notify admin inbox
    await NotificationService.notify(
      targetUserId: NotificationService.adminInbox,
      title: 'Property auto-expired',
      message:
          'Property $code for ${fresh.receiverName} → ${fresh.destination} '
          'was auto-expired after $_expireAfterDays days with no payment.',
    );
  }
}
