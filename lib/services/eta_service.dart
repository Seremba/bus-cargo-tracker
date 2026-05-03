import 'package:flutter/material.dart';
import '../models/property.dart';
import '../models/property_status.dart';
import '../models/trip.dart';
import '../models/trip_status.dart';
import '../services/hive_service.dart';
import '../services/metrics_service.dart';

/// Computes an estimated delivery date for a property.
///
/// Strategy:
///   - In Transit with active trip  → remaining checkpoints × avg time per checkpoint
///   - In Transit, no trip data     → avgTransitToDelivered from historical averages
///   - Loaded / Pending             → avgPendingToTransit + avgTransitToDelivered
///   - Delivered / Picked Up        → no ETA needed
///   - No historical data           → rough fallback based on route length
class EtaService {
  EtaService._();

  static const Duration _fallbackPerCheckpoint = Duration(hours: 3);
  static const Duration _fallbackTransit = Duration(hours: 18);
  static const Duration _fallbackPendingToTransit = Duration(hours: 12);

  /// Returns an [EtaResult] for [property], or null if ETA is not applicable.
  static EtaResult? compute(Property property) {
    switch (property.status) {
      case PropertyStatus.delivered:
      case PropertyStatus.pickedUp:
      case PropertyStatus.rejected:
      case PropertyStatus.expired:
      case PropertyStatus.underReview:
        return null;
      case PropertyStatus.pending:
      case PropertyStatus.loaded:
      case PropertyStatus.inTransit:
        break;
    }

    final avgs = MetricsService.deliveryAverages();

    if (property.status == PropertyStatus.inTransit) {
      return _etaInTransit(property, avgs);
    } else {
      return _etaPendingOrLoaded(property, avgs);
    }
  }

  // ── In Transit ────────────────────────────────────────────────────────────

  static EtaResult _etaInTransit(
    Property property,
    DeliveryAverages avgs,
  ) {
    final tripId = (property.tripId ?? '').trim();
    if (tripId.isNotEmpty) {
      final trip = _findTrip(tripId);
      if (trip != null && trip.status == TripStatus.active) {
        final result = _etaFromTrip(property, trip, avgs);
        if (result != null) return result;
      }
    }

    // Fallback: use historical transit average
    final transitAvg =
        avgs.avgTransitToDelivered ?? _fallbackTransit;
    final base = property.inTransitAt ?? DateTime.now();
    final eta = base.add(transitAvg);
    return EtaResult(
      estimatedAt: eta,
      confidence: EtaConfidence.low,
      basis: 'Based on average transit time',
    );
  }

  static EtaResult? _etaFromTrip(
    Property property,
    Trip trip,
    DeliveryAverages avgs,
  ) {
    final checkpoints = trip.checkpoints;
    if (checkpoints.isEmpty) return null;

    // Find which checkpoint matches the property destination
    final dest = property.destination.trim().toLowerCase();
    int destIndex = -1;
    for (int i = 0; i < checkpoints.length; i++) {
      if (checkpoints[i].name.trim().toLowerCase().contains(dest) ||
          dest.contains(checkpoints[i].name.trim().toLowerCase())) {
        destIndex = i;
        break;
      }
    }

    // If no checkpoint matches destination, use last checkpoint
    if (destIndex == -1) destIndex = checkpoints.length - 1;

    final lastReached = trip.lastCheckpointIndex;
    final remaining = destIndex - lastReached;

    if (remaining <= 0) {
      // Already past destination checkpoint — should be delivered soon
      return EtaResult(
        estimatedAt: DateTime.now().add(const Duration(hours: 2)),
        confidence: EtaConfidence.high,
        basis: 'Approaching destination',
      );
    }

    // Time per checkpoint from historical data or fallback
    Duration timePerCheckpoint = _fallbackPerCheckpoint;
    final transitAvg = avgs.avgTransitToDelivered;
    if (transitAvg != null && checkpoints.length > 1) {
      timePerCheckpoint = transitAvg ~/ (checkpoints.length - 1);
    }

    // Use last checkpoint reached time as base, or inTransitAt
    DateTime base = DateTime.now();
    if (lastReached >= 0 && lastReached < checkpoints.length) {
      final lastCp = checkpoints[lastReached];
      if (lastCp.reachedAt != null) base = lastCp.reachedAt!;
    } else if (property.inTransitAt != null) {
      base = property.inTransitAt!;
    }

    final eta = base.add(timePerCheckpoint * remaining);
    final confidence = transitAvg != null
        ? EtaConfidence.medium
        : EtaConfidence.low;

    return EtaResult(
      estimatedAt: eta,
      confidence: confidence,
      basis: '$remaining checkpoint${remaining == 1 ? '' : 's'} remaining',
    );
  }

  // ── Pending / Loaded ──────────────────────────────────────────────────────

  static EtaResult _etaPendingOrLoaded(
    Property property,
    DeliveryAverages avgs,
  ) {
    final pendingToTransit =
        avgs.avgPendingToTransit ?? _fallbackPendingToTransit;
    final transitToDelivered =
        avgs.avgTransitToDelivered ?? _fallbackTransit;

    final base = property.loadedAt ?? property.createdAt;
    final eta = base.add(pendingToTransit + transitToDelivered);

    return EtaResult(
      estimatedAt: eta,
      confidence: EtaConfidence.low,
      basis: 'Estimated from historical averages',
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static Trip? _findTrip(String tripId) {
    try {
      return HiveService.tripBox().values
          .firstWhere((t) => t.tripId == tripId);
    } catch (_) {
      return null;
    }
  }

  /// Formats an ETA DateTime as a friendly string.
  /// e.g. "Today", "Tomorrow", "Mon 12 May", "In ~3 days"
  static String formatEta(DateTime eta) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final etaDay = DateTime(eta.year, eta.month, eta.day);
    final diff = etaDay.difference(today).inDays;

    if (diff < 0) return 'Overdue';
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Tomorrow';
    if (diff <= 6) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${days[eta.weekday - 1]} ${eta.day} ${months[eta.month - 1]}';
    }
    return 'In ~$diff days';
  }
}

enum EtaConfidence { high, medium, low }

class EtaResult {
  final DateTime estimatedAt;
  final EtaConfidence confidence;
  final String basis;

  const EtaResult({
    required this.estimatedAt,
    required this.confidence,
    required this.basis,
  });

  String get friendlyDate => EtaService.formatEta(estimatedAt);

  Color get confidenceColor {
    switch (confidence) {
      case EtaConfidence.high:
        return const Color(0xFF2E7D32); // green
      case EtaConfidence.medium:
        return const Color(0xFF1565C0); // blue
      case EtaConfidence.low:
        return const Color(0xFFE65100); // orange
    }
  }
}