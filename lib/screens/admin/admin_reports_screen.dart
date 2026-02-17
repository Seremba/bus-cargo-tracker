import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property_status.dart';
import '../../models/trip_status.dart';

import '../../services/hive_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';
import '../../models/user_role.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  DateTime? _start; // inclusive
  DateTime? _end; // inclusive
  _QuickRange _quick = _QuickRange.last7Days;

  @override
  void initState() {
    super.initState();
    _applyQuick(_quick);
  }

  void _applyQuick(_QuickRange r) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);

    if (r == _QuickRange.today) {
      _start = todayStart;
      _end = todayStart;
    } else if (r == _QuickRange.last7Days) {
      _start = todayStart.subtract(const Duration(days: 6));
      _end = todayStart;
    } else if (r == _QuickRange.last30Days) {
      _start = todayStart.subtract(const Duration(days: 29));
      _end = todayStart;
    }

    setState(() => _quick = r);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _start ?? DateTime(now.year, now.month, now.day);
    final initialEnd = _end ?? initialStart;

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
    );

    if (picked == null) return;

    // normalize to date-only (midnight)
    final s = DateTime(picked.start.year, picked.start.month, picked.start.day);
    final e = DateTime(picked.end.year, picked.end.month, picked.end.day);

    setState(() {
      _start = s;
      _end = e;
      _quick = _QuickRange.custom;
    });
  }

  bool _inRange(DateTime dt) {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return true;

    // compare by date only
    final d = DateTime(dt.year, dt.month, dt.day);
    return !d.isBefore(s) && !d.isAfter(e);
    // inclusive
  }

  String _rangeLabel() {
    final s = _start;
    final e = _end;
    if (s == null || e == null) return 'All time';

    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    if (s.year == e.year && s.month == e.month && s.day == e.day) {
      return fmt(s);
    }
    return '${fmt(s)} → ${fmt(e)}';
  }

  @override
  Widget build(BuildContext context) {
    // ✅ UI guard (admin only)
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final pBox = HiveService.propertyBox();
    final tBox = HiveService.tripBox();
    final aBox = HiveService.auditBox();

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Custom date range',
            icon: const Icon(Icons.date_range),
            onPressed: _pickCustomRange,
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          pBox.listenable(),
          tBox.listenable(),
          aBox.listenable(),
        ]),
        builder: (context, _) {
          final propertiesAll = pBox.values.toList();
          final tripsAll = tBox.values.toList();
          final auditsAll = aBox.values.toList();

          final properties = propertiesAll.where((p) => _inRange(p.createdAt)).toList();
          final trips = tripsAll.where((t) => _inRange(t.startedAt)).toList();
          final audits = auditsAll.where((a) => _inRange(a.at)).toList();

          int countStatus(PropertyStatus s) =>
              properties.where((p) => p.status == s).length;

          final pending = countStatus(PropertyStatus.pending);
          final inTransit = countStatus(PropertyStatus.inTransit);
          final delivered = countStatus(PropertyStatus.delivered);
          final pickedUp = countStatus(PropertyStatus.pickedUp);

          // Delivered/Picked in-range based on timestamps (more accurate than createdAt)
          int deliveredInRange() => propertiesAll.where((p) {
                final at = p.deliveredAt;
                return at != null && _inRange(at);
              }).length;

          int pickedUpInRange() => propertiesAll.where((p) {
                final at = p.pickedUpAt;
                return at != null && _inRange(at);
              }).length;

          final otpLockedCount = propertiesAll.where((p) {
            // Only meaningful when waiting pickup
            if (p.status != PropertyStatus.delivered) return false;
            return PropertyService.isOtpLocked(p) && _inRange(p.deliveredAt ?? p.createdAt);
          }).length;

          final otpExpiredCount = propertiesAll.where((p) {
            if (p.status != PropertyStatus.delivered) return false;
            return PropertyService.isOtpExpired(p) && _inRange(p.deliveredAt ?? p.createdAt);
          }).length;

          int tripCount(TripStatus s) => trips.where((t) => t.status == s).length;

          final activeTrips = tripCount(TripStatus.active);
          final endedTrips = tripCount(TripStatus.ended);
          final cancelledTrips = tripCount(TripStatus.cancelled);

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _rangeHeader(),
              const SizedBox(height: 10),

              _kpiRow([
                _kpi('Properties', properties.length.toString()),
                _kpi('Delivered', deliveredInRange().toString()),
                _kpi('Picked up', pickedUpInRange().toString()),
              ]),
              const SizedBox(height: 10),

              _sectionTitle('Property status (by created date in range)'),
              const SizedBox(height: 8),
              _kpiRow([
                _kpi('Pending', pending.toString()),
                _kpi('In Transit', inTransit.toString()),
                _kpi('Delivered', delivered.toString()),
              ]),
              const SizedBox(height: 8),
              _kpiRow([
                _kpi('Picked Up', pickedUp.toString()),
                _kpi('OTP locked', otpLockedCount.toString()),
                _kpi('OTP expired', otpExpiredCount.toString()),
              ]),

              const SizedBox(height: 16),
              _sectionTitle('Trips (by started date in range)'),
              const SizedBox(height: 8),
              _kpiRow([
                _kpi('Active', activeTrips.toString()),
                _kpi('Ended', endedTrips.toString()),
                _kpi('Cancelled', cancelledTrips.toString()),
              ]),

              const SizedBox(height: 16),
              _sectionTitle('Audit'),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  title: const Text('Audit events in range'),
                  subtitle: Text('Range: ${_rangeLabel()}'),
                  trailing: Text(
                    audits.length.toString(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _rangeHeader() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Date range',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(_rangeLabel(), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Today'),
                  selected: _quick == _QuickRange.today,
                  onSelected: (_) => _applyQuick(_QuickRange.today),
                ),
                ChoiceChip(
                  label: const Text('Last 7 days'),
                  selected: _quick == _QuickRange.last7Days,
                  onSelected: (_) => _applyQuick(_QuickRange.last7Days),
                ),
                ChoiceChip(
                  label: const Text('Last 30 days'),
                  selected: _quick == _QuickRange.last30Days,
                  onSelected: (_) => _applyQuick(_QuickRange.last30Days),
                ),
                ActionChip(
                  label: const Text('Custom…'),
                  onPressed: _pickCustomRange,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );

  Widget _kpi(String label, String value) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 6),
              Text(
                value,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kpiRow(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }
}

enum _QuickRange { today, last7Days, last30Days, custom }
