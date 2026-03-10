import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/property_item_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/location_service.dart';
import '../../services/property_item_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import '../../services/trip_service.dart';

import '../admin/driver_load_overview_screen.dart';

import '../../theme/status_colors.dart';
import '../../ui/status_labels.dart';
import '../../widgets/status_chip.dart';

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
  bool _startingTrip = false;

  bool get _canUseDriverTools =>
      RoleGuard.hasAny({UserRole.driver, UserRole.admin});

  String _s(String? v) => v ?? '';
  String _dashIfEmpty(String? v) {
    final t = (v ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  String? get _assignedRouteId => Session.currentAssignedRouteId?.trim();
  String? get _assignedRouteName => Session.currentAssignedRouteName?.trim();

  @override
  void initState() {
    super.initState();

    if (_canUseDriverTools) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _startGps();
      });
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
    if (_sub != null) return;

    try {
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

          final now = DateTime.now();
          if (now.difference(_lastCheckpointCheck).inSeconds < 8) return;
          _lastCheckpointCheck = now;

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
        onError: (e, st) {
          if (!mounted) return;
          setState(() => _gpsStatus = 'GPS error: $e');
          _restartGps();
        },
        cancelOnError: false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _gpsStatus = 'GPS startup failed: $e');
      }
      _restartGps();
    }
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

  Widget _emptyHint(BuildContext context, String text) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(text, style: TextStyle(color: muted)),
    );
  }

  Widget _gpsPanel(BuildContext context) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);

    final isError =
        _gpsStatus.toLowerCase().contains('error') ||
        _gpsStatus.toLowerCase().contains('failed') ||
        _gpsStatus.toLowerCase().contains('denied');

    final icon = isError ? Icons.gps_off : Icons.gps_fixed;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: isError ? muted : null),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _gpsStatus,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastGpsText(),
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () {
                setState(() => _gpsStatus = 'GPS: retrying...');
                _restartGps();
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startAssignedRouteTrip() async {
    final routeId = _assignedRouteId;
    if (routeId == null || routeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No assigned route for this driver.')),
      );
      return;
    }

    if (_startingTrip) return;
    setState(() => _startingTrip = true);

    try {
      final trip = await PropertyService.startRouteTrip(routeId: routeId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            trip == null
                ? 'No trip started.'
                : 'Trip started for ${trip.routeName} ✅',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _startingTrip = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Session.currentUserId == null ||
        (Session.currentUserId ?? '').trim().isEmpty) {
      return const Scaffold(
        body: Center(child: Text('Session expired. Please login again.')),
      );
    }
    if (!_canUseDriverTools) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final assignedRouteId = _assignedRouteId;
    final assignedRouteName = _assignedRouteName;

    if (assignedRouteId == null || assignedRouteId.isEmpty) {
      return const Scaffold(
        body: Center(
          child: Text('No route assigned to this driver. Contact admin.'),
        ),
      );
    }

    final pBox = HiveService.propertyBox();
    final iBox = HiveService.propertyItemBox();

    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Driver'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([pBox.listenable(), iBox.listenable()]),
        builder: (context, _) {
          final itemSvc = PropertyItemService(iBox);

          final routeProperties =
              pBox.values.where((p) => p.routeId == assignedRouteId).toList()
                ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

          int readyProperties = 0;
          int readyItems = 0;
          int remainingItems = 0;

          for (final p in routeProperties) {
            final items = itemSvc.getItemsForProperty(p.key.toString());

            final loadedReady = items
                .where(
                  (x) =>
                      x.status == PropertyItemStatus.loaded &&
                      x.tripId.trim().isEmpty,
                )
                .length;

            final remaining = items
                .where((x) => x.status == PropertyItemStatus.pending)
                .length;

            if (loadedReady > 0) {
              readyProperties += 1;
              readyItems += loadedReady;
            }

            remainingItems += remaining;
          }

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _activeTripPanel(context),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined),
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

              const SizedBox(height: 10),
              _gpsPanel(context),

              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Assigned Route',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(_dashIfEmpty(assignedRouteName)),
                      const SizedBox(height: 8),
                      Text('Ready properties: $readyProperties'),
                      Text('Ready loaded items: $readyItems'),
                      Text('Remaining at station: $remainingItems'),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_startingTrip || readyItems <= 0)
                              ? null
                              : _startAssignedRouteTrip,
                          child: Text(
                            _startingTrip ? 'Starting...' : 'Start Trip',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),
              const Text(
                'Route Manifest',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Showing cargo for your assigned route only.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 10),

              if (routeProperties.isEmpty)
                _emptyHint(
                  context,
                  'No cargo found yet for your assigned route.',
                ),

              for (final p in routeProperties)
                _manifestCard(context, p, itemSvc: itemSvc),
            ],
          );
        },
      ),
    );
  }

  Widget _manifestCard(
    BuildContext context,
    Property p, {
    required PropertyItemService itemSvc,
  }) {
    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);

    final items = itemSvc.getItemsForProperty(p.key.toString());

    final loadedReady = items
        .where(
          (x) =>
              x.status == PropertyItemStatus.loaded && x.tripId.trim().isEmpty,
        )
        .length;

    final inTransitCount = items
        .where((x) => x.status == PropertyItemStatus.inTransit)
        .length;

    final deliveredCount = items
        .where((x) => x.status == PropertyItemStatus.delivered)
        .length;

    final pickedUpCount = items
        .where((x) => x.status == PropertyItemStatus.pickedUp)
        .length;

    final bg = PropertyStatusColors.background(p.status);
    final fg = PropertyStatusColors.foreground(p.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _s(p.receiverName),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(
                  text: PropertyStatusLabels.text(p.status),
                  bgColor: bg,
                  fgColor: fg,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text('${_s(p.destination)} • ${_s(p.receiverPhone)}'),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Items: ${p.itemCount} • Route: ${_dashIfEmpty(p.routeName)}',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Ready: $loadedReady • In transit: $inTransitCount • Delivered: $deliveredCount • Picked up: $pickedUpCount',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _activeTripPanel(BuildContext context) {
    final trip = TripService.getActiveTripForCurrentDriver();

    final muted = Theme.of(
      context,
    ).colorScheme.onSurface.withValues(alpha: 0.60);
    final surface = Theme.of(context).colorScheme.surface;

    if (trip == null) {
      return Card(
        color: surface,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 18, color: muted),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'No active trip yet. Start your assigned route trip.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    final total = trip.checkpoints.length;
    final reachedCount = (trip.lastCheckpointIndex + 1).clamp(0, total);

    String nextName;
    if (total == 0) {
      nextName = '—';
    } else if (trip.lastCheckpointIndex + 1 >= total) {
      nextName = '— (all checkpoints reached)';
    } else {
      nextName = trip.checkpoints[trip.lastCheckpointIndex + 1].name;
    }

    final tripBg = TripStatusColors.background(trip.status);
    final tripFg = TripStatusColors.foreground(trip.status);

    return Card(
      color: surface,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Active Trip',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(
                  text: TripStatusLabels.text(trip.status),
                  bgColor: tripBg,
                  fgColor: tripFg,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Route: ${trip.routeName}'),
            Text('Next checkpoint: $nextName'),
            Text(
              'Progress: $reachedCount / $total',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
        ),
      ),
    );
  }
}
