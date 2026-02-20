import '../models/property.dart';
import '../models/property_status.dart';
import 'hive_service.dart';

class PickupQrService {
  // Pickup QR expiry (5 minutes)
  static const Duration ttl = Duration(minutes: 5);

  // QR payload format: pickup|<propertyKey>|<nonce>
  static String buildPayload({
    required int propertyKey,
    required String nonce,
  }) {
    return 'pickup|$propertyKey|$nonce';
  }

  static ({int propertyKey, String nonce})? parsePayload(String raw) {
    final t = raw.trim();
    final parts = t.split('|');
    if (parts.length != 3) return null;
    if (parts[0] != 'pickup') return null;

    final key = int.tryParse(parts[1]);
    if (key == null) return null;

    final nonce = parts[2].trim();
    if (nonce.isEmpty) return null;

    return (propertyKey: key, nonce: nonce);
  }

  static String _nonce(int propertyKey) {
    final ms = DateTime.now().millisecondsSinceEpoch;
    final a = (ms % 2176782336).toRadixString(36).toUpperCase();
    final b = (propertyKey % 1679616)
        .toRadixString(36)
        .toUpperCase()
        .padLeft(4, '0');
    return '$a$b';
  }

  static int? _keyInt(Property p) {
    final k = p.key;
    if (k is int) return k;
    return int.tryParse(k.toString());
  }

  /// Call this immediately when you set status = delivered.
  static Future<void> issueForDelivered(
    Property p, {
    required String otp,
  }) async {
    final box = HiveService.propertyBox();
    final fresh = box.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.delivered) return;

    final keyInt = _keyInt(fresh);
    if (keyInt == null) return;

    // OTP session (longer lived)
    fresh.pickupOtp = otp;
    fresh.otpGeneratedAt = DateTime.now();
    fresh.otpAttempts = 0;
    fresh.otpLockedUntil = null;

    // QR session (short lived)
    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _nonce(keyInt);
    fresh.qrConsumedAt = null;

    await fresh.save();
  }

  // QR expiry is based ONLY on qrIssuedAt + ttl.
  // OTP expiry is handled elsewhere (manual OTP flow / OTP TTL).
  static bool _isExpired(Property p) {
    final issued = p.qrIssuedAt;
    if (issued == null) return true;

    final now = DateTime.now();
    return now.isAfter(issued.add(ttl));
  }

  /// After scan, staff enters OTP → confirm pickup.
  static Future<String?> confirmPickup({
    required int propertyKey,
    required String scannedNonce,
    required String enteredOtp,
  }) async {
    final box = HiveService.propertyBox();
    final p = box.get(propertyKey);

    if (p == null) return 'Property not found.';
    if (p.status != PropertyStatus.delivered) {
      return 'Property is not in Delivered state.';
    }
    if (p.qrConsumedAt != null) return 'Pickup QR already used.';
    if (p.qrNonce.trim().isEmpty) return 'Pickup QR not issued.';
    if (p.qrNonce.trim() != scannedNonce.trim()) {
      return 'Invalid pickup QR (nonce mismatch).';
    }

    final lockedUntil = p.otpLockedUntil;
    if (lockedUntil != null && DateTime.now().isBefore(lockedUntil)) {
      return 'OTP locked. Try again later.';
    }

    if (_isExpired(p)) return 'Pickup QR expired. Please refresh QR and try again.';

    final otp = (p.pickupOtp ?? '').trim();
    if (otp.isEmpty) return 'OTP missing. Ask staff to re-issue.';

    if (otp != enteredOtp.trim()) {
      p.otpAttempts = p.otpAttempts + 1;

      if (p.otpAttempts >= 3) {
        p.otpLockedUntil = DateTime.now().add(const Duration(minutes: 5));
      }
      await p.save();
      return 'Wrong OTP.';
    }

    final now = DateTime.now();
    p.qrConsumedAt = now;
    p.staffPickupConfirmed = true;
    p.receiverPickupConfirmed = true;
    p.pickedUpAt = now;
    p.status = PropertyStatus.pickedUp;

    await p.save();
    return null;
  }

  /// Sender/Staff can call this to refresh an expired QR session (OTP stays same).
  static Future<bool> refreshForDelivered(Property p) async {
    final box = HiveService.propertyBox();
    final fresh = box.get(p.key) ?? p;

    if (fresh.status != PropertyStatus.delivered) return false;
    if (fresh.qrConsumedAt != null) return false;

    final otp = (fresh.pickupOtp ?? '').trim();
    if (otp.isEmpty) return false;

    final keyInt = _keyInt(fresh);
    if (keyInt == null) return false;

    fresh.qrIssuedAt = DateTime.now();
    fresh.qrNonce = _nonce(keyInt);
    fresh.qrConsumedAt = null;

    await fresh.save();
    return true;
  }
}