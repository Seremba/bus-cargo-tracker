import '../models/checkpoint.dart';
import 'routes.dart';

class RouteMatch {
  final AppRoute route;
  final RouteCheckpoint checkpoint;

  const RouteMatch({required this.route, required this.checkpoint});
}

String normalizePlaceName(String input) {
  return input.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

AppRoute? findRouteById(String? id) {
  if (id == null) return null;
  final rid = id.trim();
  if (rid.isEmpty) return null;

  for (final r in routes) {
    if (r.id == rid) return r;
  }
  return null;
}

List<RouteMatch> findRoutesByDestination(String? destination) {
  if (destination == null) return const [];

  final clean = normalizePlaceName(destination);
  if (clean.isEmpty) return const [];

  final matches = <RouteMatch>[];

  for (final route in routes) {
    for (final cp in route.checkpoints) {
      if (normalizePlaceName(cp.name) == clean) {
        matches.add(RouteMatch(route: route, checkpoint: cp));
      }
    }
  }

  return matches;
}

List<Checkpoint> validatedCheckpoints(AppRoute route) {
  final cps = route.checkpoints.map((c) => c.toCheckpoint()).toList();

  final valid = cps.where((cp) {
    final badZero = cp.lat == 0.0 && cp.lng == 0.0;
    final badRange = cp.lat.abs() > 90 || cp.lng.abs() > 180;
    return !badZero && !badRange;
  }).toList();

  if (valid.length < 2) return [];
  return valid;
}
