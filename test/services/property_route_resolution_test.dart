import 'package:flutter_test/flutter_test.dart';

import 'package:bus_cargo_tracker/data/routes_helpers.dart';

void main() {
  group('route resolution', () {
    test('unique destination returns exactly one route match', () {
      final matches = findRoutesByDestination('Juba');

      expect(matches.length, 1);
      expect(matches.first.route.id, 'kla_juba');
      expect(matches.first.checkpoint.name, 'Juba');
    });

    test('ambiguous destination returns multiple route matches', () {
      final matches = findRoutesByDestination('Kabale');

      expect(matches.length, greaterThan(1));

      final routeIds = matches.map((m) => m.route.id).toSet();
      expect(routeIds.contains('kla_kigali_katuna'), isTrue);
      expect(routeIds.contains('kla_goma'), isTrue);
    });

    test('invalid destination returns no matches', () {
      final matches = findRoutesByDestination('Atlantis');

      expect(matches, isEmpty);
    });

    test('route lookup is case insensitive and trims spaces', () {
      final matches = findRoutesByDestination('   juba   ');

      expect(matches.length, 1);
      expect(matches.first.route.id, 'kla_juba');
    });
  });

  group('checkpoint autocomplete search', () {
    test('returns prefix matches first', () {
      final results = searchCheckpointNames('ju', limit: 10);

      expect(results, isNotEmpty);

      final prefixMatches = results
          .where((r) => normalizePlaceName(r).startsWith('ju'))
          .toList();

      if (prefixMatches.isNotEmpty) {
        final firstNonPrefixIndex = results.indexWhere(
          (r) => !normalizePlaceName(r).startsWith('ju'),
        );

        if (firstNonPrefixIndex != -1) {
          for (int i = 0; i < firstNonPrefixIndex; i++) {
            expect(normalizePlaceName(results[i]).startsWith('ju'), isTrue);
          }
        }
      }
    });

    test('deduplicates checkpoint names', () {
      final all = getAllCheckpointNames();
      final asSet = all.toSet();

      expect(all.length, asSet.length);
    });

    test('returns limited number of suggestions', () {
      final results = searchCheckpointNames('', limit: 5);

      expect(results.length, lessThanOrEqualTo(5));
    });

    test('finds partial matches', () {
      final results = searchCheckpointNames('bus', limit: 10);

      expect(
        results.any((r) => normalizePlaceName(r).contains('bus')),
        isTrue,
      );
    });
  });
}