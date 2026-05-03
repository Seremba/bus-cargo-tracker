import '../services/hive_service.dart';

/// Centralised user name resolver.
///
/// Looks up a user by ID in the local Hive userBox and returns their
/// full name. Falls back gracefully when the user hasn't synced yet.
///
/// Replaces the four copies of _resolveUser / _resolveSender that were
/// scattered across admin screens.
class UserResolver {
  UserResolver._();

  /// Returns the user's full name for [userId].
  ///
  /// Fallback chain:
  ///   1. Full name from userBox   → e.g. "Patrick Seremba"
  ///   2. [fallback] if provided   → e.g. "Sender (not synced)"
  ///   3. Empty string / '—'       → when userId itself is blank
  static String nameFor(
    String? userId, {
    String notSyncedFallback = 'User (not synced)',
  }) {
    final raw = (userId ?? '').trim();
    if (raw.isEmpty) return '—';
    try {
      final user = HiveService.userBox().values.firstWhere((u) => u.id == raw);
      final name = user.fullName.trim();
      return name.isEmpty ? notSyncedFallback : name;
    } catch (_) {
      return notSyncedFallback;
    }
  }

  /// Convenience for resolving a sender — uses a sender-specific fallback.
  static String senderName(String? userId) =>
      nameFor(userId, notSyncedFallback: 'Sender (not synced)');
}