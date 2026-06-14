import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() {
  runApp(const BiasharaOS());
}

class BiasharaOS extends StatelessWidget {
  const BiasharaOS({super.key}); 

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BiasharaOS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const WhatsAppInbox(),
    );
  }
}

class WhatsAppInbox extends StatefulWidget {
  const WhatsAppInbox({super.key});

  @override
  State<WhatsAppInbox> createState() => _WhatsAppInboxState();
}

class _WhatsAppInboxState extends State<WhatsAppInbox> {
  List<Map<String, dynamic>> _customers = [
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

  final List<Map<String, dynamic>> _teamMembers = [
    {'name': 'James Kamau', 'role': 'sales', 'avatar': 'JK'},
    {'name': 'Mary Akinyi', 'role': 'sales', 'avatar': 'MA'},
    {'name': 'Sarah Wanjiku', 'role': 'support', 'avatar': 'SW'},
    {'name': 'John Otieno', 'role': 'support', 'avatar': 'JO'},
    {'name': 'Peter Odhiambo', 'role': 'delivery', 'avatar': 'PO'},
    {'name': 'David Mwangi', 'role': 'delivery', 'avatar': 'DM'},
  ];

  String _selectedFilter = 'all';
  String _selectedPersonFilter = 'all';
  String _searchQuery = '';
  Map<String, dynamic>? _selectedCustomer;
  final TextEditingController _noteController = TextEditingController();

  List<Map<String, dynamic>> get _filteredCustomers {
    List<Map<String, dynamic>> result = _customers;
    
    if (_selectedFilter != 'all') {
      result = result.where((c) => c['assignedTo'] == _selectedFilter).toList();
    }
    
    if (_selectedPersonFilter != 'all') {
      result = result.where((c) => c['assignedToPerson'] == _selectedPersonFilter).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      result = result.where((c) =>
        c['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
        c['business'].toLowerCase().contains(_searchQuery.toLowerCase())
      ).toList();
    }
    return result;
  }

  List<Map<String, dynamic>> get _teamMembersByRole {
    if (_selectedFilter == 'all') {
      return [];
    }
    return _teamMembers.where((m) => m['role'] == _selectedFilter).toList();
  }

  Map<String, dynamic> get _stats {
    return {
      'total': _customers.length,
      'unread': _customers.where((c) => c['unread'] > 0).length,
      'debtTotal': _customers.fold<double>(0, (sum, c) => sum + (c['debtAmount'] ?? 0)),
      'vipCount': _customers.where((c) => (c['tags'] as List).contains('VIP')).length,
    };
  }

  Color _getAssignmentColor(String assignedTo) {
    switch (assignedTo) {
      case 'sales': return Colors.blue;
      case 'support': return Colors.green;
      case 'delivery': return Colors.orange;
      default: return Colors.grey;
    }
  }

  Color _getTagColor(String tag) {
    switch (tag) {
      case 'VIP': return Colors.orange;
      case 'Pending Payment': return Colors.red;
      case 'New Customer': return Colors.green;
      case 'Delivery': return Colors.blue;
      case 'Debt': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getMessageStatusIcon(int unread) {
    return unread > 0 ? Icons.mark_email_unread : Icons.mark_email_read;
  }

  Color _getMessageStatusColor(int unread) {
    return unread > 0 ? Colors.green : Colors.grey;
  }

  Widget _buildStatItem(IconData icon, String label, dynamic value) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.green[700]),
        const SizedBox(height: 4),
        Text(
          value.toString(),
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ============ FIREBASE SAVE FUNCTION ============
  
  Future<void> _saveToFirebase() async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saving to Firebase...')),
      );
      
      final customersRef = FirebaseFirestore.instance.collection('customers');
      
      // Save each customer to Firebase
      int count = 0;
      for (var customer in _customers) {
        await customersRef.add({
          'name': customer['name'],
          'business': customer['business'],
          'phone': customer['phone'],
          'lastMessage': customer['lastMessage'],
          'time': customer['time'],
          'unread': customer['unread'],
          'assignedTo': customer['assignedTo'],
          'assignedToPerson': customer['assignedToPerson'],
          'tags': customer['tags'],
          'notes': customer['notes'],
          'debtAmount': customer['debtAmount'],
          'createdAt': DateTime.now().toIso8601String(),
        });
        count++;
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $count customers to Firebase!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ============ LOAD FROM FIREBASE FUNCTION ============
  
  Future<void> _loadFromFirebase() async {
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loading from Firebase...')),
      );
      
      final snapshot = await FirebaseFirestore.instance.collection('customers').get();
      
      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No data in Firebase')),
        );
        return;
      }
      
      List<Map<String, dynamic>> loadedCustomers = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        loadedCustomers.add({
          'name': data['name'] ?? '',
          'business': data['business'] ?? '',
          'phone': data['phone'] ?? '',
          'lastMessage': data['lastMessage'] ?? '',
          'time': data['time'] ?? '',
          'unread': data['unread'] ?? 0,
          'assignedTo': data['assignedTo'] ?? 'unassigned',
          'assignedToPerson': data['assignedToPerson'] ?? '',
          'tags': data['tags'] ?? [],
          'notes': data['notes'] ?? '',
          'debtAmount': data['debtAmount'] ?? 0,
        });
      }
      
      setState(() {
        _customers = loadedCustomers;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loaded ${loadedCustomers.length} customers!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  void _addNote() {
    if (_noteController.text.isNotEmpty && _selectedCustomer != null) {
      setState(() {
        String existingNotes = _selectedCustomer!['notes'] ?? '';
        String newNote = _noteController.text;
        _selectedCustomer!['notes'] = existingNotes == 'No notes available.' || existingNotes.isEmpty 
            ? newNote 
            : '$existingNotes\n$newNote';
        final index = _customers.indexWhere((c) => c['name'] == _selectedCustomer!['name']);
        if (index != -1) {
          _customers[index]['notes'] = _selectedCustomer!['notes'];
        }
        _noteController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note added!')),
      );
    }
  }

  void _assignCustomerToPerson(String department, String personName) {
    if (_selectedCustomer != null) {
      setState(() {
        _selectedCustomer!['assignedTo'] = department;
        _selectedCustomer!['assignedToPerson'] = personName;
        final index = _customers.indexWhere((c) => c['name'] == _selectedCustomer!['name']);
        if (index != -1) {
          _customers[index]['assignedTo'] = department;
          _customers[index]['assignedToPerson'] = personName;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Assigned to $personName ($department)')),
      );
    }
  }

  void _recordPayment() {
    final amountController = TextEditingController();
    String _selectedAction = 'reduce';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Manage Debt'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Current Debt: KES ${_selectedCustomer!['debtAmount']}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Reduce Debt'),
                        value: 'reduce',
                        groupValue: _selectedAction,
                        onChanged: (value) {
                          setModalState(() {
                            _selectedAction = value!;
                          });
                        },
                        activeColor: Colors.green,
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Add Debt'),
                        value: 'add',
                        groupValue: _selectedAction,
                        onChanged: (value) {
                          setModalState(() {
                            _selectedAction = value!;
                          });
                        },
                        activeColor: Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountController,
                  decoration: InputDecoration(
                    labelText: _selectedAction == 'reduce' ? 'Payment Amount (KES)' : 'Additional Debt (KES)',
                    prefixIcon: Icon(_selectedAction == 'reduce' ? Icons.payment : Icons.add_circle),
                    border: const OutlineInputBorder(),
                    hintText: 'Enter amount',
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final amount = double.tryParse(amountController.text);
                  if (amount != null && amount > 0 && _selectedCustomer != null) {
                    final currentDebt = _selectedCustomer!['debtAmount'] as double;
                    double newDebtAmount;
                    String actionText;
                    
                    if (_selectedAction == 'reduce') {
                      newDebtAmount = (currentDebt - amount).clamp(0, double.infinity);
                      actionText = 'Payment of KES $amount recorded!';
                    } else {
                      newDebtAmount = currentDebt + amount;
                      actionText = 'Additional debt of KES $amount added!';
                    }
                    
                    setState(() {
                      _selectedCustomer!['debtAmount'] = newDebtAmount;
                      final index = _customers.indexWhere((c) => c['name'] == _selectedCustomer!['name']);
                      if (index != -1) {
                        _customers[index]['debtAmount'] = newDebtAmount;
                        if (newDebtAmount > 0) {
                          final tags = _customers[index]['tags'] as List;
                          if (!tags.contains('Debt')) {
                            tags.add('Debt');
                          }
                        }
                        if (newDebtAmount == 0) {
                          final tags = _customers[index]['tags'] as List;
                          tags.remove('Debt');
                          if (tags.contains('Pending Payment')) {
                            tags.remove('Pending Payment');
                          }
                        }
                      }
                    });
                    
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$actionText Remaining debt: KES ${newDebtAmount.toStringAsFixed(0)}')),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid amount')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _selectedAction == 'reduce' ? Colors.green : Colors.red,
                ),
                child: Text(_selectedAction == 'reduce' ? 'Record Payment' : 'Add Debt'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _markMessageAsRead(Map<String, dynamic> customer) {
    if (customer['unread'] > 0) {
      setState(() {
        customer['unread'] = 0;
        final index = _customers.indexWhere((c) => c['name'] == customer['name']);
        if (index != -1) {
          _customers[index]['unread'] = 0;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Marked ${customer['name']}\'s messages as read')),
      );
    }
  }

  void _markAllAsRead() {
    setState(() {
      for (var customer in _customers) {
        customer['unread'] = 0;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All messages marked as read')),
    );
  }

  void _editCustomer() {
    final nameController = TextEditingController(text: _selectedCustomer!['name']);
    final phoneController = TextEditingController(text: _selectedCustomer!['phone']);
    final businessController = TextEditingController(text: _selectedCustomer!['business']);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            TextField(
              controller: businessController,
              decoration: const InputDecoration(labelText: 'Business Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedCustomer!['name'] = nameController.text;
                _selectedCustomer!['phone'] = phoneController.text;
                _selectedCustomer!['business'] = businessController.text;
                final index = _customers.indexWhere((c) => c['name'] == _selectedCustomer!['name']);
                if (index != -1) {
                  _customers[index]['name'] = nameController.text;
                  _customers[index]['phone'] = phoneController.text;
                  _customers[index]['business'] = businessController.text;
                }
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Customer updated!')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _deleteCustomer() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Are you sure you want to delete ${_selectedCustomer!['name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _customers.removeWhere((c) => c['name'] == _selectedCustomer!['name']);
                _selectedCustomer = null;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Customer deleted!')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssignmentButton(String title, IconData icon, Color color, String value) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: OutlinedButton(
          onPressed: () {
            _showTeamMembersDialog(value);
          },
          style: OutlinedButton.styleFrom(
            side: BorderSide(
              color: _selectedCustomer!['assignedTo'] == value ? color : Colors.grey,
            ),
            backgroundColor: _selectedCustomer!['assignedTo'] == value
                ? color.withOpacity(0.1)
                : null,
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: _selectedCustomer!['assignedTo'] == value ? color : Colors.grey),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _selectedCustomer!['assignedTo'] == value ? color : Colors.grey,
                  ),
                  overflow: TextOverflow.visible,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showTeamMembersDialog(String department) {
    final teamMembers = _teamMembers.where((m) => m['role'] == department).toList();
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Assign to $department Team',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...teamMembers.map((member) => ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.green[100],
                child: Text(member['avatar']),
              ),
              title: Text(member['name']),
              subtitle: Text(department.toUpperCase()),
              onTap: () {
                Navigator.pop(context);
                _assignCustomerToPerson(department, member['name']);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showTeamMembersManagement() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Team Members'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ..._teamMembers.map((member) => ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green[100],
                  child: Text(member['avatar']),
                ),
                title: Text(member['name']),
                subtitle: Text(member['role'].toUpperCase()),
                trailing: const Icon(Icons.person, color: Colors.green),
              )),
              const Divider(),
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text(
                  'Sales: James Kamau, Mary Akinyi\nSupport: Sarah Wanjiku, John Otieno\nDelivery: Peter Odhiambo, David Mwangi',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return FilterChip(
      label: Text(label),
      selected: _selectedFilter == value,
      onSelected: (_) {
        setState(() {
          _selectedFilter = value;
          _selectedPersonFilter = 'all';
        });
      },
      backgroundColor: Colors.grey[200],
      selectedColor: Colors.green[100],
    );
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Customers'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter name or business...',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _searchQuery = '';
              });
              Navigator.pop(context);
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showAddCustomerDialog() {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final businessController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Customer'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
            ),
            TextField(
              controller: businessController,
              decoration: const InputDecoration(labelText: 'Business Name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isNotEmpty) {
                setState(() {
                  _customers.add({
                    'name': nameController.text,
                    'business': businessController.text,
                    'phone': phoneController.text,
                    'lastMessage': 'Welcome!',
                    'time': 'Just now',
                    'unread': 0,
                    'assignedTo': 'unassigned',
                    'assignedToPerson': '',
                    'tags': ['New Customer'],
                    'notes': 'New customer added.',
                    'debtAmount': 0,
                  });
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Added ${nameController.text}')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teamMembersByRole = _teamMembersByRole;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('WhatsApp Inbox'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload),
            onPressed: _saveToFirebase,
            tooltip: 'Save to Firebase',
          ),
          IconButton(
            icon: const Icon(Icons.cloud_download),
            onPressed: _loadFromFirebase,
            tooltip: 'Load from Firebase',
          ),
          IconButton(
            icon: const Icon(Icons.people),
            onPressed: _showTeamMembersManagement,
            tooltip: 'Manage Team',
          ),
          IconButton(
            icon: const Icon(Icons.mark_email_read),
            onPressed: _markAllAsRead,
            tooltip: 'Mark all as read',
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _showSearchDialog(),
          ),
        ],
      ),
      body: Row(
        children: [
          // Left Panel - Customer List
          Expanded(
            flex: 3,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      _buildFilterChip('All', 'all'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Sales', 'sales'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Support', 'support'),
                      const SizedBox(width: 8),
                      _buildFilterChip('Delivery', 'delivery'),
                    ],
                  ),
                ),
                if (_selectedFilter != 'all' && teamMembersByRole.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          FilterChip(
                            label: const Text('All'),
                            selected: _selectedPersonFilter == 'all',
                            onSelected: (_) {
                              setState(() {
                                _selectedPersonFilter = 'all';
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          ...teamMembersByRole.map((member) => FilterChip(
                            label: Text(member['name']),
                            selected: _selectedPersonFilter == member['name'],
                            onSelected: (_) {
                              setState(() {
                                _selectedPersonFilter = member['name'];
                              });
                            },
                            avatar: CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.green[100],
                              child: Text(
                                member['avatar'],
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          )),
                        ],
                      ),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem(Icons.people, 'Total', _stats['total']),
                      _buildStatItem(Icons.mark_email_unread, 'Unread', _stats['unread']),
                      _buildStatItem(Icons.currency_exchange, 'Debt', 'KES ${_stats['debtTotal']}'),
                      _buildStatItem(Icons.star, 'VIP', _stats['vipCount']),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: _filteredCustomers.length,
                    itemBuilder: (context, index) {
                      final customer = _filteredCustomers[index];
                      final tags = customer['tags'] as List;
                      final assignedPerson = customer['assignedToPerson'] ?? '';
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            _markMessageAsRead(customer);
                            setState(() {
                              _selectedCustomer = customer;
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Colors.green[100],
                                      child: Text(
                                        customer['name'][0],
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  customer['name'],
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 8,
                                                  vertical: 4,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: _getAssignmentColor(customer['assignedTo'])
                                                      .withOpacity(0.1),
                                                  borderRadius: BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      customer['assignedTo'] == 'sales'
                                                          ? Icons.trending_up
                                                          : customer['assignedTo'] == 'support'
                                                          ? Icons.support_agent
                                                          : Icons.local_shipping,
                                                      size: 12,
                                                      color: _getAssignmentColor(customer['assignedTo']),
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      customer['assignedTo'],
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: _getAssignmentColor(customer['assignedTo']),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            customer['business'],
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                          if (assignedPerson.isNotEmpty)
                                            Row(
                                              children: [
                                                const Icon(Icons.person, size: 10, color: Colors.grey),
                                                const SizedBox(width: 4),
                                                Text(
                                                  assignedPerson,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: Colors.grey[500],
                                                  ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      children: [
                                        Text(
                                          customer['time'],
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                        if (customer['unread'] > 0)
                                          const SizedBox(height: 4),
                                        if (customer['unread'] > 0)
                                          Container(
                                            padding: const EdgeInsets.all(4),
                                            decoration: const BoxDecoration(
                                              color: Colors.green,
                                              shape: BoxShape.circle,
                                            ),
                                            child: Text(
                                              '${customer['unread']}',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: tags.map((tag) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: _getTagColor(tag).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        tag,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _getTagColor(tag),
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(
                                      _getMessageStatusIcon(customer['unread']),
                                      size: 14,
                                      color: _getMessageStatusColor(customer['unread']),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        customer['lastMessage'],
                                        style: const TextStyle(fontSize: 13),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_selectedCustomer != null)
            SizedBox(
              width: 380,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Colors.green,
                    child: Row(
                      children: [
                        const Icon(Icons.notes, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _selectedCustomer!['name'],
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.white),
                          onPressed: _editCustomer,
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.white),
                          onPressed: _deleteCustomer,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedCustomer = null;
                              _noteController.clear();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: _getAssignmentColor(_selectedCustomer!['assignedTo']).withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Currently Assigned To:',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(
                                        _selectedCustomer!['assignedTo'] == 'sales'
                                            ? Icons.trending_up
                                            : _selectedCustomer!['assignedTo'] == 'support'
                                            ? Icons.support_agent
                                            : Icons.local_shipping,
                                        size: 14,
                                        color: _getAssignmentColor(_selectedCustomer!['assignedTo']),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _selectedCustomer!['assignedToPerson'] ?? 'Not assigned',
                                        style: const TextStyle(fontWeight: FontWeight.w500),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _getAssignmentColor(_selectedCustomer!['assignedTo']).withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          _selectedCustomer!['assignedTo'],
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: _getAssignmentColor(_selectedCustomer!['assignedTo']),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.business, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedCustomer!['business'],
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(Icons.phone, size: 16, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _selectedCustomer!['phone'],
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if ((_selectedCustomer!['debtAmount'] ?? 0) > 0)
                              Container(
                                margin: const EdgeInsets.only(top: 16),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.red.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.red.withOpacity(0.3)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'Outstanding Debt',
                                            style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            'KES ${_selectedCustomer!['debtAmount']}',
                                            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: _recordPayment,
                                      icon: const Icon(Icons.payment, size: 18),
                                      label: const Text('Manage'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                        foregroundColor: Colors.white,
                                        minimumSize: const Size(90, 38),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            const Text(
                              'Notes',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                _selectedCustomer!['notes'] ?? 'No notes available.',
                                style: const TextStyle(height: 1.4, fontSize: 13),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _noteController,
                                    decoration: InputDecoration(
                                      hintText: 'Add a note...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    onSubmitted: (_) => _addNote(),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                InkWell(
                                  onTap: _addNote,
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.send, color: Colors.white, size: 20),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Assign To',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                _buildAssignmentButton('Sales', Icons.trending_up, Colors.blue, 'sales'),
                                const SizedBox(width: 8),
                                _buildAssignmentButton('Support', Icons.support_agent, Colors.green, 'support'),
                                const SizedBox(width: 8),
                                _buildAssignmentButton('Delivery', Icons.local_shipping, Colors.orange, 'delivery'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddCustomerDialog,
        backgroundColor: Colors.green,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
