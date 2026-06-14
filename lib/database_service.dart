import 'package:cloud_firestore/cloud_firestore.dart';

class DatabaseService {
  final CollectionReference _customersCollection = 
      FirebaseFirestore.instance.collection('customers');
  final CollectionReference _teamMembersCollection = 
      FirebaseFirestore.instance.collection('team_members');

  // ============ CUSTOMER OPERATIONS ============
  
  // Stream all customers (real-time updates)
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

  // Add new customer
  Future<void> addCustomer(Map<String, dynamic> customer) async {
    await _customersCollection.add({
      'name': customer['name'],
      'business': customer['business'],
      'phone': customer['phone'],
      'lastMessage': customer['lastMessage'],
      'lastMessageTime': customer['lastMessageTime'],
      'time': customer['time'],
      'unread': customer['unread'],
      'assignedTo': customer['assignedTo'],
      'assignedToPerson': customer['assignedToPerson'],
      'tags': customer['tags'],
      'notes': customer['notes'],
      'debtAmount': customer['debtAmount'],
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Update customer
  Future<void> updateCustomer(String id, Map<String, dynamic> data) async {
    await _customersCollection.doc(id).update(data);
  }

  // Delete customer
  Future<void> deleteCustomer(String id) async {
    await _customersCollection.doc(id).delete();
  }

  // Get single customer
  Future<Map<String, dynamic>?> getCustomer(String id) async {
    final doc = await _customersCollection.doc(id).get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      data['id'] = doc.id;
      return data;
    }
    return null;
  }

  // ============ TEAM MEMBERS OPERATIONS ============
  
  // Stream team members
  Stream<List<Map<String, dynamic>>> getTeamMembers() {
    return _teamMembersCollection.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return data;
      }).toList();
    });
  }

  // Add sample data if empty
  Future<void> addSampleDataIfEmpty() async {
    final snapshot = await _customersCollection.get();
    if (snapshot.docs.isEmpty) {
      await _addSampleCustomers();
    }
    
    final teamSnapshot = await _teamMembersCollection.get();
    if (teamSnapshot.docs.isEmpty) {
      await _addSampleTeamMembers();
    }
  }

  Future<void> _addSampleCustomers() async {
    final sampleCustomers = [
      {
        'name': 'John Doe',
        'business': 'ABC Electronics',
        'phone': '+254 712 345 678',
        'lastMessage': 'Hello, I need 10 more units',
        'lastMessageTime': DateTime.now().subtract(const Duration(hours: 2)),
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
        'lastMessageTime': DateTime.now().subtract(const Duration(hours: 5)),
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
        'lastMessageTime': DateTime.now().subtract(const Duration(days: 1)),
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
      await _customersCollection.add(customer);
    }
  }

  Future<void> _addSampleTeamMembers() async {
    final sampleTeam = [
      {'name': 'James Kamau', 'role': 'sales', 'avatar': 'JK'},
      {'name': 'Mary Akinyi', 'role': 'sales', 'avatar': 'MA'},
      {'name': 'Sarah Wanjiku', 'role': 'support', 'avatar': 'SW'},
      {'name': 'John Otieno', 'role': 'support', 'avatar': 'JO'},
      {'name': 'Peter Odhiambo', 'role': 'delivery', 'avatar': 'PO'},
      {'name': 'David Mwangi', 'role': 'delivery', 'avatar': 'DM'},
    ];

    for (var member in sampleTeam) {
      await _teamMembersCollection.add(member);
    }
  }
}