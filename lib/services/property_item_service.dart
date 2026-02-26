import 'package:hive/hive.dart';

import '../models/property.dart';
import '../models/property_item.dart';
import '../models/property_item_status.dart';
import '../models/property_status.dart';

class PropertyItemTripCounts {
  final int total;
  final int loadedForTrip; // items assigned to this trip (loaded/inTransit/etc)
  final int remainingAtStation; // pending items (not loaded yet)

  const PropertyItemTripCounts({
    required this.total,
    required this.loadedForTrip,
    required this.remainingAtStation,
  });
}

class PropertyItemService {
  final Box<PropertyItem> _itemsBox;

  PropertyItemService(this._itemsBox);

  /// Creates PropertyItems (1..itemCount) if missing.
  /// Idempotent: safe to call many times.
  Future<void> ensureItemsForProperty({
    required String propertyKey,
    required String trackingCode,
    required int itemCount,
  }) async {
    final existingCount = _itemsBox.values
        .where((x) => x.propertyKey == propertyKey)
        .length;
    if (existingCount > 0) return;

    final cleanTracking = trackingCode.trim();

    for (int i = 1; i <= itemCount; i++) {
      final itemKey = _itemKey(propertyKey, i);
      final item = PropertyItem(
        itemKey: itemKey,
        propertyKey: propertyKey,
        itemNo: i,
        status: PropertyItemStatus.pending,
        labelCode: _buildLabelCode(cleanTracking, i),
      );
      await _itemsBox.put(itemKey, item);
    }
  }

  List<PropertyItem> getItemsForProperty(String propertyKey) {
    final list = _itemsBox.values
        .where((x) => x.propertyKey == propertyKey)
        .toList();
    list.sort((a, b) => a.itemNo.compareTo(b.itemNo));
    return list;
  }

  /// Desk selects which items to load today (does NOT move inTransit yet).
  /// Only pending -> loaded is allowed.
  Future<void> markSelectedItemsLoaded({
    required String propertyKey,
    required List<int> itemNos,
    required String tripId,
    required DateTime now,
  }) async {
    final items = getItemsForProperty(propertyKey);
    final trip = tripId.trim();

    for (final no in itemNos) {
      final item = items.firstWhere((x) => x.itemNo == no);

      if (item.status != PropertyItemStatus.pending) {
        // Non-blocking: just skip invalid items
        continue;
      }

      item.status = PropertyItemStatus.loaded;
      item.loadedAt = now;
      item.tripId = trip;
      await item.save();
    }
  }

  /// Driver starts trip: move only loaded items assigned to this trip -> inTransit
  Future<void> onTripStartMoveLoadedToInTransit({
    required String tripId,
    required DateTime now,
  }) async {
    final trip = tripId.trim();
    final affected = _itemsBox.values.where(
      (x) => x.tripId == trip && x.status == PropertyItemStatus.loaded,
    );

    for (final item in affected) {
      item.status = PropertyItemStatus.inTransit;
      item.inTransitAt = now;
      await item.save();
    }
  }

  PropertyItemTripCounts computeTripCounts({
    required String propertyKey,
    required String tripId,
  }) {
    final items = getItemsForProperty(propertyKey);
    final total = items.length;
    final trip = tripId.trim();

    final loadedForTrip = items.where((x) => x.tripId == trip).length;
    final remainingAtStation = items
        .where((x) => x.status == PropertyItemStatus.pending)
        .length;

    return PropertyItemTripCounts(
      total: total,
      loadedForTrip: loadedForTrip,
      remainingAtStation: remainingAtStation,
    );
  }

  /// Keeps your existing Property strict status consistent with item reality.
  /// Call this after load, trip start, delivered, picked up, etc.
  Future<void> recomputePropertyAggregate({required Property property}) async {
    final items = getItemsForProperty(property.key);
    if (items.isEmpty) return;

    final bool anyInTransit = items.any(
      (x) => x.status == PropertyItemStatus.inTransit,
    );

    final bool allDelivered = items.every(
      (x) =>
          x.status == PropertyItemStatus.delivered ||
          x.status == PropertyItemStatus.pickedUp,
    );

    final bool allPickedUp = items.every(
      (x) => x.status == PropertyItemStatus.pickedUp,
    );

    PropertyStatus newStatus;

    if (allPickedUp) {
      newStatus = PropertyStatus.pickedUp;
    } else if (allDelivered) {
      newStatus = PropertyStatus.delivered;
    } else if (anyInTransit) {
      newStatus = PropertyStatus.inTransit;
    } else {
      // IMPORTANT: property stays pending until trip starts
      newStatus = PropertyStatus.pending;
    }

    if (property.status != newStatus) {
      property.status = newStatus;
      await property.save();
    }

    if (property.loadedAt == null) {
      final loadedTimes =
          items
              .where((x) => x.loadedAt != null)
              .map((x) => x.loadedAt!)
              .toList()
            ..sort();

      if (loadedTimes.isNotEmpty) {
        property.loadedAt = loadedTimes.first;
        await property.save();
      }
    }
  }

  String _itemKey(String propertyKey, int itemNo) => '$propertyKey#$itemNo';

  String _buildLabelCode(String trackingCode, int itemNo) {
    // keep stable + short; scanner gets trackingCode + itemNo
    // Example: "BC-482193-XK|3"
    final tc = trackingCode.trim();
    return '$tc|$itemNo';
  }

  Future<void> onTripStartedMoveLoadedToInTransitForProperty({
    required String propertyKey,
    required String tripId,
    required DateTime now,
  }) async {
    final trip = tripId.trim();

    final affected = _itemsBox.values.where(
      (x) =>
          x.propertyKey == propertyKey &&
          x.status == PropertyItemStatus.loaded &&
          x.tripId.trim().isEmpty,
    );

    for (final item in affected) {
      item.tripId = trip;
      item.status = PropertyItemStatus.inTransit;
      item.inTransitAt = now;
      await item.save();
    }
  }
}
