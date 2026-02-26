import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../models/property.dart';
import '../../models/property_status.dart';
import '../../models/user_role.dart';

import '../../models/property_item_status.dart';

import '../../services/hive_service.dart';
import '../../services/printing/printer_service.dart';
import '../../services/printing/printer_settings_service.dart';
import '../../services/role_guard.dart';
import '../../services/property_service.dart';
import '../../services/session.dart';

import '../../services/property_item_service.dart';
import '../../services/printing/escpos_label_builder.dart';

class DeskPropertyDetailsScreen extends StatefulWidget {
  final String scannedCode; // propertyCode
  const DeskPropertyDetailsScreen({super.key, required this.scannedCode});

  @override
  State<DeskPropertyDetailsScreen> createState() =>
      _DeskPropertyDetailsScreenState();
}

class _DeskPropertyDetailsScreenState extends State<DeskPropertyDetailsScreen> {
  static String _fmt16(DateTime? d) {
    if (d == null) return '—';
    return d.toLocal().toString().substring(0, 16);
  }

  String _statusText(PropertyStatus s) {
    switch (s) {
      case PropertyStatus.pending:
        return '🟡 Pending';
      case PropertyStatus.inTransit:
        return '🔵 In Transit';
      case PropertyStatus.delivered:
        return '🟢 Delivered';
      case PropertyStatus.pickedUp:
        return '✅ Picked Up';
    }
  }

  Property? _findByCode(Box<Property> box, String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return null;

    // primary: propertyCode
    for (final p in box.values) {
      if (p.propertyCode.trim().toLowerCase() == c) return p;
    }

    // fallback: allow scanning "key"
    final key = int.tryParse(code.trim());
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
                  Navigator.pop(ctx, 1); // safe fallback
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

    // Only allow selecting PENDING items for loading
    final selectable =
        all.where((x) => x.status == PropertyItemStatus.pending).toList()
          ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

    if (selectable.isEmpty) return null;

    final selected = <int>{
      for (final x in selectable) x.itemNo,
    }; // default: all pending

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
                      Navigator.pop(ctx); // nothing selected
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

  @override
  Widget build(BuildContext context) {
    if (!RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin})) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final box = HiveService.propertyBox();

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

          // Desk can load as long as property is still pending.
          final canLoad = p.status == PropertyStatus.pending;

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
              final itemBox = HiveService.propertyItemBox();
              final itemSvc = PropertyItemService(itemBox);
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

              final canMarkLoadedNow = canLoad && remainingPending > 0;

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Code: $code',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Status: ${_statusText(p.status)}'),
                          Text('Receiver: ${p.receiverName}'),
                          Text('Phone: ${p.receiverPhone}'),
                          Text('Destination: ${p.destination}'),
                          Text('Items: ${p.itemCount}'),
                          const SizedBox(height: 8),
                          Text(
                            'Loaded (not yet on trip): $loadedNotAssigned/${p.itemCount}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'Remaining pending at station: $remainingPending/${p.itemCount}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Created: ${_fmt16(p.createdAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'LoadedAt: ${_fmt16(p.loadedAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'InTransit: ${_fmt16(p.inTransitAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            'Delivered: ${_fmt16(p.deliveredAt)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Mark Loaded (Desk) with selection
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.local_shipping),
                      label: Text(
                        canMarkLoadedNow
                            ? 'Mark Loaded (Select items)'
                            : (remainingPending == 0
                                  ? 'All items loaded ✅'
                                  : 'Cannot load now'),
                      ),
                      onPressed: !canMarkLoadedNow
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
                              if (selectedNos == null || selectedNos.isEmpty) {
                                return;
                              }

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

                  // Print item labels (thermal) for LOADED not assigned to a trip
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text('Print Item Labels (Thermal)'),
                      onPressed: () async {
                        final ctx = context;

                        try {
                          // 1) Ensure printer connected
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

                          // 2) Ask copies per item (dialog uses ctx)
                          final copies = await _askCopiesPerItem(ctx);

                          if (!ctx.mounted) return;
                          if (copies == null) return;

                          // 3) Ensure items exist
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

                          // Print only items LOADED for today (trip not assigned yet)
                          final toPrint =
                              all
                                  .where(
                                    (x) =>
                                        x.status == PropertyItemStatus.loaded &&
                                        x.tripId.trim().isEmpty,
                                  )
                                  .toList()
                                ..sort((a, b) => a.itemNo.compareTo(b.itemNo));

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

                          // 4) Build + print labels per item (with copies)
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
