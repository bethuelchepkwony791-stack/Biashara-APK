import 'package:flutter/material.dart';
import 'dart:html' as html;
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> exportToCsv(List<Map<String, dynamic>> customers, BuildContext context) async {
  if (customers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No customers to export'), backgroundColor: Colors.orange),
    );
    return;
  }

  final totalDebt = customers.fold<double>(0, (s, c) => s + (c['debtAmount'] ?? 0));
  final totalUnread = customers.fold(0, (s, c) => s + ((c['unread'] ?? 0) as int));

  final headers = [
    'Name', 'Business', 'Phone Numbers', 'Last Message', 'Time', 'Unread',
    'Assigned To', 'Assigned Person', 'Tags', 'Notes', 'Debt (KES)'
  ];
  final rows = [headers];
  for (var c in customers) {
    rows.add([
      c['name'],
      c['business'],
      (c['phoneNumbers'] as List).join(', '),
      c['lastMessage'],
      c['time'],
      c['unread'].toString(),
      c['assignedTo'],
      c['assignedToPerson'],
      (c['tags'] as List).join(', '),
      c['notes'] ?? '',
      (c['debtAmount'] ?? 0).toStringAsFixed(2),
    ]);
  }
  rows.add(List.filled(headers.length, ''));
  rows.add([
    'TOTAL', '', '', '', '', totalUnread.toString(), '', '', '',
    'Total Customers: ${customers.length}', totalDebt.toStringAsFixed(2)
  ]);

  final csv = const ListToCsvConverter().convert(rows);
  if (kIsWeb) {
    final blob = html.Blob([csv], 'text/csv');
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..download = 'customers_export_${DateTime.now().millisecondsSinceEpoch}.csv'
      ..click();
    html.Url.revokeObjectUrl(url);
  } else {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/customers_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csv);
    await Share.shareXFiles([XFile(file.path)], text: 'Customer List Export', subject: 'BiasharaOS Export');
  }
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Export successful'), backgroundColor: Colors.green),
  );
}

Future<void> exportToPdf(List<Map<String, dynamic>> customers, BuildContext context) async {
  if (customers.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No customers to export'), backgroundColor: Colors.orange),
    );
    return;
  }

  final totalDebt = customers.fold<double>(0, (s, c) => s + (c['debtAmount'] ?? 0));
  final totalUnread = customers.fold(0, (s, c) => s + ((c['unread'] ?? 0) as int));

  final pdf = pw.Document();
  pdf.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    orientation: pw.PageOrientation.landscape,
    build: (_) => [
      pw.Header(level: 0, child: pw.Text('BiasharaOS - Customer Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 10),
      pw.Text('Generated: ${DateTime.now()}', style: pw.TextStyle(fontSize: 10)),
      pw.SizedBox(height: 20),
      pw.TableHelper.fromTextArray(
        headers: [
          'Name', 'Business', 'Phone Numbers', 'Last Message', 'Time', 'Unread',
          'Assigned To', 'Assigned Person', 'Tags', 'Notes', 'Debt (KES)'
        ],
        data: customers.map((c) => [
          c['name'],
          c['business'],
          (c['phoneNumbers'] as List).join(', '),
          c['lastMessage'],
          c['time'],
          c['unread'].toString(),
          c['assignedTo'],
          c['assignedToPerson'],
          (c['tags'] as List).join(', '),
          c['notes'] ?? '',
          (c['debtAmount'] ?? 0).toStringAsFixed(2),
        ]).toList(),
        headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
        border: pw.TableBorder.all(width: 0.5),
        cellAlignment: pw.Alignment.centerLeft,
        headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
      ),
      pw.SizedBox(height: 20),
      pw.Container(
        padding: pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('SUMMARY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
            pw.SizedBox(height: 5),
            pw.Text('Total Customers: ${customers.length}'),
            pw.Text('Total Unread Messages: $totalUnread'),
            pw.Text('Total Debt (KES): ${totalDebt.toStringAsFixed(2)}'),
          ],
        ),
      ),
    ],
  ));
  await Printing.sharePdf(bytes: await pdf.save(), filename: 'customers_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('PDF report generated'), backgroundColor: Colors.green),
  );
}