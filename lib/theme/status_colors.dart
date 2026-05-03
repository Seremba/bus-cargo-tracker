import '../ui/status_labels.dart';
import 'package:flutter/material.dart';
import '../models/property_status.dart';
import '../models/property_item_status.dart';
import '../models/trip_status.dart';
import '../ui/app_colors.dart';

class PropertyStatusColors {
  static Color color(PropertyStatus status) {
    switch (status) {
      case PropertyStatus.pending:
        return Colors.grey;
      case PropertyStatus.loaded:
        return Colors.amber;
      case PropertyStatus.inTransit:
        return AppColors.primary;
      case PropertyStatus.delivered:
        return Colors.blue;
      case PropertyStatus.pickedUp:
        return Colors.green;
      case PropertyStatus.rejected:
        return Colors.red;
      case PropertyStatus.expired:
        return Colors.brown;
      case PropertyStatus.underReview:
        return const Color(0xFFFF8F00); // amber 800
    }
  }

  static Color background(PropertyStatus status) =>
      color(status).withValues(alpha: 0.12);
  static Color foreground(PropertyStatus status) => color(status);
}

class PropertyItemStatusColors {
  static Color color(PropertyItemStatus status) {
    switch (status) {
      case PropertyItemStatus.pending:
        return AppColors.secondary;
      case PropertyItemStatus.loaded:
        return AppColors.support;
      case PropertyItemStatus.inTransit:
        return AppColors.primary;
      case PropertyItemStatus.delivered:
        return AppColors.highlight;
      case PropertyItemStatus.pickedUp:
        return Colors.green;
    }
  }

  static Color background(PropertyItemStatus status) =>
      color(status).withValues(alpha: 0.12);
  static Color foreground(PropertyItemStatus status) => color(status);
}

class TripStatusColors {
  static Color color(TripStatus status) {
    switch (status) {
      case TripStatus.active:
        return AppColors.primary;
      case TripStatus.ended:
        return Colors.green;
      case TripStatus.cancelled:
        return Colors.red;
    }
  }

  static Color background(TripStatus status) =>
      color(status).withValues(alpha: 0.12);
  static Color foreground(TripStatus status) => color(status);
}
/// Combined chip style (label + bg + fg) for a PropertyStatus.
/// Replaces the _statusStyle() copies in sender_dashboard,
/// admin_properties_screen, and my_properties_screen.
class PropertyStatusChip {
  static ({String label, Color bg, Color fg}) style(PropertyStatus status) {
    final fg = PropertyStatusColors.foreground(status);
    final bg = PropertyStatusColors.background(status);
    final label = PropertyStatusLabels.text(status);
    return (label: label, bg: bg, fg: fg);
  }
}

/// Extended chip style including emoji indicator.
/// Used by my_properties_screen for the sender's property list.
class PropertyStatusChipEx {
  static ({String emoji, String label, Color bg, Color fg}) style(
    PropertyStatus status,
  ) {
    const emojis = {
      PropertyStatus.pending: '🟡',
      PropertyStatus.loaded: '🟠',
      PropertyStatus.inTransit: '🔵',
      PropertyStatus.delivered: '🟢',
      PropertyStatus.pickedUp: '✅',
      PropertyStatus.rejected: '🔴',
      PropertyStatus.expired: '⏳',
      PropertyStatus.underReview: '🔎',
    };
    final base = PropertyStatusChip.style(status);
    return (
      emoji: emojis[status] ?? '⬜',
      label: base.label,
      bg: base.bg,
      fg: base.fg,
    );
  }
}