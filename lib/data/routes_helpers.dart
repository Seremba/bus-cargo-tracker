import '../models/checkpoint.dart';
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

List<Checkpoint> validatedCheckpoints(AppRoute route) {
  final cps = route.checkpoints.map((c) => c.toCheckpoint()).toList();

  // Remove invalid coordinates (0,0) or nonsense
  final valid = cps.where((cp) {
    final badZero = cp.lat == 0.0 && cp.lng == 0.0;
    final badRange = cp.lat.abs() > 90 || cp.lng.abs() > 180;
    return !badZero && !badRange;
  }).toList();

  // Ensure at least 2 checkpoints (start + end) to track anything
  if (valid.length < 2) return [];
  return valid;
}
