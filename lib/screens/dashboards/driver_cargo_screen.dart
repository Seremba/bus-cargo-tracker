import 'dart:async';

import 'package:bus_cargo_tracker/ui/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
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
    _retryTimer?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {
      // Safe to ignore — stream may not have fully initialised.
    } finally {
      _sub = null;
    }
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
      if (mounted) setState(() => _gpsStatus = 'GPS startup failed: $e');
      _restartGps();
    }
  }

  /// Safely cancels the GPS stream and schedules a retry.
  /// Guarded with try/catch to handle the PlatformException thrown when
  /// Retry is tapped before the stream has fully initialised.
  void _restartGps() {
    _retryTimer?.cancel();
    try {
      _sub?.cancel();
    } catch (_) {
      // PlatformException: No active stream to cancel — safe to ignore.
    } finally {
      _sub = null;
    }
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
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

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

          final activeTrip = TripService.getActiveTripForCurrentDriver(
            routeId: assignedRouteId,
          );
          final activeTripId = activeTrip?.tripId;

          final routeProperties = pBox.values.where((p) {
            if (p.routeId != assignedRouteId) return false;
            if (activeTripId != null && activeTripId.isNotEmpty) {
              return (p.tripId ?? '').trim() == activeTripId.trim();
            }
            final items = itemSvc.getItemsForProperty(p.key.toString());
            return items.any(
              (x) =>
                  x.status == PropertyItemStatus.loaded &&
                  x.tripId.trim().isEmpty,
            );
          }).toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

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
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              _activeTripPanel(context),
              const SizedBox(height: 10),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                  label: const Text(
                    'View Load Overview',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(color: AppColors.primary),
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const DriverLoadOverviewScreen(),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              _gpsPanel(context),
              const SizedBox(height: 14),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 3,
                            height: 20,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            Icons.route_outlined,
                            size: 17,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'Assigned Route',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _dashIfEmpty(assignedRouteName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: muted),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _statPill(
                              icon: Icons.inventory_2_outlined,
                              label: 'Ready props',
                              value: '$readyProperties',
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statPill(
                              icon: Icons.check_circle_outline,
                              label: 'Loaded items',
                              value: '$readyItems',
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _statPill(
                              icon: Icons.hourglass_top_outlined,
                              label: 'Remaining',
                              value: '$remainingItems',
                              color: Colors.amber.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_startingTrip || readyItems <= 0)
                              ? null
                              : _startAssignedRouteTrip,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            _startingTrip ? 'Starting...' : 'Start Trip',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                children: [
                  Container(
                    width: 3,
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.list_alt_outlined,
                    size: 17,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'My Manifest',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 13, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      activeTripId != null
                          ? 'Showing cargo on your active trip.'
                          : 'Showing cargo loaded and ready for your bus.',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (routeProperties.isEmpty)
                Row(
                  children: [
                    Icon(Icons.inbox_outlined, size: 16, color: Colors.black38),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'No cargo assigned to your bus yet.',
                        style: TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                  ],
                ),

              for (final p in routeProperties)
                _manifestCard(context, p, itemSvc: itemSvc),
            ],
          );
        },
      ),
    );
  }

  Widget _gpsPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    final isError =
        _gpsStatus.toLowerCase().contains('error') ||
        _gpsStatus.toLowerCase().contains('failed') ||
        _gpsStatus.toLowerCase().contains('denied');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.gps_off : Icons.gps_fixed,
            size: 18,
            color: isError ? Colors.red : Colors.green,
          ),
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
                const SizedBox(height: 3),
                Text(
                  _lastGpsText(),
                  style: TextStyle(fontSize: 11, color: muted),
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
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              side: BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _activeTripPanel(BuildContext context) {
    final trip = TripService.getActiveTripForCurrentDriver();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    if (trip == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.30),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 16, color: muted),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'No active trip yet. Start your assigned route trip.',
                style: TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final total = trip.checkpoints.length;
    final reachedCount = (trip.lastCheckpointIndex + 1).clamp(0, total);
    final progress = total > 0 ? reachedCount / total : 0.0;
    final nextName = total == 0
        ? '—'
        : (trip.lastCheckpointIndex + 1 >= total)
        ? '— (all checkpoints reached)'
        : trip.checkpoints[trip.lastCheckpointIndex + 1].name;

    final tripBg = TripStatusColors.background(trip.status);
    final tripFg = TripStatusColors.foreground(trip.status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 3,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.directions_bus_outlined,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Active Trip',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
                StatusChip(
                  text: TripStatusLabels.text(trip.status),
                  bgColor: tripBg,
                  fgColor: tripFg,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.route_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    trip.routeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined, size: 13, color: muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    'Next: $nextName',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 6,
                      backgroundColor: AppColors.primary.withValues(
                        alpha: 0.12,
                      ),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '$reachedCount / $total',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _manifestCard(
    BuildContext context,
    Property p, {
    required PropertyItemService itemSvc,
  }) {
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

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
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _initialsAvatar(_s(p.receiverName)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _s(p.receiverName),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.place_outlined, size: 12, color: muted),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              _s(p.destination),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Icon(Icons.phone_outlined, size: 12, color: muted),
                          const SizedBox(width: 3),
                          Text(
                            _s(p.receiverPhone),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ],
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
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _countChip('${p.itemCount} total', Colors.grey.shade600),
                if (loadedReady > 0)
                  _countChip('$loadedReady loaded', Colors.green),
                if (inTransitCount > 0)
                  _countChip('$inTransitCount in transit', Colors.blue),
                if (deliveredCount > 0)
                  _countChip('$deliveredCount delivered', Colors.teal),
                if (pickedUpCount > 0)
                  _countChip('$pickedUpCount picked up', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _initialsAvatar(String fullName) {
    final parts = fullName.trim().split(' ');
    final initials = parts.length >= 2
        ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
        : fullName.isNotEmpty
        ? fullName.substring(0, fullName.length.clamp(0, 2)).toUpperCase()
        : '??';
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _statPill({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _countChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
