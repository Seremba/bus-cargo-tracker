import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/payment_record.dart';
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
  DateTime? _start;
  DateTime? _end;
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
    final d = DateTime(dt.year, dt.month, dt.day);
    return !d.isBefore(s) && !d.isAfter(e);
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

  String _fmt(int n) {
    final s = n.abs().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return n < 0 ? '-${buf.toString()}' : buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasRole(UserRole.admin)) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final pBox = HiveService.propertyBox();
    final tBox = HiveService.tripBox();
    final aBox = HiveService.auditBox();
    final payBox = HiveService.paymentBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.55);

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
          payBox.listenable(),
        ]),
        builder: (context, _) {
          final propertiesAll = pBox.values.toList();
          final tripsAll = tBox.values.toList();
          final auditsAll = aBox.values.toList();
          final paymentsAll = payBox.values.toList();

          final properties = propertiesAll
              .where((p) => _inRange(p.createdAt))
              .toList();
          final trips = tripsAll.where((t) => _inRange(t.startedAt)).toList();
          final audits = auditsAll.where((a) => _inRange(a.at)).toList();

          // Payments in range
          final paymentsInRange = paymentsAll
              .whereType<PaymentRecord>()
              .where((x) => _inRange(x.createdAt))
              .toList();
          final totalCollected = paymentsInRange
              .where((x) => x.amount > 0)
              .fold<int>(0, (s, x) => s + x.amount);
          final totalRefunded = paymentsInRange
              .where((x) => x.amount < 0)
              .fold<int>(0, (s, x) => s + x.amount.abs());
          final totalNet = totalCollected - totalRefunded;

          int countStatus(PropertyStatus s) =>
              properties.where((p) => p.status == s).length;

          final pending = countStatus(PropertyStatus.pending);
          final loaded = countStatus(PropertyStatus.loaded);
          final inTransit = countStatus(PropertyStatus.inTransit);
          final delivered = countStatus(PropertyStatus.delivered);
          final pickedUp = countStatus(PropertyStatus.pickedUp);
          final rejected = countStatus(PropertyStatus.rejected);
          final expired = countStatus(PropertyStatus.expired); // F5

          int deliveredInRange() => propertiesAll.where((p) {
            final at = p.deliveredAt;
            return at != null && _inRange(at);
          }).length;

          int pickedUpInRange() => propertiesAll.where((p) {
            final at = p.pickedUpAt;
            return at != null && _inRange(at);
          }).length;

          final otpLockedCount = propertiesAll.where((p) {
            if (p.status != PropertyStatus.delivered) return false;
            return PropertyService.isOtpLocked(p) &&
                _inRange(p.deliveredAt ?? p.createdAt);
          }).length;

          final otpExpiredCount = propertiesAll.where((p) {
            if (p.status != PropertyStatus.delivered) return false;
            return PropertyService.isOtpExpired(p) &&
                _inRange(p.deliveredAt ?? p.createdAt);
          }).length;

          final hasOtpIssues = otpLockedCount > 0 || otpExpiredCount > 0;
          final hasTerminalIssues = rejected > 0 || expired > 0;

          int tripCount(TripStatus s) =>
              trips.where((t) => t.status == s).length;

          final activeTrips = tripCount(TripStatus.active);
          final endedTrips = tripCount(TripStatus.ended);
          final cancelledTrips = tripCount(TripStatus.cancelled);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              _rangeHeader(),
              const SizedBox(height: 14),

              _sectionTitle(context, 'Summary', Icons.summarize_outlined, cs),
              const SizedBox(height: 8),
              _kpiRow([
                _kpi(
                  label: 'Properties',
                  value: _fmt(properties.length),
                  color: cs.primary,
                  bg: cs.primary.withValues(alpha: 0.08),
                ),
                _kpi(
                  label: 'Delivered',
                  value: _fmt(deliveredInRange()),
                  color: Colors.green.shade700,
                  bg: Colors.green.withValues(alpha: 0.08),
                ),
                _kpi(
                  label: 'Picked up',
                  value: _fmt(pickedUpInRange()),
                  color: Colors.teal.shade700,
                  bg: Colors.teal.withValues(alpha: 0.08),
                ),
              ]),

              const SizedBox(height: 16),

              _sectionTitle(context, 'Finance', Icons.payments_outlined, cs),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      _financeRow(
                        label: 'Collected',
                        value: 'UGX ${_fmt(totalCollected)}',
                        color: Colors.green.shade700,
                        muted: muted,
                      ),
                      if (totalRefunded > 0) ...[
                        const SizedBox(height: 6),
                        _financeRow(
                          label: 'Refunded',
                          value: 'UGX ${_fmt(totalRefunded)}',
                          color: Colors.red.shade600,
                          muted: muted,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Divider(
                        height: 1,
                        color: cs.outlineVariant.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Net',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'UGX ${_fmt(totalNet)}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '${paymentsInRange.length} payment record${paymentsInRange.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: muted),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              _sectionTitle(
                context,
                'Property status',
                Icons.inventory_2_outlined,
                cs,
              ),
              const SizedBox(height: 4),
              Text(
                'By created date in range',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 8),

              // Row 1: pending / loaded / in-transit
              _kpiRow([
                _kpi(
                  label: 'Pending',
                  value: _fmt(pending),
                  color: const Color(0xFFF57F17),
                  bg: const Color(0xFFFFF8E1),
                ),
                _kpi(
                  label: 'Loaded',
                  value: _fmt(loaded),
                  color: const Color(0xFFE65100),
                  bg: const Color(0xFFFFF3E0),
                ),
                _kpi(
                  label: 'In Transit',
                  value: _fmt(inTransit),
                  color: const Color(0xFF1565C0),
                  bg: const Color(0xFFE3F2FD),
                ),
              ]),
              const SizedBox(height: 8),

              // Row 2: delivered / picked-up + spacer
              _kpiRow([
                _kpi(
                  label: 'Delivered',
                  value: _fmt(delivered),
                  color: Colors.green.shade700,
                  bg: Colors.green.withValues(alpha: 0.08),
                ),
                _kpi(
                  label: 'Picked Up',
                  value: _fmt(pickedUp),
                  color: Colors.teal.shade700,
                  bg: Colors.teal.withValues(alpha: 0.08),
                ),
                const Expanded(child: SizedBox()),
              ]),

              // Row 3 (F5): rejected / expired — only shown when non-zero
              if (hasTerminalIssues) ...[
                const SizedBox(height: 8),
                _kpiRow([
                  if (rejected > 0)
                    _kpi(
                      label: 'Rejected',
                      value: _fmt(rejected),
                      color: const Color(0xFFC62828),
                      bg: const Color(0xFFFFEBEE),
                    ),
                  if (rejected > 0 && expired > 0) const SizedBox(width: 8),
                  if (expired > 0)
                    _kpi(
                      label: 'Expired',
                      value: _fmt(expired),
                      color: const Color(0xFF4E342E),
                      bg: const Color(0xFFEFEBE9),
                    ),
                  // Spacer to fill the third column if only one tile is shown
                  if (rejected == 0 || expired == 0)
                    const Expanded(child: SizedBox()),
                ]),
              ],

              // OTP issues — only shown when non-zero
              if (hasOtpIssues) ...[
                const SizedBox(height: 8),
                _kpiRow([
                  _kpi(
                    label: 'OTP locked',
                    value: _fmt(otpLockedCount),
                    color: Colors.red.shade600,
                    bg: Colors.red.withValues(alpha: 0.08),
                  ),
                  _kpi(
                    label: 'OTP expired',
                    value: _fmt(otpExpiredCount),
                    color: Colors.orange.shade700,
                    bg: Colors.orange.withValues(alpha: 0.08),
                  ),
                  const Expanded(child: SizedBox()),
                ]),
              ],

              const SizedBox(height: 16),

              _sectionTitle(
                context,
                'Trips',
                Icons.local_shipping_outlined,
                cs,
              ),
              const SizedBox(height: 4),
              Text(
                'By started date in range',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 8),
              _kpiRow([
                _kpi(
                  label: 'Active',
                  value: _fmt(activeTrips),
                  color: Colors.green.shade700,
                  bg: Colors.green.withValues(alpha: 0.08),
                ),
                _kpi(
                  label: 'Ended',
                  value: _fmt(endedTrips),
                  color: muted,
                  bg: cs.surfaceContainerHighest.withValues(alpha: 0.35),
                ),
                _kpi(
                  label: 'Cancelled',
                  value: _fmt(cancelledTrips),
                  color: Colors.red.shade600,
                  bg: Colors.red.withValues(alpha: 0.08),
                ),
              ]),

              const SizedBox(height: 16),

              _sectionTitle(context, 'Audit', Icons.history_outlined, cs),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_outlined, color: muted, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Audit events in range',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              _rangeLabel(),
                              style: TextStyle(fontSize: 12, color: muted),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _fmt(audits.length),
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                          color: cs.primary,
                        ),
                      ),
                    ],
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
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.date_range, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Date range',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _rangeLabel(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),

            Row(
              children: [
                _expandedChip('Today', _QuickRange.today, cs),
                const SizedBox(width: 6),
                _expandedChip('7 days', _QuickRange.last7Days, cs),
                const SizedBox(width: 6),
                _expandedChip('30 days', _QuickRange.last30Days, cs),
                const SizedBox(width: 6),
                _expandedChip('Custom', _QuickRange.custom, cs, isAction: true),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _expandedChip(
    String label,
    _QuickRange range,
    ColorScheme cs, {
    bool isAction = false,
  }) {
    final selected = _quick == range;
    return Expanded(
      child: GestureDetector(
        onTap: () => isAction ? _pickCustomRange() : _applyQuick(range),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
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
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? cs.onPrimary : cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(
    BuildContext context,
    String text,
    IconData icon,
    ColorScheme cs,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
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
      ),
    );
  }

  Widget _financeRow({
    required String label,
    required String value,
    required Color color,
    required Color muted,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: muted)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _kpi({
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kpiRow(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          children[i],
          if (i != children.length - 1) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

enum _QuickRange { today, last7Days, last30Days, custom }
