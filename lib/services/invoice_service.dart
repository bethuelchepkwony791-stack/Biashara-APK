import 'package:cloud_firestore/cloud_firestore.dart';

class InvoiceService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static Future<String> getNextInvoiceNumber() async {
    final counterRef = _firestore.collection('counters').doc('invoiceNumber');
    final result = await _firestore.runTransaction((transaction) async {
      final doc = await transaction.get(counterRef);
      int current = doc.exists ? (doc.data()?['value'] ?? 0) : 0;
      int next = current + 1;
      transaction.set(counterRef, {'value': next});
      return next;
    });
    return 'INV-${result.toString().padLeft(4, '0')}';
  }
}