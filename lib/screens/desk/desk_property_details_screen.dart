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

  Property? _findByCode(Box box, String code) {
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

    final selected = <int>{for (final x in selectable) x.itemNo};

    if (!context.mounted) return null;

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
                          onPressed: () {
                            setDialogState(() => selected.clear());
                          },
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

  // ── F1: Reject dialog ─────────────────────────────────────────────────────
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
              content: SingleChildScrollView(
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
                      value: selectedCategory,
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
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _recordPaymentDialog(BuildContext context, Property p) async {
    final station = (Session.currentStationName ?? '').trim();

    if (station.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No station set for this user ❌')),
      );
      return;
    }

    final amountController = TextEditingController(
      text: p.amountPaidTotal > 0 ? p.amountPaidTotal.toString() : '',
    );
    final txnRefController = TextEditingController(text: p.lastTxnRef);

    String method = p.lastPaymentMethod.trim().isEmpty
        ? 'cash'
        : p.lastPaymentMethod.trim();

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return AlertDialog(
              title: const Text('Record Payment'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Amount',
                        hintText: 'Enter amount paid',
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      value: method,
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Cash')),
                        DropdownMenuItem(
                          value: 'mobile money',
                          child: Text('Mobile Money'),
                        ),
                        DropdownMenuItem(value: 'bank', child: Text('Bank')),
                        DropdownMenuItem(value: 'other', child: Text('Other')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => method = v);
                      },
                      decoration: const InputDecoration(labelText: 'Method'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: txnRefController,
                      decoration: const InputDecoration(
                        labelText: 'Transaction reference (optional)',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(dialogCtx, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!context.mounted || result != true) return;

    final amount = int.tryParse(amountController.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    try {
      await PaymentService.recordPayment(
        property: p,
        amount: amount,
        method: method,
        txnRef: txnRefController.text.trim(),
        station: station,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment recorded ✅')),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.propertyBox();
    final cs = Theme.of(context).colorScheme;
    final muted = cs.onSurface.withValues(alpha: 0.60);

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Scanned Property')),
      body: ValueListenableBuilder(
        valueListenable: box.listenable(),
        builder: (context, Box<Property> b, _) {
          final p = _findByCode(b, widget.scannedCode);

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

          final canLoad =
              p.status == PropertyStatus.pending ||
              p.status == PropertyStatus.loaded;

          // F1: can reject if pending or loaded (not yet in transit)
          final canReject =
              p.status == PropertyStatus.pending ||
              p.status == PropertyStatus.loaded;

          return FutureBuilder<void>(
            future: () async {
              final itemBox = HiveService.propertyItemBox();
              final itemSvc = PropertyItemService(itemBox);
              await itemSvc.ensureItemsForProperty(
                propertyKey: p.key.toString(),
                trackingCode: p.trackingCode,
                itemCount: p.itemCount,
              );
            }(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
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

              final itemBox = HiveService.propertyItemBox();
              final itemSvc = PropertyItemService(itemBox);
              final items = itemSvc.getItemsForProperty(p.key.toString());

              final payments = PaymentService.getPaymentsForProperty(
                p.key.toString(),
              );
              final isPaid = PaymentService.hasValidPaymentForProperty(
                p.key.toString(),
              );
              final PaymentRecord? latestPayment =
                  payments.isEmpty ? null : payments.first;

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

              final canMarkLoadedNow =
                  isPaid && canLoad && remainingPending > 0;

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // ── F1: Rejection banner ──────────────────────────────
                  if (p.status == PropertyStatus.rejected) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.cancel_outlined,
                                color: Colors.red,
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Rejected',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.red,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if ((p.rejectionCategory ?? '').isNotEmpty)
                            Text(
                              'Reason: ${PropertyService.rejectionCategoryLabel(p.rejectionCategory!)}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          if ((p.rejectionReason ?? '').trim().isNotEmpty)
                            Text(
                              'Details: ${p.rejectionReason!.trim()}',
                              style: const TextStyle(fontSize: 13),
                            ),
                          if (p.rejectedAt != null)
                            Text(
                              'Rejected at: ${_fmt16(p.rejectedAt)}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  // ─────────────────────────────────────────────────────

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
                          Text('Receiver: ${p.receiverName}'),
                          Text('Phone: ${p.receiverPhone}'),
                          Text('Destination: ${p.destination}'),
                          Text('Items: ${p.itemCount}'),

                          const SizedBox(height: 12),
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
                                Text(
                                  isPaid
                                      ? 'Payment: Recorded ✅'
                                      : 'Payment: Not yet recorded',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Amount paid total: '
                                  '${p.currency.trim().isEmpty ? 'UGX' : p.currency} '
                                  '${p.amountPaidTotal}',
                                ),
                                if (latestPayment != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Last payment: '
                                    '${latestPayment.method.trim().isEmpty ? '—' : latestPayment.method.trim()}'
                                    ' • ${_fmt16(latestPayment.createdAt)}',
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withValues(
                                alpha: 0.60,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cs.onSurface.withValues(alpha: 0.08),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Loaded (not yet on trip): '
                                  '$loadedNotAssigned/${p.itemCount}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Remaining pending at station: '
                                  '$remainingPending/${p.itemCount}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),
                          Text(
                            'Created: ${_fmt16(p.createdAt)}',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          Text(
                            'LoadedAt: ${_fmt16(p.loadedAt)}',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          Text(
                            'InTransit: ${_fmt16(p.inTransitAt)}',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                          Text(
                            'Delivered: ${_fmt16(p.deliveredAt)}',
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(
                        isPaid ? 'Payment Recorded ✅' : 'Record Payment',
                      ),
                      onPressed: () => _recordPaymentDialog(context, p),
                    ),
                  ),
                  const SizedBox(height: 12),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.local_shipping),
                      label: Text(
                        !isPaid
                            ? 'Record Payment First'
                            : canMarkLoadedNow
                            ? 'Mark Loaded (Select items)'
                            : (remainingPending == 0
                                  ? 'All items loaded ✅'
                                  : 'Cannot load now'),
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
                              final st = (Session.currentStationName ?? '')
                                  .trim();

                              if (st.isEmpty) {
                                if (!ctx.mounted) return;
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'No station set for this user ❌',
                                    ),
                                  ),
                                );
                                return;
                              }

                              final selectedNos = await _pickItemNumbersToLoad(
                                context: ctx,
                                p: p,
                              );

                              if (!ctx.mounted) return;
                              if (selectedNos == null ||
                                  selectedNos.isEmpty) return;

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

                  // ── F1: Reject button ─────────────────────────────────
                  if (canReject) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.cancel_outlined,
                          color: Colors.red,
                        ),
                        label: const Text(
                          'Reject Property',
                          style: TextStyle(color: Colors.red),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                        ),
                        onPressed: () => _showRejectDialog(context, p),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // ─────────────────────────────────────────────────────

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

                          final itemBox = HiveService.propertyItemBox();
                          final itemSvc = PropertyItemService(itemBox);

                          await itemSvc.ensureItemsForProperty(
                            propertyKey: p.key.toString(),
                            trackingCode: p.trackingCode,
                            itemCount: p.itemCount,
                          );

                          final all = itemSvc.getItemsForProperty(
                            p.key.toString(),
                          );

                          final toPrint =
                              all
                                  .where(
                                    (x) =>
                                        x.status ==
                                            PropertyItemStatus.loaded &&
                                        x.tripId.trim().isEmpty,
                                  )
                                  .toList()
                                ..sort(
                                  (a, b) => a.itemNo.compareTo(b.itemNo),
                                );

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
}