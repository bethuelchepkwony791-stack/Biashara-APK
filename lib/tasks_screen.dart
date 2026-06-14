import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String? currentUserId;
  String? tenantId;

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      setState(() {
        currentUserId = user.uid;
        tenantId = userDoc.data()?['tenantId'];
      });
    }
  }

  Future<void> _completeTask(String taskId) async {
    await FirebaseFirestore.instance.collection('tasks').doc(taskId).update({
      'status': 'completed',
      'completedAt': FieldValue.serverTimestamp(),
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Task marked as completed'), backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _openCustomerChat(String customerId, String customerName, {String? taskId}) async {
    // If a task ID is provided, ask to complete it before opening chat
    if (taskId != null) {
      final shouldComplete = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Complete Task?'),
          content: Text('Do you want to mark the task for "$customerName" as completed?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Later'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Yes, Complete'),
            ),
          ],
        ),
      );
      if (shouldComplete == true) {
        await _completeTask(taskId);
      }
    }
    
    // Fetch full customer data
    try {
      final customerDoc = await FirebaseFirestore.instance.collection('customers').doc(customerId).get();
      if (customerDoc.exists) {
        final data = customerDoc.data()!;
        final customerMap = {
          'id': customerId,
          'name': data['name'] ?? customerName,
          'business': data['business'] ?? '',
          'phoneNumbers': List<String>.from(data['phoneNumbers'] ?? []),
          'lastMessage': data['lastMessage'] ?? '',
          'time': data['time'] ?? '',
          'unread': data['unread'] ?? 0,
          'assignedTo': data['assignedTo'] ?? '',
          'assignedToPerson': data['assignedToPerson'] ?? '',
          'tags': List<String>.from(data['tags'] ?? []),
          'notes': data['notes'] ?? '',
          'debtAmount': (data['debtAmount'] ?? 0).toDouble(),
        };
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(customer: customerMap)),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Customer not found'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening chat: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {}),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tasks')
            .where('assignedToUserId', isEqualTo: currentUserId)
            .where('tenantId', isEqualTo: tenantId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('No tasks assigned to you'));
          }
          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final task = docs[i].data() as Map<String, dynamic>;
              final status = task['status'] ?? 'pending';
              final isCompleted = status == 'completed';
              final customerId = task['customerId'] ?? '';
              final customerName = task['customerName'] ?? 'Unknown Customer';
              final message = task['message'] ?? 'No message';
              final createdAt = (task['createdAt'] as Timestamp?)?.toDate();
              final taskId = docs[i].id;

              return Card(
                margin: const EdgeInsets.all(8),
                child: InkWell(
                  onTap: isCompleted
                      ? null
                      : () => _openCustomerChat(customerId, customerName, taskId: taskId),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                customerName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            if (!isCompleted)
                              IconButton(
                                icon: const Icon(Icons.chat, color: Colors.blue),
                                onPressed: () => _openCustomerChat(customerId, customerName, taskId: taskId),
                                tooltip: 'Assist Customer',
                              ),
                            if (!isCompleted)
                              ElevatedButton(
                                onPressed: () => _completeTask(taskId),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                child: const Text('Mark Done'),
                              ),
                            if (isCompleted)
                              const Icon(Icons.check_circle, color: Colors.green),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(message),
                        const SizedBox(height: 4),
                        Text(
                          'Assigned on: ${createdAt?.toLocal().toString() ?? 'Unknown'}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (isCompleted)
                          const Text('Completed', style: TextStyle(color: Colors.green, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}