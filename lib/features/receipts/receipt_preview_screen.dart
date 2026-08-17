import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/currency_helper.dart';
import '../../models/order_model.dart';
import '../../models/receipt_view_data.dart';
import '../../providers/auth_provider.dart';
import '../../services/receipt_print_service.dart';
import '../../services/receipt_service.dart';

/// Shared receipt viewer. Administrative output actions are protected here as
/// well as at their entry points; staff can never invoke them.
class ReceiptPreviewScreen extends StatefulWidget {
  const ReceiptPreviewScreen({super.key, required this.order});
  final OrderModel order;

  @override
  State<ReceiptPreviewScreen> createState() => _ReceiptPreviewScreenState();
}

class _ReceiptPreviewScreenState extends State<ReceiptPreviewScreen> {
  late final Future<ReceiptViewData> _receipt;

  @override
  void initState() {
    super.initState();
    _receipt = ReceiptService().buildForOrder(widget.order);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isAdmin = auth.isAdmin;
    final isOwner = auth.isCustomer && auth.user?.id == widget.order.userId;
    if (!isAdmin && !isOwner) {
      return const Scaffold(body: Center(child: Text('You are not authorized to view this receipt.')));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Preview')),
      body: FutureBuilder<ReceiptViewData>(
        future: _receipt,
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return const Center(child: Text('Unable to prepare receipt.'));
          final data = snapshot.data!;
          return Column(children: [
            Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420), child: _ReceiptPaper(data: data, showCustomer: isAdmin || isOwner, showStaff: isAdmin),
            )))),
            if (isAdmin) SafeArea(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.ios_share), label: const Text('Share PDF'), onPressed: () => ReceiptPrintService.share(data))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton.icon(icon: const Icon(Icons.print), label: const Text('Print / Save'), onPressed: () => ReceiptPrintService.print(data))),
              ]),
            )),
          ]);
        },
      ),
    );
  }
}

class _ReceiptPaper extends StatelessWidget {
  const _ReceiptPaper({required this.data, required this.showCustomer, required this.showStaff});
  final ReceiptViewData data;
  final bool showCustomer;
  final bool showStaff;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 4, color: Colors.white,
    child: Padding(padding: const EdgeInsets.all(22), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('THIA & NICOLE', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
      const Text('Laundry Shop', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 3),
      const Text('Sabalo St, Dagat-Dagatan, Caloocan City', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
      const Divider(height: 26),
      _row('Transaction No.', data.transactionNumber, bold: true),
      _row('Date', _date(data.createdAt)),
      if (showCustomer && data.customerName?.isNotEmpty == true) 
        _row('Customer', data.customerName!.toUpperCase(), bold: true),
      if (showCustomer && data.customerPhone?.isNotEmpty == true) 
        _row('Contact', data.customerPhone!),
      const Divider(height: 26),
      const Text('LOAD DETAILS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
      const SizedBox(height: 8),
      if (data.loads.isEmpty) _row(data.serviceType, '${data.weight.toStringAsFixed(1)} kg'),
      ...data.loads.map((load) => Padding(padding: const EdgeInsets.only(bottom: 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Load ${load.loadNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('${load.weight.toStringAsFixed(1)} kg • ${load.serviceType}', style: const TextStyle(fontSize: 12)),
        Text(load.status.value, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ]))),
      if (data.selectedSoaps != null && data.selectedSoaps!.isNotEmpty) ...[
        const Divider(height: 26),
        const Text('SOAP ADD-ONS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .8)),
        const SizedBox(height: 8),
        ...data.selectedSoaps!.map((soap) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${soap['soapName']} x${soap['quantity']}',
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                CurrencyHelper.formatSimple((soap['soapPrice'] ?? 0) * (soap['quantity'] ?? 0)),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        )),
      ],
      const Divider(height: 26),
      _row('Subtotal', CurrencyHelper.formatSimple(data.subtotal)),
      _row('Total', CurrencyHelper.formatSimple(data.total), bold: true),
      _row('Payment', data.paymentStatus),
      _row('Method', data.paymentMethodLabel),
      _row('Collection', data.collectionMethodLabel),
      _row('Transaction status', data.displayStatus),
      if (showStaff) _row('Assigned staff', data.assignedStaffName.toUpperCase(), bold: true),
      const Divider(height: 26),
      const Text('SCAN TO TRACK', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
      const SizedBox(height: 8),
      Center(child: QrImageView(data: data.trackingUrl, size: 150)),
      const SizedBox(height: 10),
      const Text('Thank you for choosing\nTHIA & NICOLE Laundry Shop!', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
    ])),
  );

  static Widget _row(String label, String value, {bool bold = false}) => Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w400))),
    Expanded(child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w500))),
  ]));
  static String _date(DateTime value) => '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
