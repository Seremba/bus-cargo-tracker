import 'package:hive/hive.dart';

import '../models/property.dart';
import '../models/property_item.dart';
import '../models/property_item_status.dart';
import '../models/property_status.dart';
import '../models/sync_event.dart';
import '../models/sync_event_type.dart';
import 'hive_service.dart';
import 'session.dart';
import 'sync_service.dart';

class PropertyItemTripCounts {
  final int total;
  final int loadedForTrip; // items assigned to this trip (loaded/inTransit/etc)
  final int remainingAtStation; // items still left behind

  const PropertyItemTripCounts({
    required this.total,
    required this.loadedForTrip,
    required this.remainingAtStation,
  });
}

class PropertyItemService {
  final Box _itemsBox;

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
        .cast<PropertyItem>()
        .toList();

    list.sort((a, b) => a.itemNo.compareTo(b.itemNo));
    return list;
  }

  /// Desk selects which items to load today (does NOT move inTransit yet).
  /// Only pending -> loaded is allowed.
  Future<void> markSelectedItemsLoaded({
    required String propertyKey,
    required List<int> itemNos,
    required DateTime now,
    String driverUserId = '',
  }) async {
    final items = getItemsForProperty(propertyKey);
    final validNos = items.map((x) => x.itemNo).toSet();

    for (final no in itemNos) {
      if (!validNos.contains(no)) {
        throw StateError(
          'Item number $no does not exist for property $propertyKey',
        );
      }
    }

    for (final no in itemNos) {
      final item = items.firstWhere((x) => x.itemNo == no);

      if (item.status != PropertyItemStatus.pending) {
        continue;
      }

      item.status = PropertyItemStatus.loaded;
      item.loadedAt = now;
      item.driverUserId = driverUserId.trim();
      await item.save();

      await _emitItemEvent(
        type: SyncEventType.propertyItemLoaded,
        item: item,
        timestamp: now,
      );
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

    for (final raw in affected) {
      final item = raw as PropertyItem;
      item.status = PropertyItemStatus.inTransit;
      item.inTransitAt = now;
      item.loadedAt ??= now;
      await item.save();

      await _emitItemEvent(
        type: SyncEventType.propertyItemInTransit,
        item: item,
        timestamp: now,
      );
    }
  }

  PropertyItemTripCounts computeTripCounts({
    required String propertyKey,
    required String tripId,
  }) {
    final items = getItemsForProperty(propertyKey);
    final total = items.length;
    final trip = tripId.trim();

    final onThisTrip = items.where((x) {
      if (x.tripId.trim() != trip) return false;

      return x.status == PropertyItemStatus.loaded ||
          x.status == PropertyItemStatus.inTransit ||
          x.status == PropertyItemStatus.delivered ||
          x.status == PropertyItemStatus.pickedUp;
    }).length;

    final remainingAtStation = items.where((x) {
      return x.status == PropertyItemStatus.pending ||
          (x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty);
    }).length;

    return PropertyItemTripCounts(
      total: total,
      loadedForTrip: onThisTrip,
      remainingAtStation: remainingAtStation,
    );
  }

  /// Keeps Property aggregate status consistent with item reality.
  Future<void> recomputePropertyAggregate({required Property property}) async {
    final items = getItemsForProperty(property.key.toString());
    if (items.isEmpty) return;

    final bool allPickedUp = items.every(
      (x) => x.status == PropertyItemStatus.pickedUp,
    );

    final bool allDeliveredOrPickedUp = items.every(
      (x) =>
          x.status == PropertyItemStatus.delivered ||
          x.status == PropertyItemStatus.pickedUp,
    );

    final bool anyInTransit = items.any(
      (x) => x.status == PropertyItemStatus.inTransit,
    );

    final bool anyLoaded = items.any(
      (x) => x.status == PropertyItemStatus.loaded,
    );

    final bool allPending = items.every(
      (x) => x.status == PropertyItemStatus.pending,
    );

    PropertyStatus newStatus;
    if (allPickedUp) {
      newStatus = PropertyStatus.pickedUp;
    } else if (allDeliveredOrPickedUp) {
      newStatus = PropertyStatus.delivered;
    } else if (anyInTransit) {
      newStatus = PropertyStatus.inTransit;
    } else if (anyLoaded) {
      newStatus = PropertyStatus.loaded;
    } else if (allPending) {
      newStatus = PropertyStatus.pending;
    } else {
      // mixed edge case, e.g. pending + loaded
      newStatus = PropertyStatus.loaded;
    }

    bool changed = false;

    if (property.status != newStatus) {
      property.status = newStatus;
      changed = true;
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
        changed = true;
      }
    }

    if (newStatus == PropertyStatus.inTransit && property.inTransitAt == null) {
      final inTransitTimes =
          items
              .where((x) => x.inTransitAt != null)
              .map((x) => x.inTransitAt!)
              .toList()
            ..sort();

      if (inTransitTimes.isNotEmpty) {
        property.inTransitAt = inTransitTimes.first;
        changed = true;
      }
    }

    if (newStatus == PropertyStatus.delivered && property.deliveredAt == null) {
      final deliveredTimes =
          items
              .where((x) => x.deliveredAt != null)
              .map((x) => x.deliveredAt!)
              .toList()
            ..sort();

      if (deliveredTimes.isNotEmpty) {
        property.deliveredAt = deliveredTimes.first;
        changed = true;
      }
    }

    if (newStatus == PropertyStatus.pickedUp && property.pickedUpAt == null) {
      final pickedUpTimes =
          items
              .where((x) => x.pickedUpAt != null)
              .map((x) => x.pickedUpAt!)
              .toList()
            ..sort();

      if (pickedUpTimes.isNotEmpty) {
        property.pickedUpAt = pickedUpTimes.first;
        changed = true;
      }
    }

    if (changed) {
      await property.save();
    }
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

    for (final raw in affected) {
      final item = raw as PropertyItem;
      item.tripId = trip;
      item.status = PropertyItemStatus.inTransit;
      item.inTransitAt = now;
      item.loadedAt ??= now;
      await item.save();

      await _emitItemEvent(
        type: SyncEventType.propertyItemInTransit,
        item: item,
        timestamp: now,
      );
    }
  }

  Future<void> markItemsDelivered({
    required String propertyKey,
    required List<int> itemNos,
    required DateTime now,
  }) async {
    final items = getItemsForProperty(propertyKey);
    final validNos = items.map((x) => x.itemNo).toSet();

    for (final no in itemNos) {
      if (!validNos.contains(no)) {
        throw StateError(
          'Item number $no does not exist for property $propertyKey',
        );
      }
    }

    for (final no in itemNos) {
      final item = items.firstWhere((x) => x.itemNo == no);

      if (item.status != PropertyItemStatus.inTransit) {
        continue;
      }

      item.status = PropertyItemStatus.delivered;
      item.deliveredAt = now;
      item.inTransitAt ??= now;
      item.loadedAt ??= item.inTransitAt;
      await item.save();

      await _emitItemEvent(
        type: SyncEventType.propertyItemDelivered,
        item: item,
        timestamp: now,
      );
    }
  }

  Future<void> markItemsPickedUp({
    required String propertyKey,
    required List<int> itemNos,
    required DateTime now,
  }) async {
    final items = getItemsForProperty(propertyKey);
    final validNos = items.map((x) => x.itemNo).toSet();

    for (final no in itemNos) {
      if (!validNos.contains(no)) {
        throw StateError(
          'Item number $no does not exist for property $propertyKey',
        );
      }
    }

    for (final no in itemNos) {
      final item = items.firstWhere((x) => x.itemNo == no);

      if (item.status != PropertyItemStatus.delivered) {
        continue;
      }

      item.status = PropertyItemStatus.pickedUp;
      item.pickedUpAt = now;
      item.deliveredAt ??= now;
      item.inTransitAt ??= item.deliveredAt;
      item.loadedAt ??= item.inTransitAt;
      await item.save();

      await _emitItemEvent(
        type: SyncEventType.propertyItemPickedUp,
        item: item,
        timestamp: now,
      );
    }
  }

  Future<void> _emitItemEvent({
    required SyncEventType type,
    required PropertyItem item,
    required DateTime timestamp,
  }) async {
    final property = _findPropertyByKey(item.propertyKey);
    final actorUserId = (Session.currentUserId ?? '').trim().isEmpty
        ? 'system'
        : Session.currentUserId!.trim();

    await SyncService.enqueueItemEvent(
      type: type,
      itemId: item.itemKey,
      actorUserId: actorUserId,
      payload: {
        'itemKey': item.itemKey,
        'propertyKey': item.propertyKey,
        'propertyCode': property?.propertyCode ?? '',
        'itemNo': item.itemNo,
        'status': _statusName(item.status),
        'tripId': item.tripId,
        'labelCode': item.labelCode,
        'loadedAt': item.loadedAt?.toIso8601String(),
        'inTransitAt': item.inTransitAt?.toIso8601String(),
        'deliveredAt': item.deliveredAt?.toIso8601String(),
        'pickedUpAt': item.pickedUpAt?.toIso8601String(),
        'eventAt': timestamp.toIso8601String(),
      },
    );
  }

  static Future<void> applyPropertyItemLoadedFromSync(SyncEvent event) async {
    final item = _requireItemFromPayload(event);

    if (item.status == PropertyItemStatus.loaded ||
        item.status == PropertyItemStatus.inTransit ||
        item.status == PropertyItemStatus.delivered ||
        item.status == PropertyItemStatus.pickedUp) {
      return;
    }

    item.status = PropertyItemStatus.loaded;
    item.loadedAt =
        _parseDate(event.payload['loadedAt']) ??
        _parseDate(event.payload['eventAt']) ??
        DateTime.now();

    await item.save();
  }

  static Future<void> applyPropertyItemInTransitFromSync(
    SyncEvent event,
  ) async {
    final item = _requireItemFromPayload(event);

    if (item.status == PropertyItemStatus.inTransit ||
        item.status == PropertyItemStatus.delivered ||
        item.status == PropertyItemStatus.pickedUp) {
      return;
    }

    final incomingTripId = (event.payload['tripId'] ?? '').toString().trim();
    if (incomingTripId.isNotEmpty) {
      item.tripId = incomingTripId;
    }

    item.status = PropertyItemStatus.inTransit;
    item.inTransitAt =
        _parseDate(event.payload['inTransitAt']) ??
        _parseDate(event.payload['eventAt']) ??
        DateTime.now();
    item.loadedAt ??= item.inTransitAt;

    await item.save();
  }

  static Future<void> applyPropertyItemDeliveredFromSync(
    SyncEvent event,
  ) async {
    final item = _requireItemFromPayload(event);

    if (item.status == PropertyItemStatus.delivered ||
        item.status == PropertyItemStatus.pickedUp) {
      return;
    }

    item.status = PropertyItemStatus.delivered;
    item.deliveredAt =
        _parseDate(event.payload['deliveredAt']) ??
        _parseDate(event.payload['eventAt']) ??
        DateTime.now();
    item.inTransitAt ??= item.deliveredAt;
    item.loadedAt ??= item.inTransitAt;

    await item.save();
  }

  static Future<void> applyPropertyItemPickedUpFromSync(SyncEvent event) async {
    final item = _requireItemFromPayload(event);

    if (item.status == PropertyItemStatus.pickedUp) {
      return;
    }

    item.status = PropertyItemStatus.pickedUp;
    item.pickedUpAt =
        _parseDate(event.payload['pickedUpAt']) ??
        _parseDate(event.payload['eventAt']) ??
        DateTime.now();
    item.deliveredAt ??= item.pickedUpAt;
    item.inTransitAt ??= item.deliveredAt;
    item.loadedAt ??= item.inTransitAt;

    await item.save();
  }

  static PropertyItem _requireItemFromPayload(SyncEvent event) {
    final itemKey = (event.payload['itemKey'] ?? '').toString().trim();
    if (itemKey.isEmpty) {
      throw StateError('Property item sync event missing itemKey');
    }

    final item = HiveService.propertyItemBox().get(itemKey);
    if (item == null) {
      throw StateError('Property item with key $itemKey not found');
    }

    return item;
  }

  Property? _findPropertyByKey(String propertyKey) {
    for (final p in HiveService.propertyBox().values) {
      if (p.key.toString() == propertyKey) {
        return p;
      }
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  static String _statusName(PropertyItemStatus status) {
    switch (status) {
      case PropertyItemStatus.pending:
        return 'pending';
      case PropertyItemStatus.loaded:
        return 'loaded';
      case PropertyItemStatus.inTransit:
        return 'inTransit';
      case PropertyItemStatus.delivered:
        return 'delivered';
      case PropertyItemStatus.pickedUp:
        return 'pickedUp';
    }
  }

  String _itemKey(String propertyKey, int itemNo) => '$propertyKey#$itemNo';

  String _buildLabelCode(String trackingCode, int itemNo) {
    final tc = trackingCode.trim();
    return '$tc|$itemNo';
  }
}