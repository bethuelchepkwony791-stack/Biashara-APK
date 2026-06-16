import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class InvoiceLineItem {
  String description;
  int quantity;
  double unitPrice;
  InvoiceLineItem({required this.description, required this.quantity, required this.unitPrice});
  double get total => quantity * unitPrice;
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
  final ScrollController _scrollController = ScrollController();

  final String backendBaseUrl = 'https://biashara-whatsapp-webhook.onrender.com';

  Stream<QuerySnapshot<Map<String, dynamic>>> get transactionsStream {
    final customerId = widget.customer['id'];
    if (customerId == null || currentTenantId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('transactions')
        .where('customerId', isEqualTo: customerId)
        .where('tenantId', isEqualTo: currentTenantId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> get messagesStream {
    final customerId = widget.customer['id'];
    if (customerId == null) return const Stream.empty();
    return FirebaseFirestore.instance
        .collection('chats')
        .doc(customerId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .snapshots();
  }

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
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

  String? _getCustomerPhone() {
    final phones = widget.customer['phoneNumbers'] as List<String>?;
    if (phones == null || phones.isEmpty) return null;
    String phone = phones.first.trim();
    phone = phone.replaceAll(RegExp(r'\D'), '');
    if (phone.startsWith('0')) phone = '254' + phone.substring(1);
    if (!phone.startsWith('254')) phone = '254' + phone;
    return phone;
  }

  Future<String> _getFreshIdToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Not logged in');
    final token = await user.getIdToken(true);
    if (token == null) throw Exception('Failed to get ID token');
    return token;
  }

  Future<void> _sendMessageViaAPI(String message, String customerId) async {
    final phone = _getCustomerPhone();
    if (phone == null) throw Exception('Customer has no valid phone number');

    final idToken = await _getFreshIdToken();
    final url = '$backendBaseUrl/send-message';
    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'to': phone,
        'text': message,
        'customerId': customerId,
      }),
    );

    if (response.statusCode != 200) {
      final error = jsonDecode(response.body)['error'] ?? 'Unknown error';
      throw Exception('$response.statusCode: $error');
    }
  }

  // ======== Send message ========
  Future<void> _sendWhatsAppMessage(String message, {bool storeMessage = true}) async {
    try {
      final customerId = widget.customer['id'];
      if (storeMessage) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(customerId)
            .collection('messages')
            .add({
          'text': message,
          'direction': 'outgoing',
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'sending',
        });
      }
      await _sendMessageViaAPI(message, customerId);

      final snapshot = await FirebaseFirestore.instance
          .collection('chats')
          .doc(customerId)
          .collection('messages')
          .where('text', isEqualTo: message)
          .where('direction', isEqualTo: 'outgoing')
          .where('status', isEqualTo: 'sending')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (!snapshot.docs.isEmpty) {
        await snapshot.docs.first.reference.update({'status': 'sent'});
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sent!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (storeMessage) {
        final customerId = widget.customer['id'];
        final snapshot = await FirebaseFirestore.instance
            .collection('chats')
            .doc(customerId)
            .collection('messages')
            .where('text', isEqualTo: message)
            .where('direction', isEqualTo: 'outgoing')
            .where('status', isEqualTo: 'sending')
            .orderBy('timestamp', descending: true)
            .limit(1)
            .get();
        if (!snapshot.docs.isEmpty) {
          await snapshot.docs.first.reference.update({'status': 'failed'});
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
      rethrow;
    }
  }

  // ======== Retry failed message ========
  Future<void> _retryFailedMessage(String docId, String message) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      await _sendMessageViaAPI(message, widget.customer['id']);
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.customer['id'])
          .collection('messages')
          .doc(docId)
          .update({'status': 'sent'});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Message sent!'), backgroundColor: Colors.green));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retry failed: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ======== DEBT LOGGING ========
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
      if (mounted) Navigator.pop(context); // close dialog

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

      final recent = await FirebaseFirestore.instance
          .collection('transactions')
          .where('customerId', isEqualTo: customerId)
          .where('tenantId', isEqualTo: currentTenantId)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .get();
      final recentList = recent.docs.map((d) => d.data() as Map<String, dynamic>).toList();

      final statement = _generateDebtStatement(newDebt, amount, 'add_debt', note, recentList);

      try {
        await _sendWhatsAppMessage(statement, storeMessage: true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Debt logged & statement sent!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Debt logged but statement failed: $e'), backgroundColor: Colors.orange),
          );
        }
      }

      if (mounted) {
        setState(() => widget.customer['debtAmount'] = newDebt);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Debt logging failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendBalance() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final debt = (widget.customer['debtAmount'] ?? 0.0).toDouble();
      final message = '📊 *Balance Update* 📊\n\nHi ${widget.customer['name']},\nYour current balance is KES ${debt.toStringAsFixed(2)}.\n\nThank you.';
      await _sendWhatsAppMessage(message, storeMessage: true);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _sendCustomMessage() async {
    if (_isProcessing) return;
    final msg = _messageController.text.trim();
    if (msg.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a message'), backgroundColor: Colors.orange));
      return;
    }
    setState(() => _isProcessing = true);
    try {
      await _sendWhatsAppMessage(msg, storeMessage: true);
      _messageController.clear();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
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
            TextField(controller: _amountController, decoration: const InputDecoration(labelText: 'Amount (KES)'), keyboardType: TextInputType.number, autofocus: true),
            const SizedBox(height: 12),
            TextField(controller: _noteController, decoration: const InputDecoration(labelText: 'Note (optional)'), maxLines: 2),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: _logDebt, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Add Debt')),
        ],
      ),
    );
  }

  // ======== Invoice builder placeholder ========
  Future<void> _showInvoiceBuilder() async {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invoice builder (implemented)'), backgroundColor: Colors.orange));
  }

  @override
  Widget build(BuildContext context) {
    final customerName = widget.customer['name'] ?? 'Customer';
    final currentDebt = (widget.customer['debtAmount'] ?? 0.0).toDouble();

    return Scaffold(
      appBar: AppBar(
        title: Text(customerName),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.receipt), onPressed: _showInvoiceBuilder, tooltip: 'Invoice'),
          IconButton(icon: const Icon(Icons.message), onPressed: _sendBalance, tooltip: 'Balance'),
        ],
      ),
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                const Text('Current Debt', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 4),
                Text('KES ${currentDebt.toStringAsFixed(2)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
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
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
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
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(tabs: [Tab(text: 'Chat'), Tab(text: 'Transactions')]),
                  Expanded(
                    child: TabBarView(
                      children: [
                        // Chat tab
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: messagesStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.error_outline, color: Colors.red, size: 48),
                                    const SizedBox(height: 12),
                                    Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                                    const SizedBox(height: 12),
                                    ElevatedButton(
                                      onPressed: () => setState(() {}),
                                      child: const Text('Retry'),
                                    ),
                                  ],
                                ),
                              );
                            }
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) return const Center(child: Text('No messages yet'));
                            return ListView.builder(
                              controller: _scrollController,
                              itemCount: docs.length,
                              itemBuilder: (_, i) {
                                final doc = docs[i];
                                final msg = doc.data();
                                final docId = doc.id;
                                final isOutgoing = msg['direction'] == 'outgoing';
                                final text = msg['text'] ?? '';
                                final timestamp = (msg['timestamp'] as Timestamp?)?.toDate();
                                final status = msg['status'] ?? '';
                                return Align(
                                  key: ValueKey(docId),
                                  alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: isOutgoing ? Colors.green[100] : Colors.grey[200],
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(text),
                                        const SizedBox(height: 4),
                                        // ======== FIXED ROW (no overflow) ========
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                timestamp != null
                                                    ? '${timestamp.hour}:${timestamp.minute.toString().padLeft(2, '0')}'
                                                    : '',
                                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (status == 'failed')
                                              GestureDetector(
                                                onTap: () => _retryFailedMessage(docId, text),
                                                child: Container(
                                                  margin: const EdgeInsets.only(left: 8),
                                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                  decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                                  child: const Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Icon(Icons.refresh, color: Colors.white, size: 12),
                                                      SizedBox(width: 4),
                                                      Text('Retry', style: TextStyle(fontSize: 8, color: Colors.white)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            if (status == 'sending')
                                              Container(
                                                margin: const EdgeInsets.only(left: 8),
                                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)),
                                                child: const Text('Sending...', style: TextStyle(fontSize: 8, color: Colors.white)),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                        // Transactions tab
                        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                          stream: transactionsStream,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
                            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                            final docs = snapshot.data?.docs ?? [];
                            if (docs.isEmpty) return const Center(child: Text('No transactions yet'));
                            return ListView.builder(
                              itemCount: docs.length,
                              itemBuilder: (_, i) {
                                final tx = docs[i].data();
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
                                    subtitle: Text('${ts?.toLocal().toString() ?? 'Unknown'} ${note.isNotEmpty ? '\n$note' : ''}'),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(color: Colors.grey[100], border: Border(top: BorderSide(color: Colors.grey[300]!))),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: Colors.grey[300]!)),
                child: TextField(
                  controller: _messageController,
                  decoration: const InputDecoration(hintText: 'Type a message...', border: InputBorder.none, contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  maxLines: null,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendCustomMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _sendCustomMessage,
              child: Container(padding: const EdgeInsets.all(10), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20)),
            ),
          ],
        ),
      ),
    );
  }
}