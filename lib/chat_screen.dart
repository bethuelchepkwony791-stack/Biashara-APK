import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert' as convert;
import 'package:flutter/foundation.dart' show kIsWeb;

// Invoice line item model
class InvoiceLineItem {
  String description;
  int quantity;
  double unitPrice;

  InvoiceLineItem({
    required this.description,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  Map<String, dynamic> toJson() => {
        'description': description,
        'quantity': quantity,
        'unitPrice': unitPrice,
        'total': total,
      };
}

class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> customer;

  const ChatScreen({super.key, required this.customer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  String? currentTenantId;
  String? currentUserId;
  bool _isProcessing = false;

  List<QueryDocumentSnapshot> _transactions = [];
  StreamSubscription<QuerySnapshot>? _transactionsSubscription;

  // Backend URL
  final String backendBaseUrl = 'https://biashara-whatsapp-webhook.onrender.com';

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _listenToTransactions();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _messageController.dispose();
    _transactionsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (userDoc.exists && mounted) {
        setState(() {
          currentUserId = uid;
          currentTenantId = userDoc.data()?['tenantId'];
        });
      }
    }
  }

  void _listenToTransactions() {
    final customerId = widget.customer['id'];
    if (customerId == null || currentTenantId == null) return;
    _transactionsSubscription?.cancel();
    _transactionsSubscription = FirebaseFirestore.instance
        .collection('transactions')
        .where('customerId', isEqualTo: customerId)
        .where('tenantId', isEqualTo: currentTenantId)
        .orderBy('timestamp', descending: true)
        .limit(10)
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _transactions = snapshot.docs;
        });
      }
    }, onError: (e) {
      debugPrint('Error loading transactions: $e');
    });
  }

  String? _getCustomerPhone() {
    final phones = widget.customer['phoneNumbers'] as List<String>?;
    if (phones == null || phones.isEmpty) return null;
    String phone = phones.first.trim();
    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('0')) phone = '254${phone.substring(1)}';
    if (!phone.startsWith('254')) phone = '254$phone';
    return phone;
  }

  Future<void> _sendMessageViaAPI(String message, String customerId) async {
    final phone = _getCustomerPhone();
    if (phone == null) throw Exception('Customer has no valid phone number');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final idToken = await user.getIdToken();

    final url = '$backendBaseUrl/send-message';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: convert.jsonEncode({
        'to': phone,
        'text': message,
        'customerId': customerId,
      }),
    );
    if (response.statusCode != 200) {
      final error = convert.jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception('Failed to send: $error');
    }
  }

  Future<void> _sendWhatsAppMessage(String message) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _sendMessageViaAPI(message, widget.customer['id']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // INVOICE BUILDER
  Future<void> _showInvoiceBuilder() async {
    List<InvoiceLineItem> items = [InvoiceLineItem(description: '', quantity: 1, unitPrice: 0.0)];
    bool includeTax = true;
    double taxRate = 0.16;
    double discount = 0.0;

    return showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) {
          void addItem() {
            setStateDialog(() {
              items.add(InvoiceLineItem(description: '', quantity: 1, unitPrice: 0.0));
            });
          }

          void removeItem(int index) {
            setStateDialog(() {
              items.removeAt(index);
            });
          }

          double subtotal = items.fold(0, (sum, item) => sum + item.total);
          double taxAmount = includeTax ? subtotal * taxRate : 0.0;
          double total = subtotal + taxAmount - discount;

          return AlertDialog(
            title: const Text('Create Invoice'),
            content: Container(
              width: double.maxFinite,
              constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, idx) {
                        final item = items[idx];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                                        onChanged: (val) => setStateDialog(() => item.description = val),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (items.length > 1)
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                                        onPressed: () => removeItem(idx),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                                        keyboardType: TextInputType.number,
                                        onChanged: (val) => setStateDialog(() => item.quantity = int.tryParse(val) ?? 0),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextField(
                                        decoration: const InputDecoration(labelText: 'Unit Price (KES)', border: OutlineInputBorder()),
                                        keyboardType: TextInputType.number,
                                        onChanged: (val) => setStateDialog(() => item.unitPrice = double.tryParse(val) ?? 0.0),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Item'),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Text('Include VAT (16%):'),
                      Checkbox(
                        value: includeTax,
                        onChanged: (val) => setStateDialog(() => includeTax = val ?? true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Subtotal: KES ${subtotal.toStringAsFixed(2)}'),
                  if (includeTax) Text('VAT: KES ${taxAmount.toStringAsFixed(2)}'),
                  if (discount > 0) Text('Discount: KES ${discount.toStringAsFixed(2)}'),
                  const Divider(),
                  Text('TOTAL: KES ${total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () {
                if (ctx.mounted) Navigator.pop(ctx);
              }, child: const Text('Cancel')),
              ElevatedButton(
                onPressed: () async {
                  if (items.any((i) => i.description.isEmpty || i.quantity <= 0 || i.unitPrice <= 0)) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('Please fill all item fields correctly'), backgroundColor: Colors.orange),
                    );
                    return;
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  await _sendInvoiceAndRecordDebt(total, items, includeTax, discount, taxRate);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('Send Invoice & Add Debt'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _sendInvoiceAndRecordDebt(double total, List<InvoiceLineItem> items, bool includeTax, double discount, double taxRate) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final customerName = widget.customer['name'];
      final date = DateTime.now().toLocal();
      final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
      String invoice = '🧾 *INVOICE* 🧾\n\n';
      invoice += 'Customer: $customerName\n';
      invoice += 'Date: $formattedDate\n\n';
      invoice += '--------------------------------\n';
      invoice += 'Item               Qty   Price    Total\n';
      invoice += '--------------------------------\n';
      for (var item in items) {
        invoice += '${item.description.padRight(18)} ${item.quantity.toString().padLeft(3)}  KES ${item.unitPrice.toStringAsFixed(2).padLeft(7)}  KES ${item.total.toStringAsFixed(2).padLeft(8)}\n';
      }
      invoice += '--------------------------------\n';
      double subtotal = items.fold(0, (sum, i) => sum + i.total);
      double taxAmount = includeTax ? subtotal * taxRate : 0.0;
      invoice += 'Subtotal: ${subtotal.toStringAsFixed(2)}\n';
      if (includeTax) invoice += 'VAT (16%): ${taxAmount.toStringAsFixed(2)}\n';
      if (discount > 0) invoice += 'Discount: ${discount.toStringAsFixed(2)}\n';
      invoice += 'TOTAL: KES ${total.toStringAsFixed(2)}\n';
      invoice += '\nThank you for your business!';

      await _sendMessageViaAPI(invoice, widget.customer['id']);

      final customerId = widget.customer['id'];
      final currentDebt = (widget.customer['debtAmount'] ?? 0.0).toDouble();
      final newDebt = currentDebt + total;

      await FirebaseFirestore.instance.collection('customers').doc(customerId).update({
        'debtAmount': newDebt,
      });
      await FirebaseFirestore.instance.collection('transactions').add({
        'customerId': customerId,
        'type': 'add_debt',
        'amount': total,
        'previousDebt': currentDebt,
        'newDebt': newDebt,
        'note': 'Invoice (${items.length} items)',
        'tenantId': currentTenantId,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() {
          widget.customer['debtAmount'] = newDebt;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invoice sent and debt added!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // Existing methods
  String _generateDebtStatement(double currentDebt, double lastAmount, String lastAction, String? note, List<Map<String, dynamic>> recentTransactions) {
    final customerName = widget.customer['name'];
    final date = DateTime.now().toLocal();
    final formattedDate = '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute}';
    String statement = '🧾 *DEBT STATEMENT* 🧾\n\n';
    statement += 'Dear $customerName,\n\n';
    statement += 'Your current outstanding balance is *KES ${currentDebt.toStringAsFixed(2)}*.\n\n';
    statement += '📌 *Last transaction:*\n';
    statement += '   ${lastAction == 'add_debt' ? 'Debit' : 'Payment'} of KES ${lastAmount.toStringAsFixed(2)} on $formattedDate\n';
    if (note != null && note.isNotEmpty) statement += '   Note: $note\n';
    statement += '\n📋 *Recent activity:*\n';
    for (var tx in recentTransactions.take(3)) {
      final type = tx['type'];
      final amount = (tx['amount'] as num).toDouble();
      final ts = (tx['timestamp'] as Timestamp?)?.toDate();
      final dateStr = ts != null ? '${ts.day}/${ts.month}/${ts.year}' : 'unknown';
      final action = type == 'add_debt' ? 'Debit' : (type == 'reduce_debt' ? 'Payment' : 'M-PESA Payment');
      statement += '   • $action: KES $amount ($dateStr)\n';
    }
    statement += '\nThank you for your business. Pay via M‑PESA or bank transfer.\n';
    statement += '_This is an automated message from BiasharaOS._';
    return statement;
  }

  String _generateBalanceMessage(double currentDebt) {
    final customerName = widget.customer['name'];
    return '📊 *Balance Update* 📊\n\nHi $customerName,\nYour current outstanding balance is *KES ${currentDebt.toStringAsFixed(2)}*.\n\nThank you.';
  }

  Future<void> _logDebt() async {
    if (_isProcessing) return;
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.red),
      );
      return;
    }

    final note = _noteController.text.trim();
    final customerId = widget.customer['id'];
    final currentDebt = (widget.customer['debtAmount'] ?? 0.0).toDouble();
    final newDebt = currentDebt + amount;

    setState(() => _isProcessing = true);
    try {
      await FirebaseFirestore.instance.collection('customers').doc(customerId).update({
        'debtAmount': newDebt,
      });
      await FirebaseFirestore.instance.collection('transactions').add({
        'customerId': customerId,
        'type': 'add_debt',
        'amount': amount,
        'previousDebt': currentDebt,
        'newDebt': newDebt,
        'note': note,
        'tenantId': currentTenantId,
        'timestamp': FieldValue.serverTimestamp(),
      });
      final recentTxSnapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('customerId', isEqualTo: customerId)
          .where('tenantId', isEqualTo: currentTenantId)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();
      final recentTransactions = recentTxSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      final statement = _generateDebtStatement(newDebt, amount, 'add_debt', note, recentTransactions);
      await _sendMessageViaAPI(statement, customerId);

      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Debt logged and statement sent!'), backgroundColor: Colors.green),
        );
        setState(() {
          widget.customer['debtAmount'] = newDebt;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendBalance() async {
    final currentDebt = (widget.customer['debtAmount'] ?? 0.0).toDouble();
    final message = _generateBalanceMessage(currentDebt);
    await _sendWhatsAppMessage(message);
  }

  Future<void> _sendCustomMessage() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a message'), backgroundColor: Colors.orange),
      );
      return;
    }
    await _sendWhatsAppMessage(message);
    if (mounted) _messageController.clear();
  }

  void _showLogDebtDialog() {
    _amountController.clear();
    _noteController.clear();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Debt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount (KES)',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                prefixIcon: Icon(Icons.note),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () {
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('Cancel')),
          ElevatedButton(
            onPressed: _logDebt,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Add Debt'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.customer['name'] ?? 'Customer';
    final currentDebt = (widget.customer['debtAmount'] ?? 0.0).toDouble();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(customerName),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.message),
            onPressed: _sendBalance,
            tooltip: 'Send Balance',
          ),
        ],
      ),
      body: Column(
        children: [
          // Debt card with three buttons
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              children: [
                const Text('Current Debt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                  'KES ${currentDebt.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: _showLogDebtDialog,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Log Debt', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: ElevatedButton.icon(
                          onPressed: _showInvoiceBuilder,
                          icon: const Icon(Icons.receipt, size: 16),
                          label: const Text('Invoice', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: OutlinedButton.icon(
                          onPressed: _sendBalance,
                          icon: const Icon(Icons.send, size: 16),
                          label: const Text('Send Balance', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.green,
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Transaction list
          Expanded(
            child: _transactions.isEmpty
                ? const Center(child: Text('No transactions yet'))
                : ListView.builder(
                    itemCount: _transactions.length,
                    itemBuilder: (_, i) {
                      final tx = _transactions[i].data() as Map<String, dynamic>;
                      final type = tx['type'];
                      final amount = (tx['amount'] as num).toDouble();
                      final ts = (tx['timestamp'] as Timestamp?)?.toDate();
                      final note = tx['note'] ?? '';
                      final isDebt = type == 'add_debt';
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: ListTile(
                          leading: Icon(isDebt ? Icons.add_circle : Icons.payment, color: isDebt ? Colors.red : Colors.green),
                          title: Text('${isDebt ? 'Debt Added' : 'Payment'} - KES ${amount.toStringAsFixed(2)}'),
                          subtitle: Text('${ts?.toLocal().toString() ?? 'Unknown date'} ${note.isNotEmpty ? '\nNote: $note' : ''}'),
                        ),
                      );
                    },
                  ),
          ),
          // Chat input field – add bottom margin to avoid FAB overlap
          Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(top: BorderSide(color: Colors.grey[300]!)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: TextField(
                        controller: _messageController,
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        maxLines: null,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendCustomMessage(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _sendCustomMessage,
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _sendBalance,
        backgroundColor: Colors.green,
        child: const Icon(Icons.message),
        tooltip: 'Send Balance via WhatsApp',
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}