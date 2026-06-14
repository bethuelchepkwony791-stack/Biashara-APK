import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final CollectionReference _customersCollection = 
      FirebaseFirestore.instance.collection('customers');
  
  final CollectionReference _activityLogsCollection = 
      FirebaseFirestore.instance.collection('activity_logs');

  // ============ CUSTOMER CRUD OPERATIONS ============
  
  // Get all customers (real-time stream)
  Stream<List<Map<String, dynamic>>> getCustomers() {
    return _customersCollection
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Get customers by assignment
  Stream<List<Map<String, dynamic>>> getCustomersByAssignment(String assignedTo) {
    return _customersCollection
        .where('assignedTo', isEqualTo: assignedTo)
        .orderBy('lastMessageTime', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Get single customer by ID
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    final doc = await _customersCollection.doc(id).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }
    return null;
  }

  // Add new customer
  Future<String> addCustomer(Map<String, dynamic> customer) async {
    final docRef = await _customersCollection.add({
      ...customer,
      'createdAt': FieldValue.serverTimestamp(),
      'lastMessageTime': DateTime.now(),
      'unread': 0,
    });
    
    // Log activity
    await _logActivity('customer_created', {
      'customerId': docRef.id,
      'customerName': customer['name'],
    });
    
    return docRef.id;
  }

  // Update customer
  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    await _customersCollection.doc(id).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    // Log activity
    await _logActivity('customer_updated', {
      'customerId': id,
      'updates': data.keys.toList(),
    });
  }

  // Delete customer
  Future<void> deleteCustomer(String id) async {
    // Get customer name before deleting for logging
    final customer = await getCustomer(id);
    
    await _customersCollection.doc(id).delete();
    
    // Log activity
    await _logActivity('customer_deleted', {
      'customerId': id,
      'customerName': customer?['name'],
    });
  }

  // Add note to customer
  Future<void> addNote(String customerId, String note) async {
    final customer = await _customersCollection.doc(customerId).get();
    if (customer.exists) {
      final data = customer.data() as Map<String, dynamic>;
      final existingNotes = data['notes'] ?? '';
      final updatedNotes = existingNotes.isEmpty ? note : '$existingNotes\n$note';
      
      await updateCustomer(customerId, {'notes': updatedNotes});
    }
  }

  // Update debt amount
  Future<void> updateDebt(String customerId, double newDebtAmount) async {
    await updateCustomer(customerId, {'debtAmount': newDebtAmount});
  }

  // Update assignment
  Future<void> updateAssignment(String customerId, String department, String personName) async {
    await updateCustomer(customerId, {
      'assignedTo': department,
      'assignedToPerson': personName,
    });
  }

  // Mark message as read
  Future<void> markAsRead(String customerId) async {
    await updateCustomer(customerId, {'unread': 0});
  }

  // ============ BATCH OPERATIONS ============
  
  // Save multiple customers (batch write)
  Future<void> saveCustomersBatch(List<Map<String, dynamic>> customers) async {
    final batch = FirebaseFirestore.instance.batch();
    
    for (var customer in customers) {
      final docRef = _customersCollection.doc();
      batch.set(docRef, {
        ...customer,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageTime': DateTime.now(),
      });
    }
    
    await batch.commit();
  }

  // Delete all customers (use with caution)
  Future<void> deleteAllCustomers() async {
    final snapshot = await _customersCollection.get();
    final batch = FirebaseFirestore.instance.batch();
    
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    
    await batch.commit();
  }

  // ============ ACTIVITY LOGGING ============
  
  Future<void> _logActivity(String action, Map<String, dynamic> data) async {
    await _activityLogsCollection.add({
      'action': action,
      'data': data,
      'timestamp': FieldValue.serverTimestamp(),
      'userId': 'current_user', // Will be replaced with actual user ID after auth
    });
  }

  // Get activity logs
  Stream<List<Map<String, dynamic>>> getActivityLogs() {
    return _activityLogsCollection
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // ============ SAMPLE DATA ============
  
  Future<void> addSampleData() async {
    final sampleCustomers = [
      {
        'name': 'John Doe',
        'business': 'ABC Electronics',
        'phone': '+254 712 345 678',
        'lastMessage': 'Hello, I need 10 more units',
        'time': '2:30 PM',
        'unread': 2,
        'assignedTo': 'sales',
        'assignedToPerson': 'James Kamau',
        'tags': ['VIP', 'Pending Payment'],
        'notes': 'Prefers weekend delivery. Regular customer since 2024.',
        'debtAmount': 15000,
      },
      {
        'name': 'Maria Garcia',
        'business': 'Downtown Cafe',
        'phone': '+254 723 456 789',
        'lastMessage': 'When will delivery arrive?',
        'time': '11:15 AM',
        'unread': 0,
        'assignedTo': 'support',
        'assignedToPerson': 'Sarah Wanjiku',
        'tags': ['New Customer'],
        'notes': 'First time customer. Very responsive.',
        'debtAmount': 0,
      },
      {
        'name': 'Ahmed Hassan',
        'business': 'Hassan Hardware',
        'phone': '+254 734 567 890',
        'lastMessage': 'Please confirm ETA',
        'time': 'Yesterday',
        'unread': 1,
        'assignedTo': 'delivery',
        'assignedToPerson': 'Peter Odhiambo',
        'tags': ['Delivery', 'Debt'],
        'notes': 'Owes for last delivery. Called multiple times.',
        'debtAmount': 5000,
      },
    ];

    for (var customer in sampleCustomers) {
      await addCustomer(customer);
    }
  }
}