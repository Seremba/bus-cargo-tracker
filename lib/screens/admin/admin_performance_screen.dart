import 'package:flutter/material.dart';

import '../../models/user.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
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
    if (_rangeIndex == 0) return '7 days';
    if (_rangeIndex == 1) return '30 days';
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

  // Resolve driverId → full name
  String _resolveUser(String userId) {
    final raw = userId.trim();
    if (raw.isEmpty) return '—';
    try {
      final user =
          HiveService.userBox().values.firstWhere((u) => (u as User).id == raw)
              as User;
      final name = user.fullName.trim();
      return name.isEmpty ? raw : name;
    } catch (_) {
      return raw;
    }
  }

  static String _roleLabel(String? role) {
    if (role == null || role.trim().isEmpty) return '—';
    const map = {
      'admin': 'Admin',
      'staff': 'Staff',
      'driver': 'Driver',
      'sender': 'Sender',
      'deskCargoOfficer': 'Desk Cargo Officer',
    };
    return map[role] ?? role;
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);
    final start = _startInclusive();

    final drivers = MetricsService.topDrivers(startInclusive: start);
    final stations = MetricsService.topStations(startInclusive: start);
    final otp = MetricsService.otpAbuse(startInclusive: start);
    final avg = MetricsService.deliveryAverages(startInclusive: start);

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        elevation: 2,
        title: const Text('Performance'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Row(
                children: [
                  Icon(Icons.date_range, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Range',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: cs.onSurface,
                    ),
                  ),
                  const Spacer(),
                  // Range chips
                  _rangeChip('7 days', 0, cs),
                  const SizedBox(width: 6),
                  _rangeChip('30 days', 1, cs),
                  const SizedBox(width: 6),
                  _rangeChip('All time', 2, cs),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          _sectionTitle(
            context,
            'Top Drivers',
            Icons.local_shipping_outlined,
            cs,
          ),
          const SizedBox(height: 8),
          if (drivers.isEmpty)
            _emptyState(
              icon: Icons.local_shipping_outlined,
              message: 'No trips recorded in this range.',
              muted: muted,
            )
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < drivers.length; i++) ...[
                    _driverRow(
                      rank: i + 1,
                      name: _resolveUser(drivers[i].driverId),
                      ended: drivers[i].ended,
                      active: drivers[i].active,
                      cancelled: drivers[i].cancelled,
                      score: drivers[i].score,
                      cs: cs,
                      muted: muted,
                    ),
                    if (i < drivers.length - 1)
                      Divider(
                        height: 1,
                        indent: 52,
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),

          _sectionTitle(
            context,
            'Top Stations',
            Icons.location_on_outlined,
            cs,
          ),
          const SizedBox(height: 8),
          if (stations.isEmpty)
            _emptyState(
              icon: Icons.location_on_outlined,
              message: 'No delivered cargo in this range.',
              muted: muted,
            )
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < stations.length; i++) ...[
                    _stationRow(
                      rank: i + 1,
                      station: stations[i].station,
                      handled: stations[i].deliveredOrPickedUp,
                      pickedUp: stations[i].pickedUp,
                      cs: cs,
                      muted: muted,
                    ),
                    if (i < stations.length - 1)
                      Divider(
                        height: 1,
                        indent: 52,
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── OTP Failed Attempts (renamed from "OTP abuse leaderboard") ─
          _sectionTitle(context, 'OTP Failed Attempts', Icons.lock_outline, cs),
          const SizedBox(height: 8),
          if (otp.isEmpty)
            _emptyState(
              icon: Icons.check_circle_outline,
              message: 'No OTP failures recorded in this range.',
              muted: muted,
            )
          else
            Card(
              child: Column(
                children: [
                  for (int i = 0; i < otp.length; i++) ...[
                    _otpRow(
                      rank: i + 1,
                      name: _resolveUser(otp[i].actorUserId),
                      role: _roleLabel(otp[i].actorRole),
                      failed: otp[i].otpFailed,
                      ok: otp[i].otpOk,
                      unlocks: otp[i].adminUnlocks,
                      resets: otp[i].adminResets,
                      score: otp[i].score,
                      cs: cs,
                      muted: muted,
                    ),
                    if (i < otp.length - 1)
                      Divider(
                        height: 1,
                        indent: 52,
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                  ],
                ],
              ),
            ),

          const SizedBox(height: 16),

          _sectionTitle(
            context,
            'Delivery Time Averages',
            Icons.timer_outlined,
            cs,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _avgRow(
                  label: 'Pending → In Transit',
                  value: _fmtDuration(avg.avgPendingToTransit),
                  cs: cs,
                  muted: muted,
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                _avgRow(
                  label: 'In Transit → Delivered',
                  value: _fmtDuration(avg.avgTransitToDelivered),
                  cs: cs,
                  muted: muted,
                ),
                Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.35),
                ),
                _avgRow(
                  label: 'Delivered → Picked Up',
                  value: _fmtDuration(avg.avgDeliveredToPickup),
                  cs: cs,
                  muted: muted,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.40),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 14, color: muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'OTP Failed Attempts tracks staff_confirm_pickup_failed/ok, '
                    'admin_unlock_otp, and admin_reset_otp from the audit log.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Rang
  Widget _rangeChip(String label, int index, ColorScheme cs) {
    final selected = _rangeIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _rangeIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary
              : cs.surfaceContainerHighest.withValues(alpha: 0.40),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.50),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? cs.onPrimary : cs.onSurface,
          ),
        ),
      ),
    );
  }

  // ── Sect
  Widget _sectionTitle(
    BuildContext context,
    String text,
    IconData icon,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: cs.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
        ),
      ],
    );
  }

  // ── Empt
  Widget _emptyState({
    required IconData icon,
    required String message,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: muted),
          const SizedBox(width: 10),
          Text(message, style: TextStyle(fontSize: 13, color: muted)),
        ],
      ),
    );
  }

  // ── Driv
  Widget _driverRow({
    required int rank,
    required String name,
    required int ended,
    required int active,
    required int cancelled,
    required int score,
    required ColorScheme cs,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _rankBadge(rank, cs),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Ended: $ended  •  Active: $active  •  Cancelled: $cancelled',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          _scoreBadge(score, cs),
        ],
      ),
    );
  }

  // ── Stat
  Widget _stationRow({
    required int rank,
    required String station,
    required int handled,
    required int pickedUp,
    required ColorScheme cs,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _rankBadge(rank, cs),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Handled: $handled  •  Picked up: $pickedUp',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── OTP
  Widget _otpRow({
    required int rank,
    required String name,
    required String role,
    required int failed,
    required int ok,
    required int unlocks,
    required int resets,
    required int score,
    required ColorScheme cs,
    required Color muted,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          _rankBadge(rank, cs),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(role, style: TextStyle(fontSize: 11, color: muted)),
                const SizedBox(height: 2),
                Text(
                  'Failed: $failed  •  OK: $ok  •  Unlocks: $unlocks  •  Resets: $resets',
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          _scoreBadge(score, cs),
        ],
      ),
    );
  }

  // ── Aver
  Widget _avgRow({
    required String label,
    required String value,
    required ColorScheme cs,
    required Color muted,
  }) {
    final hasValue = value != '—';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: hasValue ? cs.primary : muted,
            ),
          ),
        ],
      ),
    );
  }

  // ── Rank
  Widget _rankBadge(int rank, ColorScheme cs) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: rank == 1
            ? const Color(0xFFFFD700).withValues(alpha: 0.20)
            : rank == 2
            ? Colors.grey.withValues(alpha: 0.15)
            : cs.surfaceContainerHighest.withValues(alpha: 0.40),
        shape: BoxShape.circle,
        border: Border.all(
          color: rank == 1
              ? const Color(0xFFFFD700)
              : rank == 2
              ? Colors.grey.shade400
              : cs.outlineVariant.withValues(alpha: 0.50),
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: rank == 1
              ? const Color(0xFFB8860B)
              : cs.onSurface.withValues(alpha: 0.70),
        ),
      ),
    );
  }

  // ── Scor
  Widget _scoreBadge(int score, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$score pts',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: cs.primary,
        ),
      ),
    );
  }
}
