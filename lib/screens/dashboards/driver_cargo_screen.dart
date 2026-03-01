import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/location_service.dart';
import '../../services/trip_service.dart';
import '../../services/role_guard.dart';

import '../../data/routes_helpers.dart';
import '../admin/driver_load_overview_screen.dart';

class DriverCargoScreen extends StatefulWidget {
  const DriverCargoScreen({super.key});

  @override
  State<DriverCargoScreen> createState() => _DriverCargoScreenState();
}

class _DriverCargoScreenState extends State<DriverCargoScreen> {
  StreamSubscription<Position>? _sub;
  Timer? _retryTimer;
  int _lastSnackCheckpointIndex = -1;

  String _gpsStatus = 'GPS: not started';
  DateTime? _lastGpsAt;

  DateTime _lastCheckpointCheck = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _canUseDriverTools =>
      RoleGuard.hasAny({UserRole.driver, UserRole.admin});

  String _s(String? v) => v ?? '';
  String _dashIfEmpty(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  @override
  void initState() {
    super.initState();
    if (_canUseDriverTools) {
      _startGps();
    } else {
      _gpsStatus = 'GPS: not allowed';
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _startGps() async {
    if (!_canUseDriverTools) return;

    // Prevent double-start
    if (_sub != null) return;

    final ok = await LocationService.ensurePermission();
    if (!ok) {
      if (mounted) {
        setState(() => _gpsStatus = 'GPS: permission denied / location off');
      }
      _scheduleRetry();
      return;
    }

    if (mounted) setState(() => _gpsStatus = 'GPS: listening...');

    _sub = LocationService.positionStream().listen(
      (Position pos) async {
        if (!mounted) return;

        _lastGpsAt = DateTime.now();
        final activeTrip = TripService.getActiveTripForCurrentDriver();
        if (activeTrip == null) _lastSnackCheckpointIndex = -1;

        setState(() {
          final coords =
              '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';

          final acc = pos.accuracy.isNaN
              ? '—'
              : '${pos.accuracy.toStringAsFixed(0)}m';

          _gpsStatus = activeTrip == null
              ? 'GPS: $coords (±$acc) (no active trip)'
              : 'GPS: $coords (±$acc) (tracking trip: ${activeTrip.routeName})';
        });

        if (activeTrip == null) return;

        // Screen-side throttle (battery + UI stability)
        final now = DateTime.now();
        if (now.difference(_lastCheckpointCheck).inSeconds < 8) return;
        _lastCheckpointCheck = now;

        // ✅ Pass accuracy into service for robust detection
        final reached = await TripService.updateCheckpointFromLocation(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracyMeters: pos.accuracy,
        );

        if (!mounted) return;

        final updatedTrip = TripService.getActiveTripForCurrentDriver();
        final currentIndex = updatedTrip?.lastCheckpointIndex ?? -1;

        if (reached && currentIndex > _lastSnackCheckpointIndex) {
          _lastSnackCheckpointIndex = currentIndex;

          final cpName =
              (updatedTrip != null &&
                  currentIndex >= 0 &&
                  currentIndex < updatedTrip.checkpoints.length)
              ? updatedTrip.checkpoints[currentIndex].name
              : 'Checkpoint';

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$cpName reached ✅')));
        }
      },
      onError: (e) {
        if (!mounted) return;
        setState(() => _gpsStatus = 'GPS: error, retrying...');
        _restartGps();
      },
      cancelOnError: true,
    );
  }

  void _restartGps() {
    _sub?.cancel();
    _sub = null;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 8), () {
      if (!mounted) return;
      _startGps();
    });
  }

  String _lastGpsText() {
    if (_lastGpsAt == null) return 'Last GPS: —';
    return 'Last GPS: ${_lastGpsAt!.toLocal().toString().substring(0, 19)}';
  }

  Widget _emptyHint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: const TextStyle(color: Colors.black54)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUseDriverTools) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.propertyBox();

    final pending =
        box.values.where((p) => p.status == PropertyStatus.pending).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Driver'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _activeTripPanel(),
          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.inventory_2),
              label: const Text('View Load Overview'),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const DriverLoadOverviewScreen(),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _gpsStatus,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(_lastGpsText(), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          const Text(
            'Pending (Ready to Load)',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Rule: Desk must mark LOADED first before you can start a trip.',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
          const SizedBox(height: 8),
          if (pending.isEmpty)
            _emptyHint(
              'No pending cargo to load right now. If you already loaded cargo, check the Active Trip above.',
            ),
          for (final p in pending) _pendingCard(context, p),
        ],
      ),
    );
  }

  Widget _pendingCard(BuildContext context, dynamic p) {
    final loadedOk = p.loadedAt != null;

    final loadedText = loadedOk
        ? 'Loaded ✅ ${p.loadedAt.toLocal().toString().substring(0, 16)}'
        : 'Not loaded yet ❌ (Desk must mark LOADED)';

    return Card(
      child: ListTile(
        title: Row(
          children: [
            Expanded(child: Text(_s(p.receiverName))),
            if (!loadedOk)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.warning_amber_rounded, size: 18),
              ),
          ],
        ),
        subtitle: Text(
          '${_s(p.destination)} • ${_s(p.receiverPhone)}\n'
          'Items: ${p.itemCount} • Route: ${_dashIfEmpty(p.routeName)}\n'
          '$loadedText',
        ),
        trailing: ElevatedButton(
          // ✅ Hard UI-block when desk hasn't marked loaded
          onPressed: loadedOk
              ? () async {
                  // Pre-check (UX)
                  final route = findRouteById(p.routeId);
                  if (route == null) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Route missing ❌ Ask admin/staff'),
                      ),
                    );
                    return;
                  }

                  final cps = validatedCheckpoints(route);
                  if (cps.isEmpty) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Route "${route.name}" has invalid checkpoints ❌',
                        ),
                      ),
                    );
                    return;
                  }

                  try {
                    await PropertyService.markInTransit(p);

                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Marked In Transit ✅')),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Failed: $e')));
                  }
                }
              : null,
          child: Text(loadedOk ? 'Load' : 'Blocked'),
        ),
      ),
    );
  }

  Widget _activeTripPanel() {
    final trip = TripService.getActiveTripForCurrentDriver();

    if (trip == null) {
      return Card(
        color: Colors.orangeAccent.shade100.withValues(alpha: 0.25),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text('No active trip yet. Load cargo to start a trip.'),
              ),
            ],
          ),
        ),
      );
    }

    final nextIndex = trip.lastCheckpointIndex + 1;
    final nextName = (nextIndex >= 0 && nextIndex < trip.checkpoints.length)
        ? trip.checkpoints[nextIndex].name
        : 'Completed';

    return Card(
      color: Colors.lightBlueAccent.shade100.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🚍 Active Trip',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text('Route: ${trip.routeName}'),
            Text('Next checkpoint: $nextName'),
            Text(
              'Progress: ${trip.lastCheckpointIndex + 1} / ${trip.checkpoints.length}',
            ),
          ],
        ),
      ),
    );
  }
}
