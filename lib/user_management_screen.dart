import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? currentTenantId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadCurrentTenant();
  }

  Future<void> _loadCurrentTenant() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists) {
        currentTenantId = doc.data()?['tenantId'];
        await _loadUsers();
      } else {
        setState(() => _errorMessage = 'User profile not found. Please log out and log in again.');
        _loading = false;
      }
    }
  }

  Future<void> _loadUsers() async {
    if (currentTenantId == null) return;
    setState(() => _loading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('tenantId', isEqualTo: currentTenantId)
          .get();
      setState(() {
        _users = snapshot.docs.map((d) => ({
          'id': d.id,
          'name': d['name'],
          'email': d['email'],
          'role': d['role'],
        })).toList();
        _errorMessage = null;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Unable to load team members: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _addEditUser({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name']);
    final emailCtrl = TextEditingController(text: existing?['email']);
    final roleCtrl = TextEditingController(text: existing?['role'] ?? 'sales');
    final passCtrl = TextEditingController();
    final isEdit = existing != null;

    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(isEdit ? 'Edit User' : 'Add User'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 8),
              TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Email')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: roleCtrl.text,
                items: ['sales', 'support', 'delivery', 'admin']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase())))
                    .toList(),
                onChanged: (v) => roleCtrl.text = v!,
                decoration: const InputDecoration(labelText: 'Role'),
              ),
              if (!isEdit) ...[
                const SizedBox(height: 8),
                TextField(controller: passCtrl, decoration: const InputDecoration(labelText: 'Password'), obscureText: true),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              try {
                if (isEdit) {
                  await FirebaseFirestore.instance.collection('users').doc(existing['id']).update({
                    'name': nameCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'role': roleCtrl.text.trim(),
                  });
                } else {
                  final userCred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
                    email: emailCtrl.text.trim(),
                    password: passCtrl.text.trim(),
                  );
                  await FirebaseFirestore.instance.collection('users').doc(userCred.user!.uid).set({
                    'name': nameCtrl.text.trim(),
                    'email': emailCtrl.text.trim(),
                    'role': roleCtrl.text.trim(),
                    'tenantId': currentTenantId,
                    'createdAt': FieldValue.serverTimestamp(),
                  });
                }
                Navigator.pop(c, true);
              } on FirebaseAuthException catch (e) {
                String message;
                if (e.code == 'email-already-in-use') {
                  message = 'This email is already registered. Use a different email.';
                } else {
                  message = e.message ?? 'Failed to create user.';
                }
                ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(content: Text(message), backgroundColor: Colors.red),
                );
              } catch (e) {
                ScaffoldMessenger.of(c).showSnackBar(
                  SnackBar(content: Text('Failed to save user: $e'), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == true) await _loadUsers();
  }

  Future<void> _deleteUser(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete User'),
        content: Text('Delete $name?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await FirebaseFirestore.instance.collection('users').doc(id).delete();
        await _loadUsers();
      } on FirebaseException catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You do not have permission to delete this user.'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('User Management'), backgroundColor: Colors.green),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: Colors.green,
        actions: [
          IconButton(onPressed: _loadUsers, icon: const Icon(Icons.refresh)),
          IconButton(onPressed: () => _addEditUser(), icon: const Icon(Icons.add)),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: _users.length,
              itemBuilder: (_, i) {
                final u = _users[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(u['name'][0])),
                  title: Text(u['name']),
                  subtitle: Text('${u['email']} • ${u['role'].toUpperCase()}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteUser(u['id'], u['name']),
                  ),
                  onTap: () => _addEditUser(existing: u),
                );
              },
            ),
    );
  }
}