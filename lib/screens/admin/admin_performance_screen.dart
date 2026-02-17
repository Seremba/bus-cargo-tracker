import 'package:flutter/material.dart';

import '../../models/user_role.dart';
import '../../services/metrics_service.dart';
import '../../services/role_guard.dart';

class AdminPerformanceScreen extends StatefulWidget {
  const AdminPerformanceScreen({super.key});

  @override
  State<AdminPerformanceScreen> createState() => _AdminPerformanceScreenState();
}

class _AdminPerformanceScreenState extends State<AdminPerformanceScreen> {
  // 0=7d, 1=30d, 2=all
  int _rangeIndex = 1;

  DateTime? _startInclusive() {
    final now = DateTime.now();
    if (_rangeIndex == 0) return now.subtract(const Duration(days: 7));
    if (_rangeIndex == 1) return now.subtract(const Duration(days: 30));
    return null;
  }

  String _rangeLabel() {
    if (_rangeIndex == 0) return 'Last 7 days';
    if (_rangeIndex == 1) return 'Last 30 days';
    return 'All time';
  }

  String _fmtDuration(Duration? d) {
    if (d == null) return '—';
    final mins = d.inMinutes;
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    // UI Guard (Admin only)
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final start = _startInclusive();

    final drivers = MetricsService.topDrivers(startInclusive: start);
    final stations = MetricsService.topStations(startInclusive: start);
    final otp = MetricsService.otpAbuse(startInclusive: start); // ✅ now audit-based
    final avg = MetricsService.deliveryAverages(startInclusive: start);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Performance Metrics'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Range filter
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.date_range, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Range: ${_rangeLabel()}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _rangeIndex,
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Last 7 days')),
                      DropdownMenuItem(value: 1, child: Text('Last 30 days')),
                      DropdownMenuItem(value: 2, child: Text('All time')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _rangeIndex = v);
                    },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Top drivers
          _sectionTitle('Top drivers'),
          if (drivers.isEmpty)
            _emptyHint('No trips yet in this range.')
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < drivers.length; i++)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text('Driver: ${drivers[i].driverId}'),
                      subtitle: Text(
                        'Ended: ${drivers[i].ended} • Active: ${drivers[i].active} • Cancelled: ${drivers[i].cancelled}',
                      ),
                      trailing: Text(
                        'Score: ${drivers[i].score}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Top stations
          _sectionTitle('Top stations'),
          if (stations.isEmpty)
            _emptyHint('No delivered cargo yet in this range.')
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < stations.length; i++)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(stations[i].station),
                      subtitle: Text(
                        'Handled (Delivered/Picked): ${stations[i].deliveredOrPickedUp} • Picked up: ${stations[i].pickedUp}',
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // ✅ OTP abuse leaderboard (audit-based)
          _sectionTitle('OTP abuse leaderboard'),
          if (otp.isEmpty)
            _emptyHint('No OTP audit activity found in this range.')
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < otp.length; i++)
                    ListTile(
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text('Actor: ${otp[i].actorUserId}'),
                      subtitle: Text(
                        'Role: ${otp[i].actorRole}'
                        ' • Failed: ${otp[i].otpFailed}'
                        ' • OK: ${otp[i].otpOk}'
                        ' • Unlocks: ${otp[i].adminUnlocks}'
                        ' • Resets: ${otp[i].adminResets}',
                      ),
                      trailing: Text(
                        'Score: ${otp[i].score}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 12),

          // Delivery averages
          _sectionTitle('Delivery time averages'),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: const Text('Pending → In Transit'),
                  trailing: Text(_fmtDuration(avg.avgPendingToTransit)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('In Transit → Delivered'),
                  trailing: Text(_fmtDuration(avg.avgTransitToDelivered)),
                ),
                const Divider(height: 1),
                ListTile(
                  title: const Text('Delivered → Picked Up'),
                  trailing: Text(_fmtDuration(avg.avgDeliveredToPickup)),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),
          _emptyHint(
            'Tip: OTP leaderboard uses AuditEvent logs (staff_confirm_pickup_failed/ok, admin_unlock_otp, admin_reset_otp).',
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _emptyHint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(text, style: const TextStyle(color: Colors.black54)),
      );
}
