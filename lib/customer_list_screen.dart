import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final List<Map<String, dynamic>> customers = [
    {
      'id': '1',
      'name': 'John Doe',
      'businessName': 'ABC Electronics',
      'phone': '+1 234 567 8900',
      'tags': ['VIP', 'Pending Payment'],
      'lastMessage': 'Hello, I need 10 more units',
      'time': DateTime.now().subtract(const Duration(hours: 2)),
      'unread': 1,
      'assignedTo': 'sales',
    },
    {
      'id': '2',
      'name': 'Maria Garcia',
      'businessName': 'Downtown Cafe',
      'phone': '+1 234 567 8901',
      'tags': ['New Customer'],
      'lastMessage': 'When will delivery arrive?',
      'time': DateTime.now().subtract(const Duration(hours: 7)),
      'unread': 0,
      'assignedTo': 'support',
    },
    {
      'id': '3',
      'name': 'Ahmed Hassan',
      'businessName': '',
      'phone': '+1 234 567 8902',
      'tags': ['Delivery', 'Debt'],
      'lastMessage': 'Please confirm ETA',
      'time': DateTime.now().subtract(const Duration(days: 1)),
      'unread': 0,
      'assignedTo': 'delivery',
    },
    {
      'id': '4',
      'name': 'Lisa Chen',
      'businessName': 'Tech Solutions Inc',
      'phone': '+1 234 567 8903',
      'tags': [],
      'lastMessage': 'Thanks for your help',
      'time': DateTime.now().subtract(const Duration(days: 2)),
      'unread': 0,
      'assignedTo': 'unassigned',
    },
  ];

  String _searchQuery = '';
  String _selectedFilter = 'all';

  @override
  Widget build(BuildContext context) {
    final filteredCustomers = customers.where((customer) {
      final matchesSearch = _searchQuery.isEmpty ||
          customer['name'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          customer['businessName'].toLowerCase().contains(_searchQuery.toLowerCase()) ||
          customer['phone'].contains(_searchQuery);
      
      final matchesFilter = _selectedFilter == 'all' ||
          customer['assignedTo'] == _selectedFilter;
      
      return matchesSearch && matchesFilter;
    }).toList();

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'WhatsApp Inbox',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const Icon(Icons.message, color: Colors.green),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.black87),
            onPressed: () => _showSearchDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.black87),
            onPressed: () => _showFilterDialog(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildStatChip('All', customers.length, _selectedFilter == 'all'),
                const SizedBox(width: 8),
                _buildStatChip('Sales', 
                    customers.where((c) => c['assignedTo'] == 'sales').length, 
                    _selectedFilter == 'sales'),
                const SizedBox(width: 8),
                _buildStatChip('Support',
                    customers.where((c) => c['assignedTo'] == 'support').length,
                    _selectedFilter == 'support'),
                const SizedBox(width: 8),
                _buildStatChip('Delivery',
                    customers.where((c) => c['assignedTo'] == 'delivery').length,
                    _selectedFilter == 'delivery'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: filteredCustomers.length,
              itemBuilder: (context, index) {
                final customer = filteredCustomers[index];
                return _buildCustomerTile(customer);
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showNewChatDialog(),
        backgroundColor: Colors.green,
        child: const Icon(Icons.chat, color: Colors.white),
      ),
    );
  }

  Widget _buildStatChip(String label, int count, bool isSelected) {
    return FilterChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _selectedFilter = isSelected ? 'all' : label.toLowerCase();
        });
      },
      backgroundColor: Colors.white,
      selectedColor: Colors.green[100],
      checkmarkColor: Colors.green,
    );
  }

  Widget _buildCustomerTile(Map<String, dynamic> customer) {
    final timeFormat = DateFormat('HH:mm');
    final dateFormat = DateFormat('MMM d');
    final time = customer['time'] as DateTime;
    final isToday = time.isAfter(DateTime.now().subtract(const Duration(days: 1)));
    
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openChat(customer),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.green[50],
                child: Text(
                  customer['name'][0],
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          isToday ? timeFormat.format(time) : dateFormat.format(time),
                          style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                    if (customer['businessName'].isNotEmpty)
                      Text(
                        customer['businessName'],
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            customer['lastMessage'],
                            style: TextStyle(
                              fontSize: 13,
                              color: customer['unread'] > 0 ? Colors.black87 : Colors.grey[600],
                              fontWeight: customer['unread'] > 0 ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (customer['unread'] > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            child: Text(
                              '${customer['unread']}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      children: (customer['tags'] as List).map<Widget>((tag) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getTagColor(tag).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tag,
                            style: TextStyle(
                              fontSize: 10,
                              color: _getTagColor(tag),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getTagColor(String tag) {
    switch (tag) {
      case 'VIP':
        return Colors.orange;
      case 'Pending Payment':
        return Colors.red;
      case 'New Customer':
        return Colors.green;
      case 'Delivery':
        return Colors.blue;
      case 'Debt':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Search Customers'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Name, business, or phone...',
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person),
            title: const Text('Unassigned'),
            onTap: () {
              setState(() => _selectedFilter = 'unassigned');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.trending_up, color: Colors.blue),
            title: const Text('Sales'),
            onTap: () {
              setState(() => _selectedFilter = 'sales');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.support_agent, color: Colors.green),
            title: const Text('Support'),
            onTap: () {
              setState(() => _selectedFilter = 'support');
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.local_shipping, color: Colors.orange),
            title: const Text('Delivery'),
            onTap: () {
              setState(() => _selectedFilter = 'delivery');
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.clear),
            title: const Text('Clear Filter'),
            onTap: () {
              setState(() => _selectedFilter = 'all');
              Navigator.pop(context);
            },
          ),
        ],
      ),
    );
  }

  void _showNewChatDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New WhatsApp Chat'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            TextField(
              decoration: InputDecoration(
                hintText: 'Phone number (with country code)',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
            SizedBox(height: 8),
            TextField(
              decoration: InputDecoration(
                hintText: 'Customer name (optional)',
                prefixIcon: Icon(Icons.person),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Start Chat', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _openChat(Map<String, dynamic> customer) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Opening chat with ${customer['name']}...')),
    );
  }
}