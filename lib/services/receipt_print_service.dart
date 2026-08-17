import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/receipt_view_data.dart';

class ReceiptPrintService {
  static Future<Uint8List> build80mmPdf(ReceiptViewData data) async {
    final doc = pw.Document();
    final qr = Barcode.qrCode();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 5 * PdfPageFormat.mm),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Center(child: pw.Text('THIA & NICOLE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 15))),
            pw.Center(child: pw.Text('Laundry Shop', style: const pw.TextStyle(fontSize: 11))),
            pw.Center(child: pw.Text('Sabalo St, Dagat-Dagatan, Caloocan City', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
            _line(),
            _row('Transaction No:', data.transactionNumber),
            _row('Date:', _date(data.createdAt)),
            if (data.customerName?.isNotEmpty == true) _row('Customer:', data.customerName!),
            if (data.customerPhone?.isNotEmpty == true) _row('Contact:', data.customerPhone!),
            _line(),
            pw.Text('LOAD DETAILS', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
            ...data.loads.map((load) => pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                    pw.Text('Load ${load.loadNumber}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    pw.Text('Weight: ${load.weight.toStringAsFixed(1)} kg | ${load.serviceType}', style: const pw.TextStyle(fontSize: 8)),
                    pw.Text('Status: ${load.status.value}', style: const pw.TextStyle(fontSize: 8)),
                  ]),
                )),
            if (data.loads.isEmpty) pw.Text('${data.serviceType} • ${data.weight.toStringAsFixed(1)} kg', style: const pw.TextStyle(fontSize: 8)),
            _line(),
            _row('Subtotal:', _money(data.subtotal)),
            _row('Total:', _money(data.total), bold: true),
            _row('Payment:', data.paymentStatus),
            _row('Method:', data.paymentMethod),
            _row('Status:', data.status),
            _row('Assigned staff:', data.assignedStaffName),
            _line(),
            pw.Center(child: pw.Text('SCAN TO TRACK', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
            pw.SizedBox(height: 5),
            pw.Center(child: pw.BarcodeWidget(barcode: qr, data: data.trackingUrl, width: 92, height: 92)),
            pw.SizedBox(height: 5),
            pw.Center(child: pw.Text('Thank you for choosing\nTHIA & NICOLE Laundry Shop!', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
    );
    return doc.save();
  }

  static Future<void> print(ReceiptViewData data) async {
    await Printing.layoutPdf(onLayout: (_) => build80mmPdf(data), name: data.transactionNumber);
  }

  static Future<void> share(ReceiptViewData data) async {
    final bytes = await build80mmPdf(data);
    await Printing.sharePdf(bytes: bytes, filename: '${data.transactionNumber}.pdf');
  }

  static pw.Widget _line() => pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 7), child: pw.Divider(thickness: .6));
  static pw.Widget _row(String label, String value, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3),
    child: pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
      pw.Expanded(child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 8, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
    ]),
  );
  static String _money(double value) => 'PHP ${value.toStringAsFixed(2)}';
  static String _date(DateTime value) => '${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
