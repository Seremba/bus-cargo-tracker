import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:bus_cargo_tracker/data/routes_helpers.dart';
import 'package:bus_cargo_tracker/models/audit_event.dart';
import 'package:bus_cargo_tracker/models/notification_item.dart';
import 'package:bus_cargo_tracker/models/property.dart';
import 'package:bus_cargo_tracker/models/property_status.dart';
import 'package:bus_cargo_tracker/models/sync_event.dart';
import 'package:bus_cargo_tracker/models/sync_event_type.dart';
import 'package:bus_cargo_tracker/services/hive_service.dart';
import 'package:bus_cargo_tracker/services/property_service.dart';
import 'package:bus_cargo_tracker/services/session.dart';

void main() {
  late Directory tempDir;

  setUpAll(() {
    if (!Hive.isAdapterRegistered(4)) {
      Hive.registerAdapter(PropertyStatusAdapter());
    }
    if (!Hive.isAdapterRegistered(5)) {
      Hive.registerAdapter(PropertyAdapter());
    }
    if (!Hive.isAdapterRegistered(15)) {
      Hive.registerAdapter(AuditEventAdapter());
    }
    if (!Hive.isAdapterRegistered(14)) {
      Hive.registerAdapter(NotificationItemAdapter());
    }
    if (!Hive.isAdapterRegistered(16)) {
      Hive.registerAdapter(SyncEventTypeAdapter());
    }
    if (!Hive.isAdapterRegistered(17)) {
      Hive.registerAdapter(SyncEventAdapter());
    }
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'bebeto_property_registration_route_test_',
    );

    Hive.init(tempDir.path);

    await HiveService.openPropertyBox();
    await HiveService.openAuditBox();
    await HiveService.openNotificationBox();
    await HiveService.openSyncEventBox();
    await HiveService.openAppSettingsBox();

    Session.currentUserId = 'test_user';
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;
  });

  tearDown(() async {
    Session.currentUserId = null;
    Session.currentRole = null;
    Session.currentUserFullName = null;
    Session.currentStationName = null;

    await Hive.close();

    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PropertyService.registerProperty route logic', () {
    test('auto confirms route when destination has single route', () async {
      final matches = findRoutesByDestination('Juba');
      expect(matches.length, 1);

      final property = await PropertyService.registerProperty(
        receiverName: 'John',
        receiverPhone: '0700000000',
        description: 'Test cargo',
        destination: 'Juba',
        itemCount: 1,
        createdByUserId: 'test_user',
        routeId: matches.first.route.id,
        routeName: matches.first.route.name,
        routeConfirmed: true,
      );

      expect(property.destination, 'Juba');
      expect(property.routeId, matches.first.route.id);
      expect(property.routeName, matches.first.route.name);
      expect(property.routeConfirmed, isTrue);
      expect(property.status, PropertyStatus.pending);
    });

    test(
      'keeps route unconfirmed when destination has multiple routes',
      () async {
        final matches = findRoutesByDestination('Kabale');
        expect(matches.length, greaterThan(1));

        final property = await PropertyService.registerProperty(
          receiverName: 'Jane',
          receiverPhone: '0700000001',
          description: 'Ambiguous route cargo',
          destination: 'Kabale',
          itemCount: 2,
          createdByUserId: 'test_user',
          routeId: '',
          routeName: '',
          routeConfirmed: false,
        );

        expect(property.destination, 'Kabale');
        expect(property.routeId, '');
        expect(property.routeName, '');
        expect(property.routeConfirmed, isFalse);
        expect(property.status, PropertyStatus.pending);
      },
    );

    test(
      'throws when confirmed route is required but route data is empty',
      () async {
        expect(
          () => PropertyService.registerProperty(
            receiverName: 'Alice',
            receiverPhone: '0700000002',
            description: 'Cargo',
            destination: 'Juba',
            itemCount: 1,
            createdByUserId: 'test_user',
            routeId: '',
            routeName: '',
            routeConfirmed: true,
          ),
          throwsArgumentError,
        );
      },
    );

    test('creates sync event with routeConfirmed in payload', () async {
      final matches = findRoutesByDestination('Juba');

      await PropertyService.registerProperty(
        receiverName: 'Mark',
        receiverPhone: '0700000003',
        description: 'Box',
        destination: 'Juba',
        itemCount: 1,
        createdByUserId: 'test_user',
        routeId: matches.first.route.id,
        routeName: matches.first.route.name,
        routeConfirmed: true,
      );

      final events = HiveService.syncEventBox().values.toList();
      expect(events.length, 1);
      expect(events.first.payload['routeConfirmed'], isTrue);
    });
  });
}
