import '../models/checkpoint.dart';
import 'destination_route_map.dart';
import 'routes.dart';

AppRoute? findRouteById(String? id) {
  if (id == null) return null;
  final rid = id.trim();
  if (rid.isEmpty) return null;

  for (final r in routes) {
    if (r.id == rid) return r;
  }
  return null;
}

AppRoute? findRouteByDestination(String? destination) {
  if (destination == null) return null;

  final clean = destination.trim().toLowerCase();
  if (clean.isEmpty) return null;

  final routeId = destinationToRouteId[clean];
  if (routeId == null) return null;

  return findRouteById(routeId);
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
