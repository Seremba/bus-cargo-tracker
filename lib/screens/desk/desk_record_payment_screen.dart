import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/routes.dart';
import '../../data/routes_helpers.dart';
import '../../models/payment_record.dart';
import '../../models/property.dart';
import '../../models/user_role.dart';
import '../../services/hive_service.dart';
import '../../services/payment_service.dart';
import '../../services/role_guard.dart';
import '../../services/session.dart';
import '../../services/printing/payment_receipt_print_service.dart';
import '../../services/printing/receipt_share_service.dart';
import '../../services/receiver_tracking_service.dart';

class DeskRecordPaymentScreen extends StatefulWidget {
  final Property property;
  const DeskRecordPaymentScreen({super.key, required this.property});

  @override
  State<DeskRecordPaymentScreen> createState() =>
      _DeskRecordPaymentScreenState();
}

class _DeskRecordPaymentScreenState extends State<DeskRecordPaymentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _txnRef = TextEditingController();

  String _method = 'cash';
  bool _saving = false;

  bool _notifyReceiver = false;
  // SMS is the default — safer for receivers without smartphones.
  // Staff can switch to WhatsApp if the receiver has it.
  String _notifyChannel = 'sms';

  AppRoute? _selectedRouteForConfirmation;

  bool get _canUse =>
      RoleGuard.hasAny({UserRole.deskCargoOfficer, UserRole.admin});

  @override
  void initState() {
    super.initState();

    final p = widget.property;
    _notifyReceiver = p.notifyReceiver == true;

    // Default to sms unless explicitly set to whatsapp
    final c = (p.receiverNotifyChannel).trim().toLowerCase();
    _notifyChannel = (c == 'whatsapp') ? 'whatsapp' : 'sms';

    final matches = findRoutesByDestination(p.destination);
    if (matches.isNotEmpty) {
      if (p.routeConfirmed && p.routeId.trim().isNotEmpty) {
        try {
          _selectedRouteForConfirmation = routes.firstWhere(
            (r) => r.id == p.routeId.trim(),
          );
        } catch (_) {
          _selectedRouteForConfirmation = matches.first.route;
        }
      } else {
        _selectedRouteForConfirmation = matches.first.route;
      }
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _txnRef.dispose();
    super.dispose();
  }

  Future<void> _copy(BuildContext context, String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$label copied ✅')));
  }

  @override
  Widget build(BuildContext context) {
    if (!_canUse) {
      return const Scaffold(body: Center(child: Text('Not authorized')));
    }

    final station = (Session.currentStationName ?? '').trim();
    if (station.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No station set for this user ❌')),
      );
    }

    final pBox = HiveService.propertyBox();
    final fresh = pBox.get(widget.property.key) ?? widget.property;

    final displayCode = fresh.propertyCode.trim().isEmpty
        ? fresh.key.toString()
        : fresh.propertyCode.trim();
    final displayCurrency = fresh.currency.trim().isEmpty
        ? 'UGX'
        : fresh.currency.trim();

    final routeMatches = findRoutesByDestination(fresh.destination);
    final needsRouteConfirmation =
        !fresh.routeConfirmed && routeMatches.isNotEmpty;

    final uniqueRoutes = <String, AppRoute>{};
    for (final m in routeMatches) {
      uniqueRoutes[m.route.id] = m.route;
    }
    final candidateRoutes = uniqueRoutes.values.toList();

    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('Record Payment')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
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
                              'Property: $displayCode',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (fresh.propertyCode.trim().isNotEmpty)
                            IconButton(
                              tooltip: 'Copy code',
                              icon: const Icon(Icons.copy, size: 18),
                              onPressed: () =>
                                  _copy(context, 'Property code', displayCode),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('Receiver: ${fresh.receiverName}'),
                      Text('Phone: ${fresh.receiverPhone}'),
                      Text(
                        'Route: ${fresh.routeName.trim().isEmpty ? '—' : fresh.routeName.trim()}',
                      ),
                      Text('Destination: ${fresh.destination}'),
                      const SizedBox(height: 6),
                      Text('Station: $station'),
                      const SizedBox(height: 6),
                      Text(
                        'Total Paid: $displayCurrency ${fresh.amountPaidTotal}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              if (needsRouteConfirmation) ...[
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Route confirmation required',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'This destination matches multiple operational routes. '
                          'Confirm the route before recording payment.',
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<AppRoute>(
                          initialValue: _selectedRouteForConfirmation,
                          decoration: const InputDecoration(
                            labelText: 'Operational route',
                            border: OutlineInputBorder(),
                          ),
                          items: candidateRoutes
                              .map(
                                (r) => DropdownMenuItem(
                                  value: r,
                                  child: Text(r.name),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            setState(() {
                              _selectedRouteForConfirmation = v;
                            });
                          },
                          validator: (_) {
                            if (!needsRouteConfirmation) return null;
                            if (_selectedRouteForConfirmation == null) {
                              return 'Please confirm route';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(9),
                ],
                decoration: const InputDecoration(
                  labelText: 'Amount (UGX)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  final n = int.tryParse(t);
                  if (n == null) return 'Enter a valid amount';
                  if (n <= 0) return 'Amount must be > 0';
                  return null;
                },
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                initialValue: _method,
                decoration: const InputDecoration(
                  labelText: 'Method',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'momo', child: Text('Mobile Money')),
                  DropdownMenuItem(value: 'bank', child: Text('Bank')),
                ],
                onChanged: (v) => setState(() => _method = (v ?? 'cash')),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _txnRef,
                decoration: const InputDecoration(
                  labelText: 'Txn ref (optional)',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 16),

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Receiver updates',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Send progress updates to receiver'),
                        subtitle: const Text(
                          'Sends payment confirmation + later status updates.',
                        ),
                        value: _notifyReceiver,
                        onChanged: (v) => setState(() => _notifyReceiver = v),
                      ),
                      if (_notifyReceiver) ...[
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _notifyChannel,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Channel',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'sms',
                              child: Text(
                                'SMS (recommended — works on all phones)',
                              ),
                            ),
                            DropdownMenuItem(
                              value: 'whatsapp',
                              child: Text('WhatsApp (smartphone only)'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _notifyChannel = (v ?? 'sms')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              ElevatedButton(
                onPressed: _saving ? null : _submit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: Text(_saving ? 'Saving...' : 'Save Payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showReceiptOptions({
    required BuildContext context,
    required PaymentRecord record,
    required Property property,
    required bool? printed,
  }) async {
    final cs = Theme.of(context).colorScheme;

    final printLabel = printed == true
        ? '✅ Receipt printed'
        : printed == false
            ? '⚠️ Print failed — try again'
            : '🖨️ Print receipt';

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Payment recorded ✅',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'How would you like to share the receipt?',
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurface.withValues(alpha: 0.60),
                ),
              ),
              const SizedBox(height: 16),

              // Print option
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.print_outlined,
                      color: cs.primary, size: 22),
                ),
                title: Text(printLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Bluetooth thermal printer'),
                onTap: printed != true
                    ? () async {
                        Navigator.pop(ctx);
                        final ok =
                            await PaymentReceiptPrintService.printAfterPayment(
                          record: record,
                          property: property,
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok == true
                                  ? 'Receipt printed ✅'
                                  : ok == false
                                      ? 'Print failed ⚠️'
                                      : 'No printer configured',
                            ),
                          ),
                        );
                      }
                    : null,
              ),

              const Divider(height: 1),

              // Share as text
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.message_outlined,
                      color: Colors.green, size: 22),
                ),
                title: const Text('Share as text',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('WhatsApp, SMS, email…'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptShareService.shareAsText(
                    pay: record,
                    property: property,
                  );
                },
              ),

              const Divider(height: 1),

              // Share as PDF
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.picture_as_pdf_outlined,
                      color: Colors.red, size: 22),
                ),
                title: const Text('Share as PDF',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Save or send as document'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptShareService.shareAsPdf(
                    pay: record,
                    property: property,
                  );
                },
              ),

              const Divider(height: 1),

              // Done
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.onSurface.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.check,
                      color: cs.onSurface.withValues(alpha: 0.55),
                      size: 22),
                ),
                title: const Text('Done — no receipt needed',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                onTap: () => Navigator.pop(ctx),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_canUse) return;
    if (!_formKey.currentState!.validate()) return;
    if (_saving) return;

    final station = (Session.currentStationName ?? '').trim();
    if (station.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No station set for this user ❌')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);

    try {
      final pBox = HiveService.propertyBox();
      final freshBeforePayment =
          pBox.get(widget.property.key) ?? widget.property;

      if (!freshBeforePayment.routeConfirmed) {
        if (_selectedRouteForConfirmation == null) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Please confirm route first.')),
          );
          return;
        }

        freshBeforePayment.routeId = _selectedRouteForConfirmation!.id;
        freshBeforePayment.routeName = _selectedRouteForConfirmation!.name;
        freshBeforePayment.routeConfirmed = true;
        await freshBeforePayment.save();
      }

      final amount = int.parse(_amount.text.trim());

      final rec = await PaymentService.recordPayment(
        property: freshBeforePayment,
        amount: amount,
        currency: 'UGX',
        method: _method,
        txnRef: _txnRef.text.trim(),
        station: station,
        kind: 'payment',
      );

      final fresh = pBox.get(widget.property.key) ?? widget.property;

      if (_notifyReceiver) {
        try {
          await ReceiverTrackingService.afterPaymentRecorded(
            property: fresh,
            enabled: true,
            channel: _notifyChannel,
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: Text('Payment saved, but receiver updates failed: $e'),
            ),
          );
        }
      } else {
        try {
          await ReceiverTrackingService.afterPaymentRecorded(
            property: fresh,
            enabled: false,
            channel: _notifyChannel,
          );
        } catch (_) {}
      }

      final printed = await PaymentReceiptPrintService.printAfterPayment(
        record: rec,
        property: fresh,
      );

      if (!mounted) return;

      // Show receipt options bottom sheet
      await _showReceiptOptions(
        context: context,
        record: rec,
        property: fresh,
        printed: printed,
      );

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}