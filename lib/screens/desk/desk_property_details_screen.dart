import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/payment_record.dart';
import '../../models/property.dart';
import '../../models/property_item_status.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../services/hive_service.dart';
import '../../services/payment_service.dart';
import '../../services/printing/escpos_label_builder.dart';
import '../../services/printing/printer_service.dart';
import '../../services/printing/printer_settings_service.dart';
import '../../services/property_item_service.dart';
import '../../services/property_qr_service.dart';
import '../../services/property_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';

import '../../theme/status_colors.dart';
import '../../ui/status_labels.dart';
import '../../widgets/status_chip.dart';
import '../desk/desk_record_payment_screen.dart';

class DeskPropertyDetailsScreen extends StatefulWidget {
  final String scannedCode;

  const DeskPropertyDetailsScreen({super.key, required this.scannedCode});

  @override
  State<DeskPropertyDetailsScreen> createState() =>
      _DeskPropertyDetailsScreenState();
}

class _DeskPropertyDetailsScreenState
    extends State<DeskPropertyDetailsScreen> {
  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    final s = d.toLocal().toString();
    return s.length >= 16 ? s.substring(0, 16) : s;
  }

  Property? _findByCode(String code) {
    final box = HiveService.propertyBox();
    final normalized =
        PropertyQrService.decodeToPropertyCode(code)?.trim().toLowerCase() ??
        '';
    if (normalized.isEmpty) return null;
    for (final p in box.values) {
      if (p.propertyCode.trim().toLowerCase() == normalized) return p;
    }
    final key = int.tryParse(normalized);
    if (key != null) return box.get(key);
    return null;
  }

  Future<int?> _askCopiesPerItem(BuildContext context) async {
    final controller = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Copies per item'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'e.g. 1, 2, 3...'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                if (v == null || v <= 0 || v > 20) {
                  Navigator.pop(ctx, 1);
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<List<int>?> _pickItemNumbersToLoad({
    required BuildContext context,
    required Property p,
  }) async {
    final itemBox = HiveService.propertyItemBox();
    final itemSvc = PropertyItemService(itemBox);

    await itemSvc.ensureItemsForProperty(
      propertyKey: p.key.toString(),
      trackingCode: p.trackingCode,
      itemCount: p.itemCount,
    );

    final all = itemSvc.getItemsForProperty(p.key.toString());
    final selectable =
        all.where((x) => x.status == PropertyItemStatus.pending).toList()
          ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

    if (selectable.isEmpty) return null;
    if (!context.mounted) return null;

    final selected = <int>{for (final x in selectable) x.itemNo};

    return showDialog<List<int>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Select items to load today'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        TextButton(
                          onPressed: () {
                            setDialogState(() {
                              selected
                                ..clear()
                                ..addAll(selectable.map((e) => e.itemNo));
                            });
                          },
                          child: const Text('Select all'),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () =>
                              setDialogState(() => selected.clear()),
                          child: const Text('Clear'),
                        ),
                        const Spacer(),
                        Text(
                          '${selected.length}/${selectable.length}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Divider(),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: selectable.length,
                        itemBuilder: (ctx2, i) {
                          final item = selectable[i];
                          final isChecked = selected.contains(item.itemNo);
                          return CheckboxListTile(
                            dense: true,
                            value: isChecked,
                            title: Text('Item ${item.itemNo}'),
                            onChanged: (v) {
                              setDialogState(() {
                                if (v == true) {
                                  selected.add(item.itemNo);
                                } else {
                                  selected.remove(item.itemNo);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (selected.isEmpty) {
                      Navigator.pop(ctx);
                      return;
                    }
                    final list = selected.toList()..sort();
                    Navigator.pop(ctx, list);
                  },
                  child: const Text('Load selected'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ── F1: Reject dialog ──────────────────────────────────────────────────
  Future<void> _showRejectDialog(BuildContext context, Property p) async {
    String selectedCategory = PropertyService.rejectionCategories.first;
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.red),
                  SizedBox(width: 8),
                  Text('Reject Property'),
                ],
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'The physical items do not match the sender\'s '
                        'declaration. Select a reason and confirm.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'Rejection reason',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        items: PropertyService.rejectionCategories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text(
                                  PropertyService.rejectionCategoryLabel(c),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v == null) return;
                          setDialogState(() => selectedCategory = v);
                        },
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Additional details (optional)',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: reasonController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText:
                              'e.g. "Declared 10 boxes, only 7 presented"',
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.all(12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Confirm Rejection'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!context.mounted || confirmed != true) return;

    final ok = await PropertyService.rejectProperty(
      p,
      category: selectedCategory,
      reason: reasonController.text.trim(),
    );

    reasonController.dispose();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Property rejected ✅ — sender notified' : 'Cannot reject ❌',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Property Details')),
      body: AnimatedBuilder(
        animation: Listenable.merge([
          HiveService.propertyBox().listenable(),
          HiveService.paymentBox().listenable(),
          HiveService.propertyItemBox().listenable(),
        ]),
        builder: (context, _) {
          final p = _findByCode(widget.scannedCode);

          if (p == null) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Property not found for code:\n\n${widget.scannedCode}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            );
          }

          final code = p.propertyCode.trim().isEmpty
              ? p.key.toString()
              : p.propertyCode.trim();

          final bg = PropertyStatusColors.background(p.status);
          final fg = PropertyStatusColors.foreground(p.status);

          // Only pending/loaded can be loaded or rejected.
          // underReview, expired, rejected block desk actions.
          final isActionable =
              p.status == PropertyStatus.pending ||
              p.status == PropertyStatus.loaded;

          final canLoad    = isActionable;
          final canReject  = isActionable;

          final payments = PaymentService.getPaymentsForProperty(
            p.key.toString(),
          );
          final isPaid = PaymentService.hasValidPaymentForProperty(
            p.key.toString(),
          );
          final PaymentRecord? latestPayment =
              payments.isEmpty ? null : payments.first;

          final itemSvc = PropertyItemService(HiveService.propertyItemBox());
          final items = itemSvc.getItemsForProperty(p.key.toString());

          final loadedNotAssigned = items
              .where(
                (x) =>
                    x.status == PropertyItemStatus.loaded &&
                    x.tripId.trim().isEmpty,
              )
              .length;

          final remainingPending = items
              .where((x) => x.status == PropertyItemStatus.pending)
              .length;

          final canMarkLoadedNow = isPaid && canLoad && remainingPending > 0;

          // Determine what the payment button should do
          final bool paymentButtonEnabled =
              !isPaid && isActionable;

          return FutureBuilder<void>(
            future: itemSvc.ensureItemsForProperty(
              propertyKey: p.key.toString(),
              trackingCode: p.trackingCode,
              itemCount: p.itemCount,
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting &&
                  items.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Failed to prepare item records: ${snap.error}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [

                  // ── Status banners ──────────────────────────────────
                  if (p.status == PropertyStatus.rejected) ...[
                    _statusBanner(
                      icon: Icons.cancel_outlined,
                      color: Colors.red,
                      title: 'Rejected',
                      lines: [
                        if ((p.rejectionCategory ?? '').isNotEmpty)
                          'Reason: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory!)}',
                        if ((p.rejectionReason ?? '').trim().isNotEmpty)
                          'Details: ${p.rejectionReason!.trim()}',
                        if (p.rejectedAt != null)
                          'Rejected at: ${_fmt16(p.rejectedAt)}',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (p.status == PropertyStatus.underReview) ...[
                    _statusBanner(
                      icon: Icons.manage_search_outlined,
                      color: const Color(0xFFFF8F00),
                      title: 'Under Review',
                      lines: const [
                        'Sender has submitted a re-review request.',
                        'Admin must approve before this property can be loaded.',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (p.status == PropertyStatus.expired) ...[
                    _statusBanner(
                      icon: Icons.timer_off_outlined,
                      color: const Color(0xFF4E342E),
                      title: 'Expired',
                      lines: const [
                        'No payment was recorded within 10 days.',
                        'Admin must restore to Pending before this can proceed.',
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Main info card ──────────────────────────────────
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Code: $code',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              StatusChip(
                                text: PropertyStatusLabels.text(p.status),
                                bgColor: bg,
                                fgColor: fg,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _infoRow(Icons.person_outline,      'Receiver',    p.receiverName),
                          _infoRow(Icons.phone_outlined,      'Phone',       p.receiverPhone),
                          _infoRow(Icons.place_outlined,      'Destination', p.destination),
                          _infoRow(Icons.route_outlined,      'Route',       p.routeName.trim().isEmpty ? '—' : p.routeName),
                          _infoRow(Icons.inventory_2_outlined, 'Description', p.description.trim().isEmpty ? '—' : p.description.trim()),
                          _infoRow(Icons.numbers_outlined,    'Items',       p.itemCount.toString()),

                          const SizedBox(height: 12),

                          // Payment status block
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isPaid
                                  ? Colors.green.withValues(alpha: 0.08)
                                  : Colors.orange.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isPaid
                                    ? Colors.green.withValues(alpha: 0.25)
                                    : Colors.orange.withValues(alpha: 0.30),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(
                                    isPaid
                                        ? Icons.check_circle_outline
                                        : Icons.payments_outlined,
                                    size: 16,
                                    color: isPaid ? Colors.green : Colors.orange,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    isPaid
                                        ? 'Payment recorded ✅'
                                        : 'Payment not yet recorded',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                ]),
                                const SizedBox(height: 6),
                                Text(
                                  'Total: '
                                  '${p.currency.trim().isEmpty ? 'UGX' : p.currency} '
                                  '${p.amountPaidTotal}',
                                ),
                                if (latestPayment != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last: '
                                    '${latestPayment.method.trim().isEmpty ? '—' : latestPayment.method.trim()}'
                                    ' • ${_fmt16(latestPayment.createdAt)}',
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Item load status block
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: 0.60),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: cs.onSurface.withValues(alpha: 0.08)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _infoRow(
                                  Icons.local_shipping_outlined,
                                  'Loaded (not on trip)',
                                  '$loadedNotAssigned / ${p.itemCount}',
                                ),
                                const SizedBox(height: 4),
                                _infoRow(
                                  Icons.pending_actions_outlined,
                                  'Remaining at station',
                                  '$remainingPending / ${p.itemCount}',
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),
                          Text('Created: ${_fmt16(p.createdAt)}',
                              style: TextStyle(fontSize: 12, color: muted)),
                          if (p.loadedAt != null)
                            Text('Loaded: ${_fmt16(p.loadedAt)}',
                                style: TextStyle(fontSize: 12, color: muted)),
                          if (p.inTransitAt != null)
                            Text('In transit: ${_fmt16(p.inTransitAt)}',
                                style: TextStyle(fontSize: 12, color: muted)),
                          if (p.deliveredAt != null)
                            Text('Delivered: ${_fmt16(p.deliveredAt)}',
                                style: TextStyle(fontSize: 12, color: muted)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Record Payment — navigates to DeskRecordPaymentScreen
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(isPaid
                          ? 'Payment Recorded ✅'
                          : !isActionable
                          ? 'Payment unavailable'
                          : 'Record Payment'),
                      onPressed: paymentButtonEnabled
                          ? () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DeskRecordPaymentScreen(
                                    property: p,
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Mark Loaded ────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.local_shipping),
                      label: Text(
                        !isActionable
                            ? 'Loading unavailable'
                            : !isPaid
                            ? 'Record payment first'
                            : canMarkLoadedNow
                            ? 'Mark Loaded (Select items)'
                            : remainingPending == 0
                            ? 'All items loaded ✅'
                            : 'Cannot load now',
                      ),
                      onPressed: (!isPaid && remainingPending > 0)
                          ? () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Record payment first before loading cargo',
                                  ),
                                ),
                              );
                            }
                          : !canMarkLoadedNow
                          ? null
                          : () async {
                              final ctx = context;
                              final st =
                                  (Session.currentStationName ?? '').trim();

                              if (st.isEmpty) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('No station set ❌'),
                                  ),
                                );
                                return;
                              }

                              final selectedNos =
                                  await _pickItemNumbersToLoad(
                                context: ctx,
                                p: p,
                              );

                              if (!ctx.mounted) return;
                              if (selectedNos == null ||
                                  selectedNos.isEmpty) { return; }

                              final ok = await PropertyService.markLoaded(
                                p,
                                station: st,
                                itemNos: selectedNos,
                              );

                              if (!ctx.mounted) return;
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    ok
                                        ? 'Marked Loaded ✅ (${selectedNos.length} item(s))'
                                        : 'Cannot mark loaded ❌',
                                  ),
                                ),
                              );
                            },
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Reject button ──────────────────────────────────
                  if (canReject) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined,
                            color: Colors.red),
                        label: const Text('Reject Property',
                            style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => _showRejectDialog(context, p),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Print labels ───────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('Print Item Labels (Thermal)'),
                      onPressed: () async {
                        final ctx = context;
                        try {
                          final connected =
                              await PrinterService.ensureConnectedFromSaved();

                          if (!ctx.mounted) return;

                          if (!connected) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No saved printer. Please set up a printer first.',
                                ),
                              ),
                            );
                            return;
                          }

                          final copies = await _askCopiesPerItem(ctx);
                          if (!ctx.mounted) return;
                          if (copies == null) return;

                          final localItemSvc = PropertyItemService(
                            HiveService.propertyItemBox(),
                          );
                          await localItemSvc.ensureItemsForProperty(
                            propertyKey: p.key.toString(),
                            trackingCode: p.trackingCode,
                            itemCount: p.itemCount,
                          );

                          final all = localItemSvc.getItemsForProperty(
                            p.key.toString(),
                          );

                          final toPrint = all
                              .where(
                                (x) =>
                                    x.status == PropertyItemStatus.loaded &&
                                    x.tripId.trim().isEmpty,
                              )
                              .toList()
                            ..sort(
                                (a, b) => a.itemNo.compareTo(b.itemNo));

                          if (!ctx.mounted) return;

                          if (toPrint.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No LOADED items to print. Mark items loaded first.',
                                ),
                              ),
                            );
                            return;
                          }

                          final paperMm =
                              PrinterSettingsService.getOrCreate().paperMm;

                          for (final item in toPrint) {
                            final bytes =
                                await EscPosLabelBuilder.buildItemLabel(
                              p: p,
                              item: item,
                              paperMm: paperMm,
                            );

                            for (int i = 0; i < copies; i++) {
                              final ok =
                                  await PrinterService.printBytesBluetooth(
                                bytes,
                              );

                              if (!ctx.mounted) return;

                              if (!ok) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Print failed on item ${item.itemNo}/${p.itemCount}',
                                    ),
                                  ),
                                );
                                return;
                              }
                            }
                          }

                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Printed ${toPrint.length} item label(s) x $copies ✅',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text('Print error: $e')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: Colors.grey)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner({
    required IconData icon,
    required Color color,
    required String title,
    required List<String> lines,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 6),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontSize: 14)),
          ]),
          if (lines.isNotEmpty) ...[
            const SizedBox(height: 6),
            for (final l in lines)
              Text(l, style: const TextStyle(fontSize: 13)),
          ],
        ],
      ),
    );
  }
}