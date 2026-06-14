import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:intl/intl.dart';
import 'services/invoice_service.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  String? currentTenantId;
  Map<String, dynamic>? supplierDetails;

  // Cache customer names
  final Map<String, String> _customerNames = {};

  @override
  void initState() {
    super.initState();
    _loadTenantIdAndSupplier();
  }

  Future<void> _loadTenantIdAndSupplier() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists) {
        setState(() {
          currentTenantId = userDoc.data()?['tenantId'];
        });
        if (currentTenantId != null) {
          final tenantDoc = await FirebaseFirestore.instance.collection('tenants').doc(currentTenantId).get();
          if (tenantDoc.exists) {
            setState(() {
              supplierDetails = {
                'name': tenantDoc.data()?['name'] ?? 'Biashara OS',
                'address': tenantDoc.data()?['address'] ?? 'Nairobi, Kenya',
                'email': tenantDoc.data()?['email'] ?? 'info@biasharaos.com',
                'phone': tenantDoc.data()?['phone'] ?? '+254 700 000 000',
              };
            });
          } else {
            setState(() {
              supplierDetails = {
                'name': 'Biashara OS',
                'address': 'Nairobi, Kenya',
                'email': 'info@biasharaos.com',
                'phone': '+254 700 000 000',
              };
            });
          }
        }
      }
    }
  }

  Future<String> _getCustomerName(String? customerId) async {
    if (customerId == null) return 'Unknown';
    if (_customerNames.containsKey(customerId)) return _customerNames[customerId]!;
    try {
      final doc = await FirebaseFirestore.instance.collection('customers').doc(customerId).get();
      final name = doc.exists ? (doc.data()?['name'] ?? 'Unknown') : 'Unknown';
      _customerNames[customerId] = name;
      return name;
    } catch (e) {
      return 'Unknown';
    }
  }

  Stream<QuerySnapshot> _getTransactionsStream() {
    if (currentTenantId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('tenantId', isEqualTo: currentTenantId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> _generateInvoice({
    required Map<String, dynamic> transaction,
    bool autoSend = false,
    String? customCustomerName,
    double? subtotal,
    double? taxRate,
    double? discount,
    String? description,
    String? paymentTerms,
    DateTime? dueDate,
  }) async {
    if (supplierDetails == null) return;

    final customerId = transaction['customerId'];
    String customerName = customCustomerName ?? 'Customer';
    String customerAddress = '';
    String customerPhone = '';
    if (customerId != null) {
      final customerDoc = await FirebaseFirestore.instance.collection('customers').doc(customerId).get();
      if (customerDoc.exists) {
        customerName = customerDoc.data()?['name'] ?? customerName;
        customerAddress = customerDoc.data()?['address'] ?? '';
        final phones = customerDoc.data()?['phoneNumbers'] as List?;
        if (phones != null && phones.isNotEmpty) customerPhone = phones[0];
      }
    }

    final amount = (transaction['amount'] ?? 0).toDouble();
    final date = (transaction['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now();

    final finalSubtotal = subtotal ?? amount;
    final finalTaxRate = taxRate ?? 0.16;
    final finalDiscount = discount ?? 0.0;
    final taxAmount = finalSubtotal * finalTaxRate;
    final grandTotal = finalSubtotal + taxAmount - finalDiscount;
    final finalPaymentTerms = paymentTerms ?? 'Due within 30 days';
    final finalDueDate = dueDate ?? date.add(const Duration(days: 30));
    final descriptionText = description ?? (transaction['type'] == 'manual_invoice' ? 'Consulting services' : 'Payment received');

    final invoiceNumber = await InvoiceService.getNextInvoiceNumber();

    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) => [
        pw.Container(
          alignment: pw.Alignment.center,
          child: pw.Text('INVOICE', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('Invoice Number: $invoiceNumber'),
              pw.Text('Date: ${DateFormat('dd/MM/yyyy').format(date)}'),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('Due Date: ${DateFormat('dd/MM/yyyy').format(finalDueDate)}'),
            ]),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Supplier', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(supplierDetails!['name']),
                pw.Text(supplierDetails!['address']),
                pw.Text(supplierDetails!['email']),
                pw.Text(supplierDetails!['phone']),
              ]),
            ),
            pw.SizedBox(width: 20),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Bill To', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text(customerName),
                if (customerAddress.isNotEmpty) pw.Text(customerAddress),
                if (customerPhone.isNotEmpty) pw.Text(customerPhone),
              ]),
            ),
          ],
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: ['Description', 'Quantity', 'Unit Price (KES)', 'Total (KES)'],
          data: [
            [descriptionText, '1', finalSubtotal.toStringAsFixed(2), finalSubtotal.toStringAsFixed(2)],
          ],
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          cellAlignment: pw.Alignment.centerLeft,
          border: pw.TableBorder.all(width: 0.5),
        ),
        pw.SizedBox(height: 20),
        pw.Container(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: KES ${finalSubtotal.toStringAsFixed(2)}'),
              pw.Text('Tax (${(finalTaxRate * 100).toStringAsFixed(0)}% VAT): KES ${taxAmount.toStringAsFixed(2)}'),
              if (finalDiscount > 0) pw.Text('Discount: KES ${finalDiscount.toStringAsFixed(2)}'),
              pw.Divider(),
              pw.Text('Grand Total: KES ${grandTotal.toStringAsFixed(2)}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
        pw.SizedBox(height: 20),
        pw.Text('Payment Terms', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Text(finalPaymentTerms),
        pw.Text('Accepted payment methods: M-PESA, Bank Transfer, Credit Card'),
        pw.SizedBox(height: 10),
        pw.Text('Thank you for your business!'),
      ],
    ));

    final bytes = await pdf.save();

    // Cross-platform PDF sharing
    if (kIsWeb) {
      // Web: download the PDF (user can then share manually)
      final blob = html.Blob([bytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..download = 'invoice_$invoiceNumber.pdf'
        ..click();
      html.Url.revokeObjectUrl(url);
      if (autoSend) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice downloaded. You can now share it.')),
        );
      }
    } else {
      // Mobile: save to temporary directory and share
      final output = await getTemporaryDirectory();
      final filePath = '${output.path}/invoice_$invoiceNumber.pdf';
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      if (autoSend) {
        await Share.shareXFiles([XFile(filePath)], text: 'Your invoice from Biashara OS');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: 'invoice_$invoiceNumber.pdf');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard'), backgroundColor: Colors.green),
      body: currentTenantId == null || supplierDetails == null
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: _getTransactionsStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(child: Text('No transactions yet'));
                }
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final amount = (data['amount'] ?? 0).toDouble();
                    final type = data['type'] ?? 'unknown';
                    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                    final customerId = data['customerId'];
                    return FutureBuilder<String>(
                      future: _getCustomerName(customerId),
                      builder: (context, snapshot) {
                        final customerName = snapshot.data ?? 'Loading...';
                        return Card(
                          margin: const EdgeInsets.all(8),
                          child: ListTile(
                            title: Text('KES ${amount.toStringAsFixed(2)}'),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Type: $type'),
                                Text('Customer: $customerName'),
                                Text('Date: ${timestamp?.toLocal() ?? 'Unknown date'}'),
                              ],
                            ),
                            trailing: ElevatedButton.icon(
                              onPressed: () => _generateInvoice(transaction: data),
                              icon: const Icon(Icons.receipt),
                              label: const Text('Invoice'),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showManualInvoiceDialog(),
        label: const Text('Manual Invoice'),
        icon: const Icon(Icons.add),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _showManualInvoiceDialog() async {
    final amountCtrl = TextEditingController();
    final customerIdCtrl = TextEditingController();
    final descriptionCtrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Manual Invoice'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: amountCtrl, decoration: const InputDecoration(labelText: 'Amount (KES)'), keyboardType: TextInputType.number),
            const SizedBox(height: 8),
            TextField(controller: customerIdCtrl, decoration: const InputDecoration(labelText: 'Customer ID (optional)')),
            const SizedBox(height: 8),
            TextField(controller: descriptionCtrl, decoration: const InputDecoration(labelText: 'Description (optional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text) ?? 0;
              if (amount <= 0) return;
              final manualTransaction = {
                'amount': amount,
                'type': 'manual_invoice',
                'customerId': customerIdCtrl.text.isNotEmpty ? customerIdCtrl.text : null,
                'note': descriptionCtrl.text,
                'tenantId': currentTenantId,
                'timestamp': FieldValue.serverTimestamp(),
              };
              final docRef = await FirebaseFirestore.instance.collection('transactions').add(manualTransaction);
              await _generateInvoice(
                transaction: {...manualTransaction, 'id': docRef.id},
                description: descriptionCtrl.text.isNotEmpty ? descriptionCtrl.text : 'Manual invoice',
                subtotal: amount,
              );
              Navigator.pop(c);
              ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Manual invoice created'), backgroundColor: Colors.green));
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}