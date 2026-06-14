import 'dart:async';
import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:csv/csv.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:universal_html/html.dart' as html;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shimmer/shimmer.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'user_management_screen.dart';
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'dashboard_screen.dart';
import 'tasks_screen.dart';
import 'auth_wrapper.dart';

class WhatsAppInbox extends StatefulWidget {
  const WhatsAppInbox({super.key});

  @override
  State<WhatsAppInbox> createState() => _WhatsAppInboxState();
}

class _WhatsAppInboxState extends State<WhatsAppInbox> {
  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _teamMembers = [];
  Map<String, dynamic>? _currentUser;
  String? currentTenantId;
  String? currentUserId;

  String _selectedFilter = 'all';
  String _selectedPersonFilter = 'all';
  String _searchQuery = '';

  String _dashboardDateFilter = 'today';
  DateTimeRange? _customDateRange;

  Map<String, dynamic>? _selectedCustomer;
  final TextEditingController _noteController = TextEditingController();
  bool _isLoading = false;
  bool _isMpesaRequesting = false;
  final GlobalKey<RefreshIndicatorState> _refreshIndicatorKey = GlobalKey<RefreshIndicatorState>();

  final ValueNotifier<bool> _isOnlineNotifier = ValueNotifier<bool>(true);
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _debounceTimer;
  Timer? _connectivityFallbackTimer;

  List<QueryDocumentSnapshot> _allTransactions = [];
  StreamSubscription<QuerySnapshot>? _transactionsSubscription;

  StreamSubscription<QuerySnapshot>? _tasksSubscription;
  Set<String> _customerIdsWithPendingTasks = {};

  List<Map<String, dynamic>> _filteredAndSortedCustomers = [];
  bool _isFiltering = false;

  bool _showDeletedNotes = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _initConnectivity();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _connectivityFallbackTimer?.cancel();
    _connectivitySubscription?.cancel();
    _transactionsSubscription?.cancel();
    _tasksSubscription?.cancel();
    _isOnlineNotifier.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _logError(String context, dynamic error, [StackTrace? stack]) {
    debugPrint('ERROR [$context]: $error');
    if (stack != null) debugPrint(stack.toString());
  }

  // --------------------- User & Data Loading ---------------------
  Future<void> _ensureAdminIfOnlyUser() async {
    if (currentTenantId == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('tenantId', isEqualTo: currentTenantId)
          .get();
      if (snapshot.docs.length == 1 && _currentUser?['role'] != 'admin') {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).update({'role': 'admin'});
        if (mounted) {
          setState(() {
            _currentUser?['role'] = 'admin';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You have been upgraded to admin (first user of this business).'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e, stack) {
      _logError('ensureAdminIfOnlyUser', e, stack);
    }
  }

  Future<void> _createUserDocument(String uid) async {
    final email = FirebaseAuth.instance.currentUser!.email;
    if (email == null) return;
    final allUsers = await FirebaseFirestore.instance.collection('users').limit(1).get();
    final role = allUsers.docs.isEmpty ? 'admin' : 'sales';
    final tenantId = FirebaseFirestore.instance.collection('tenants').doc().id;
    await FirebaseFirestore.instance.collection('tenants').doc(tenantId).set({
      'name': '${email.split('@')[0]}\'s Business',
      'createdAt': FieldValue.serverTimestamp(),
    });
    final userData = {
      'name': email.split('@')[0],
      'email': email,
      'role': role,
      'tenantId': tenantId,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await FirebaseFirestore.instance.collection('users').doc(uid).set(userData);
    if (mounted) {
      setState(() {
        _currentUser = userData;
        currentTenantId = tenantId;
      });
    }
    await _loadTeamMembers();
    await _loadCustomers();
  }

  Future<void> _loadCurrentUser({int retryCount = 0}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    setState(() {
      currentUserId = uid;
    });

    final userDoc = FirebaseFirestore.instance.collection('users').doc(uid);
    try {
      final doc = await userDoc.get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) {
          setState(() {
            _currentUser = data;
            currentTenantId = data['tenantId'];
          });
        }
        await _loadTeamMembers();
        await _loadCustomers();
        await _ensureAdminIfOnlyUser();
        Future.delayed(const Duration(milliseconds: 500), () async {
          await _ensureAdminIfOnlyUser();
        });
        _listenToTransactions();
        _listenToUserTasks();
      } else {
        if (retryCount < 3) {
          await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
          return _loadCurrentUser(retryCount: retryCount + 1);
        }
        await _createUserDocument(uid);
        _listenToTransactions();
        _listenToUserTasks();
      }
    } catch (e, stack) {
      if (e is FirebaseException && e.code == 'permission-denied' && retryCount < 3) {
        await Future.delayed(Duration(milliseconds: 500 * (retryCount + 1)));
        return _loadCurrentUser(retryCount: retryCount + 1);
      }
      _logError('loadCurrentUser', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load profile. Pull down to refresh.'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  Future<void> _loadTeamMembers() async {
    if (currentTenantId == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('tenantId', isEqualTo: currentTenantId)
          .get();
      if (mounted) {
        setState(() {
          _teamMembers = snapshot.docs.map((d) => ({
            'name': d['name'],
            'role': d['role'],
            'avatar': d['name'].substring(0, 1).toUpperCase(),
            'id': d.id,
          })).toList();
        });
      }
    } catch (e, stack) {
      _logError('loadTeamMembers', e, stack);
    }
  }

  Future<void> _loadCustomers() async {
    if (currentTenantId == null) return;
    if (mounted) setState(() => _isLoading = true);
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('customers')
          .where('tenantId', isEqualTo: currentTenantId)
          .get();
      final loaded = snapshot.docs.map((doc) {
        final data = doc.data();
        dynamic notesData = data['notes'];
        List<Map<String, dynamic>> notesList = [];

        if (notesData is String && notesData.isNotEmpty) {
          notesList = [
            {
              'text': notesData,
              'createdAt': Timestamp.now(),
              'author': _currentUser?['name'] ?? 'System',
              'deleted': false,
            }
          ];
        } else if (notesData is List) {
          notesList = notesData.map((note) {
            final Map<String, dynamic> cleanNote = Map.from(note);
            final createdAt = cleanNote['createdAt'];
            if (createdAt != null && createdAt is! Timestamp) {
              cleanNote['createdAt'] = null;
            }
            if (cleanNote['deleted'] == null) {
              cleanNote['deleted'] = false;
            }
            return cleanNote;
          }).cast<Map<String, dynamic>>().toList();
        }

        return {
          'id': doc.id,
          'name': data['name'] ?? '',
          'business': data['business'] ?? '',
          'phoneNumbers': List<String>.from(data['phoneNumbers'] ?? []),
          'lastMessage': data['lastMessage'] ?? '',
          'time': data['time'] ?? '',
          'unread': data['unread'] ?? 0,
          'assignedTo': data['assignedTo'] ?? 'unassigned',
          'assignedToPerson': data['assignedToPerson'] ?? '',
          'assignedToUserId': data['assignedToUserId'] ?? '',
          'tags': List<String>.from(data['tags'] ?? []),
          'notes': notesList,
          'debtAmount': (data['debtAmount'] ?? 0).toDouble(),
        };
      }).toList();

      // Background repair for missing deleted flag in notes
      for (var doc in snapshot.docs) {
        final notesData = doc.data()['notes'];
        if (notesData is List) {
          bool needsUpdate = false;
          final fixedNotes = notesData.map((note) {
            if (note['deleted'] == null) {
              needsUpdate = true;
              return {...note, 'deleted': false};
            }
            return note;
          }).toList();
          if (needsUpdate) {
            doc.reference.update({'notes': fixedNotes}).catchError((e) => _logError('fixNotesDeletedFlag', e));
          }
        }
      }

      if (mounted) {
        setState(() {
          _customers = loaded;
          _selectedCustomer = null;
        });
        await _applyFiltersAndSort();
      }
    } catch (e, stack) {
      _logError('loadCustomers', e, stack);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _initConnectivity() async {
    final result = await Connectivity().checkConnectivity();
    final isOnline = !result.contains(ConnectivityResult.none);
    _isOnlineNotifier.value = isOnline;

    _connectivityFallbackTimer = Timer(const Duration(seconds: 3), () async {
      final fresh = await Connectivity().checkConnectivity();
      final freshOnline = !fresh.contains(ConnectivityResult.none);
      if (_isOnlineNotifier.value != freshOnline) {
        _isOnlineNotifier.value = freshOnline;
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      _connectivityFallbackTimer?.cancel();
      final nowOnline = !result.contains(ConnectivityResult.none);
      final wasOffline = !_isOnlineNotifier.value;
      if (nowOnline != _isOnlineNotifier.value) {
        _isOnlineNotifier.value = nowOnline;
      }
      if (wasOffline && nowOnline) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Back online!'), backgroundColor: Colors.green),
        );
        _loadCustomers();
      }
    });
  }

  void _listenToTransactions() {
    if (currentTenantId == null) return;
    _transactionsSubscription?.cancel();
    _transactionsSubscription = FirebaseFirestore.instance
        .collection('transactions')
        .where('tenantId', isEqualTo: currentTenantId)
        .snapshots()
        .listen((snapshot) {
      _allTransactions = snapshot.docs;
      if (mounted) setState(() {});
    }, onError: (e) {
      _logError('transactionsStream', e);
    });
  }

  void _listenToUserTasks() {
    if (currentUserId == null || currentTenantId == null) return;
    _tasksSubscription?.cancel();
    _tasksSubscription = FirebaseFirestore.instance
        .collection('tasks')
        .where('assignedToUserId', isEqualTo: currentUserId)
        .where('tenantId', isEqualTo: currentTenantId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      final Set<String> pendingCustomerIds = {};
      for (var doc in snapshot.docs) {
        final customerId = doc.data()['customerId'] as String?;
        if (customerId != null && customerId.isNotEmpty) {
          pendingCustomerIds.add(customerId);
        }
      }
      if (mounted) {
        setState(() {
          _customerIdsWithPendingTasks = pendingCustomerIds;
        });
      }
    }, onError: (e) {
      _logError('tasksStream', e);
    });
  }

  double get _dashboardTotalPayments {
    final now = DateTime.now();
    DateTime startDate;
    switch (_dashboardDateFilter) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'thisWeek':
        startDate = now.subtract(Duration(days: now.weekday - 1));
        break;
      case 'thisMonth':
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 'custom':
        if (_customDateRange == null) return 0.0;
        startDate = _customDateRange!.start;
        break;
      default:
        return 0.0;
    }
    double total = 0.0;
    for (var doc in _allTransactions) {
      final data = doc.data() as Map<String, dynamic>;
      final type = data['type'] as String?;
      if (type == 'reduce_debt' || type == 'mpesa_payment') {
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
        if (timestamp != null) {
          if (_dashboardDateFilter == 'custom') {
            if (timestamp.isAfter(_customDateRange!.start.subtract(const Duration(days: 1))) &&
                timestamp.isBefore(_customDateRange!.end.add(const Duration(days: 1)))) {
              total += amount;
            }
          } else {
            if (timestamp.isAfter(startDate.subtract(const Duration(days: 1)))) {
              total += amount;
            }
          }
        }
      }
    }
    return total;
  }

  Future<void> _selectCustomDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customDateRange,
    );
    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _dashboardDateFilter = 'custom';
      });
    } else {
      setState(() {
        _dashboardDateFilter = 'today';
      });
    }
  }

  Future<DateTime?> _getLatestTransactionDate(String customerId) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .where('customerId', isEqualTo: customerId)
          .where('tenantId', isEqualTo: currentTenantId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (snapshot.docs.isNotEmpty) {
        final ts = snapshot.docs.first['timestamp'] as Timestamp?;
        return ts?.toDate();
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  List<Map<String, dynamic>> get _teamMembersByRole {
    if (_selectedFilter == 'all') return [];
    return _teamMembers.where((m) => m['role'] == _selectedFilter).toList();
  }

  Future<void> _applyFiltersAndSort() async {
    if (_isFiltering) return;
    setState(() => _isFiltering = true);
    try {
      var result = List<Map<String, dynamic>>.from(_customers);

      if (_selectedFilter != 'all') {
        result = result.where((c) => c['assignedTo'] == _selectedFilter).toList();
      }
      if (_selectedPersonFilter != 'all') {
        result = result.where((c) => c['assignedToPerson'] == _selectedPersonFilter).toList();
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        result = result.where((c) {
          final nameMatch = c['name'].toLowerCase().contains(query);
          final businessMatch = c['business'].toLowerCase().contains(query);
          final phoneNumbers = c['phoneNumbers'] as List<String>? ?? [];
          final phoneMatch = phoneNumbers.any((phone) => phone.toLowerCase().contains(query));
          return nameMatch || businessMatch || phoneMatch;
        }).toList();
      }
      final withTxDate = <Map<String, dynamic>>[];
      for (var customer in result) {
        final txDate = await _getLatestTransactionDate(customer['id']);
        withTxDate.add({...customer, '_latestTxDate': txDate});
      }
      withTxDate.sort((a, b) {
        final dateA = a['_latestTxDate'] as DateTime?;
        final dateB = b['_latestTxDate'] as DateTime?;
        if (dateA == null && dateB == null) return 0;
        if (dateA == null) return 1;
        if (dateB == null) return -1;
        return dateB.compareTo(dateA);
      });
      if (mounted) {
        setState(() {
          _filteredAndSortedCustomers = withTxDate;
          _isFiltering = false;
        });
      }
    } catch (e) {
      _logError('applyFiltersAndSort', e);
      if (mounted) setState(() => _isFiltering = false);
    }
  }

  Map<String, dynamic> get _stats {
    return {
      'total': _customers.length,
      'unread': _customers.where((c) => c['unread'] > 0).length,
      'debtTotal': _customers.fold<double>(0, (s, c) => s + (c['debtAmount'] ?? 0)),
      'vipCount': _customers.where((c) => (c['tags'] as List).contains('VIP')).length,
    };
  }

  Color _getTagColor(String t) {
    switch (t) {
      case 'VIP':
        return Colors.orange;
      case 'Pending Payment':
        return Colors.red;
      case 'New Customer':
        return Colors.green;
      case 'Delivery':
        return Colors.blue;
      case 'Debt':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildStatItem(IconData icon, String label, dynamic value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6)),
        child: Column(
          children: [
            Icon(icon, size: 14, color: Colors.green[600]),
            const SizedBox(height: 2),
            Text(value.toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(label, style: TextStyle(fontSize: 9, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  // --------------------- Export ---------------------
  Future<void> _exportToCsv() async {
    try {
      final data = _filteredAndSortedCustomers;
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No customers to export'), backgroundColor: Colors.orange));
        }
        return;
      }
      final totalDebt = data.fold<double>(0, (s, c) => s + (c['debtAmount'] ?? 0));
      final totalUnread = data.fold(0, (s, c) => s + ((c['unread'] ?? 0) as int));
      final headers = ['Name', 'Business', 'Phone Numbers', 'Last Message', 'Time', 'Unread', 'Assigned To', 'Assigned Person', 'Tags', 'Notes', 'Debt (KES)'];
      final rows = [headers];
      for (var c in data) {
        rows.add([
          c['name'],
          c['business'],
          (c['phoneNumbers'] as List).join(', '),
          c['lastMessage'],
          c['time'],
          c['unread'].toString(),
          c['assignedTo'],
          c['assignedToPerson'],
          (c['tags'] as List).join(', '),
          c['notes'] ?? '',
          (c['debtAmount'] ?? 0).toStringAsFixed(2),
        ]);
      }
      rows.add(List.filled(headers.length, ''));
      rows.add([
        'TOTAL',
        '',
        '',
        '',
        '',
        totalUnread.toString(),
        '',
        '',
        '',
        'Total Customers: ${data.length}',
        totalDebt.toStringAsFixed(2)
      ]);
      final csv = const ListToCsvConverter().convert(rows);
      if (kIsWeb) {
        final blob = html.Blob([csv], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.AnchorElement(href: url)..download = 'customers_export_${DateTime.now().millisecondsSinceEpoch}.csv'..click();
        html.Url.revokeObjectUrl(url);
      } else {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/customers_export_${DateTime.now().millisecondsSinceEpoch}.csv');
        await file.writeAsString(csv);
        await Share.shareXFiles([XFile(file.path)], text: 'Customer List Export', subject: 'BiasharaOS Export');
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Export successful'), backgroundColor: Colors.green));
      }
    } catch (e, stack) {
      _logError('exportToCsv', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _exportToPdf() async {
    try {
      final data = _filteredAndSortedCustomers;
      if (data.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No customers to export'), backgroundColor: Colors.orange));
        }
        return;
      }
      final totalDebt = data.fold<double>(0, (s, c) => s + (c['debtAmount'] ?? 0));
      final totalUnread = data.fold(0, (s, c) => s + ((c['unread'] ?? 0) as int));
      final pdf = pw.Document();
      pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        orientation: pw.PageOrientation.landscape,
        build: (_) => [
          pw.Header(level: 0, child: pw.Text('BiasharaOS - Customer Report', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.SizedBox(height: 10),
          pw.Text('Generated: ${DateTime.now()}', style: pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: ['Name', 'Business', 'Phone Numbers', 'Last Message', 'Time', 'Unread', 'Assigned To', 'Assigned Person', 'Tags', 'Notes', 'Debt (KES)'],
            data: data.map((c) => [
              c['name'],
              c['business'],
              (c['phoneNumbers'] as List).join(', '),
              c['lastMessage'],
              c['time'],
              c['unread'].toString(),
              c['assignedTo'],
              c['assignedToPerson'],
              (c['tags'] as List).join(', '),
              c['notes'] ?? '',
              (c['debtAmount'] ?? 0).toStringAsFixed(2)
            ]).toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            border: pw.TableBorder.all(width: 0.5),
            cellAlignment: pw.Alignment.centerLeft,
            headerDecoration: pw.BoxDecoration(color: PdfColors.grey300),
          ),
          pw.SizedBox(height: 20),
          pw.Container(
            padding: pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SUMMARY', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
              pw.SizedBox(height: 5),
              pw.Text('Total Customers: ${data.length}'),
              pw.Text('Total Unread Messages: $totalUnread'),
              pw.Text('Total Debt (KES): ${totalDebt.toStringAsFixed(2)}'),
            ]),
          ),
        ],
      ));
      await Printing.sharePdf(bytes: await pdf.save(), filename: 'customers_report_${DateTime.now().millisecondsSinceEpoch}.pdf');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PDF report generated'), backgroundColor: Colors.green));
      }
    } catch (e, stack) {
      _logError('exportToPdf', e, stack);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF export failed'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _recordTransaction({required String customerId, required String type, required double amount, required double previousDebt, required double newDebt, String? note}) async {
    await FirebaseFirestore.instance.collection('transactions').add({
      'customerId': customerId,
      'type': type,
      'amount': amount,
      'previousDebt': previousDebt,
      'newDebt': newDebt,
      'note': note ?? '',
      'tenantId': currentTenantId,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await _applyFiltersAndSort();
  }

  // --------------------- CRUD Operations ---------------------
  void _addCustomer() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final businessCtrl = TextEditingController();
    final List<TextEditingController> phoneControllers = [TextEditingController()];
    
    Map<String, dynamic>? selectedTeamMember;
    final List<Map<String, dynamic>> assignableMembers = _teamMembers.where((m) => m['role'] != 'admin').toList();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setStateDialog) {
          bool _isChecking = false;

          void addPhone() => setStateDialog(() => phoneControllers.add(TextEditingController()));
          void removePhone(int idx) {
            if (phoneControllers.length > 1) {
              setStateDialog(() => phoneControllers.removeAt(idx));
            }
          }

          void submitAdd() async {
            if (formKey.currentState!.validate()) {
              final name = nameCtrl.text.trim();
              final phones = phoneControllers.map((p) => p.text.trim()).where((p) => p.isNotEmpty).toList();
              if (phones.isEmpty) return;
              setStateDialog(() => _isChecking = true);
              try {
                final existing = await FirebaseFirestore.instance
                    .collection('customers')
                    .where('tenantId', isEqualTo: currentTenantId)
                    .where('name', isEqualTo: name)
                    .get();
                if (existing.docs.isNotEmpty) {
                  ScaffoldMessenger.of(c).showSnackBar(
                    const SnackBar(content: Text('Customer with this name already exists!'), backgroundColor: Colors.orange),
                  );
                  setStateDialog(() => _isChecking = false);
                  return;
                }
                
                final assignedToPerson = selectedTeamMember != null ? selectedTeamMember!['name'] : '';
                final assignedToUserId = selectedTeamMember != null ? selectedTeamMember!['id'] : '';
                final assignedToRole = selectedTeamMember != null ? selectedTeamMember!['role'] : 'unassigned';
                
                final newCustomer = {
                  'name': name,
                  'business': businessCtrl.text.trim(),
                  'phoneNumbers': phones,
                  'lastMessage': 'Welcome!',
                  'time': 'Just now',
                  'unread': 0,
                  'assignedTo': assignedToRole,
                  'assignedToPerson': assignedToPerson,
                  'assignedToUserId': assignedToUserId,
                  'tags': ['New Customer'],
                  'notes': [],
                  'debtAmount': 0.0,
                  'tenantId': currentTenantId,
                  'createdAt': FieldValue.serverTimestamp(),
                };
                final docRef = await FirebaseFirestore.instance.collection('customers').add(newCustomer);
                
                if (selectedTeamMember != null && assignedToUserId.isNotEmpty) {
                  await _createTask(
                    assignedToUserId: assignedToUserId,
                    assignedToName: assignedToPerson,
                    customerId: docRef.id,
                    customerName: name,
                    message: 'New customer "$name" has been assigned to you. Please assist.',
                  );
                }
                
                if (mounted) {
                  setState(() {
                    _customers.add({...newCustomer, 'id': docRef.id});
                  });
                  await _applyFiltersAndSort();
                }
                if (c.mounted) Navigator.pop(c);
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Added $name'), backgroundColor: Colors.green));
              } catch (e) {
                ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                setStateDialog(() => _isChecking = false);
              }
            }
          }

          return AlertDialog(
            title: const Text('Add Customer'),
            content: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name *'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(c).nextFocus(),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: businessCtrl,
                      decoration: const InputDecoration(labelText: 'Business Name (optional)'),
                      textInputAction: TextInputAction.next,
                      onFieldSubmitted: (_) => FocusScope.of(c).nextFocus(),
                    ),
                    const SizedBox(height: 8),
                    const Text('Phone Numbers (at least one)'),
                    ...phoneControllers.asMap().entries.map((entry) {
                      int idx = entry.key;
                      TextEditingController ctrl = entry.value;
                      return Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: ctrl,
                              decoration: InputDecoration(
                                hintText: 'e.g. 0712345678',
                                suffixIcon: idx > 0
                                    ? IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.red),
                                        onPressed: () => removePhone(idx),
                                      )
                                    : null,
                              ),
                              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                              textInputAction: idx == phoneControllers.length - 1 ? TextInputAction.done : TextInputAction.next,
                              onFieldSubmitted: (_) {
                                if (idx == phoneControllers.length - 1) {
                                  submitAdd();
                                } else {
                                  FocusScope.of(c).nextFocus();
                                }
                              },
                            ),
                          ),
                          if (idx == 0)
                            IconButton(
                              icon: const Icon(Icons.add_circle, color: Colors.green),
                              onPressed: addPhone,
                            ),
                        ],
                      );
                    }).toList(),
                    if (assignableMembers.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<Map<String, dynamic>>(
                        decoration: const InputDecoration(labelText: 'Assign To (optional)'),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('-- None --')),
                          ...assignableMembers.map((member) => DropdownMenuItem(
                                value: member,
                                child: Text('${member['name']} (${member['role']})'),
                              )),
                        ],
                        onChanged: (value) {
                          setStateDialog(() {
                            selectedTeamMember = value;
                          });
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: _isChecking ? null : submitAdd,
                child: _isChecking
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _editCustomer() {
    final customer = _selectedCustomer!;
    final nameCtrl = TextEditingController(text: customer['name']);
    final businessCtrl = TextEditingController(text: customer['business']);
    final phoneControllers = (customer['phoneNumbers'] as List).map((p) => TextEditingController(text: p)).toList();
    if (phoneControllers.isEmpty) phoneControllers.add(TextEditingController());

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) {
          void addPhone() => setStateDialog(() => phoneControllers.add(TextEditingController()));
          void removePhone(int idx) {
            if (phoneControllers.length > 1) {
              setStateDialog(() => phoneControllers.removeAt(idx));
            }
          }
          return AlertDialog(
            title: const Text('Edit Customer'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: businessCtrl,
                    decoration: const InputDecoration(labelText: 'Business Name'),
                  ),
                  const SizedBox(height: 8),
                  const Text('Phone Numbers'),
                  ...phoneControllers.asMap().entries.map((entry) {
                    int idx = entry.key;
                    TextEditingController ctrl = entry.value;
                    return Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: ctrl,
                            decoration: InputDecoration(
                              hintText: 'Phone number',
                              suffixIcon: idx > 0
                                  ? IconButton(
                                      icon: const Icon(Icons.remove_circle, color: Colors.red),
                                      onPressed: () => removePhone(idx),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        if (idx == 0)
                          IconButton(
                            icon: const Icon(Icons.add_circle, color: Colors.green),
                            onPressed: addPhone,
                          ),
                      ],
                    );
                  }).toList(),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final phones = phoneControllers.map((p) => p.text.trim()).where((p) => p.isNotEmpty).toList();
                  if (phones.isEmpty) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('At least one phone number required')),
                    );
                    return;
                  }
                  final update = {
                    'name': nameCtrl.text.trim(),
                    'business': businessCtrl.text.trim(),
                    'phoneNumbers': phones,
                  };
                  try {
                    await FirebaseFirestore.instance.collection('customers').doc(customer['id']).update(update);
                    if (mounted) {
                      setState(() {
                        customer['name'] = update['name'];
                        customer['business'] = update['business'];
                        customer['phoneNumbers'] = update['phoneNumbers'];
                        final idx = _customers.indexWhere((c) => c['id'] == customer['id']);
                        if (idx != -1) _customers[idx] = Map.from(customer);
                      });
                      await _applyFiltersAndSort();
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Customer updated'), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _manageDebt() {
    final amountCtrl = TextEditingController();
    String action = 'add';
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setStateDialog) => AlertDialog(
          title: const Text('Manage Debt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Current Debt: KES ${_selectedCustomer!['debtAmount'].toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: RadioListTile(title: const Text('Add Debt'), value: 'add', groupValue: action, onChanged: (v) => setStateDialog(() => action = v!), activeColor: Colors.red)),
                  Expanded(child: RadioListTile(title: const Text('Reduce Debt'), value: 'reduce', groupValue: action, onChanged: (v) => setStateDialog(() => action = v!), activeColor: Colors.green)),
                ],
              ),
              TextField(controller: amountCtrl, decoration: InputDecoration(labelText: action == 'add' ? 'Amount to Add (KES)' : 'Payment Amount (KES)', prefixIcon: Icon(action == 'add' ? Icons.add_circle : Icons.payment)), keyboardType: TextInputType.number),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                final amount = double.tryParse(amountCtrl.text) ?? 0;
                if (amount <= 0) return;
                double current = _selectedCustomer!['debtAmount'];
                double newDebt;
                String type;
                if (action == 'add') {
                  newDebt = current + amount;
                  type = 'add_debt';
                } else {
                  if (amount > current) {
                    ScaffoldMessenger.of(c).showSnackBar(const SnackBar(content: Text('Payment exceeds debt')));
                    return;
                  }
                  newDebt = current - amount;
                  type = 'reduce_debt';
                }
                if (mounted) {
                  setState(() {
                    _selectedCustomer!['debtAmount'] = newDebt;
                    final idx = _customers.indexWhere((cust) => cust['id'] == _selectedCustomer!['id']);
                    if (idx != -1) _customers[idx]['debtAmount'] = newDebt;
                  });
                  await _applyFiltersAndSort();
                }
                final customerId = _selectedCustomer!['id'];
                await _updateCustomerDebtInFirebase(customerId, newDebt);
                await _recordTransaction(
                  customerId: customerId,
                  type: type,
                  amount: amount,
                  previousDebt: current,
                  newDebt: newDebt,
                  note: action == 'add' ? 'Added debt' : 'Manual payment',
                );
                if (c.mounted) Navigator.pop(c);
                if (mounted) {
                  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(action == 'add' ? 'Debt added' : 'Payment recorded')));
                }
              },
              child: Text(action == 'add' ? 'Add Debt' : 'Record Payment'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateCustomerDebtInFirebase(String customerId, double newDebt) async {
    await FirebaseFirestore.instance.collection('customers').doc(customerId).update({'debtAmount': newDebt});
  }

  Future<void> _requestMpesaPayment() async {
    final customer = _selectedCustomer!;
    final phones = customer['phoneNumbers'] as List<String>;
    if (phones.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number')));
      return;
    }
    String selectedPhone = phones.first;
    if (phones.length > 1) {
      selectedPhone = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Select Phone Number'),
          content: Column(mainAxisSize: MainAxisSize.min, children: phones.map((p) => ListTile(title: Text(p), onTap: () => Navigator.pop(c, p))).toList()),
        ),
      ) ?? phones.first;
    }
    final amountCtrl = TextEditingController(text: customer['debtAmount'].toStringAsFixed(0));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('M-PESA Payment Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Customer: ${customer['name']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('Phone: $selectedPhone'),
            TextField(controller: amountCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Amount (KES)', prefixText: 'KES ')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Request Payment')),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = double.tryParse(amountCtrl.text) ?? 0;
    if (amount <= 0) return;
    if (mounted) setState(() => _isMpesaRequesting = true);
    await Future.delayed(const Duration(seconds: 2));
    double currentDebt = customer['debtAmount'];
    double newDebt = (currentDebt - amount).clamp(0, double.infinity);
    if (mounted) {
      setState(() {
        _selectedCustomer!['debtAmount'] = newDebt;
        final idx = _customers.indexWhere((c) => c['id'] == customer['id']);
        if (idx != -1) _customers[idx]['debtAmount'] = newDebt;
      });
      await _applyFiltersAndSort();
    }
    await _updateCustomerDebtInFirebase(customer['id'], newDebt);
    await _recordTransaction(
      customerId: customer['id'],
      type: 'mpesa_payment',
      amount: amount,
      previousDebt: currentDebt,
      newDebt: newDebt,
      note: 'M-PESA payment',
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment of KES ${amount.toStringAsFixed(0)} received')));
      setState(() => _isMpesaRequesting = false);
    }
  }

  Future<void> _createTask({
    required String assignedToUserId,
    required String assignedToName,
    required String customerId,
    required String customerName,
    required String message,
  }) async {
    if (assignedToUserId.isEmpty) return;
    await FirebaseFirestore.instance.collection('tasks').add({
      'assignedToUserId': assignedToUserId,
      'assignedToName': assignedToName,
      'customerId': customerId,
      'customerName': customerName,
      'message': message,
      'tenantId': currentTenantId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': _currentUser?['name'] ?? 'System',
    });
  }

  // Note methods (soft delete, audit)
  void _addNote() async {
    if (_noteController.text.isNotEmpty && _selectedCustomer != null) {
      final customerId = _selectedCustomer!['id'];
      final newNoteText = _noteController.text.trim();
      final newNote = {
        'text': newNoteText,
        'createdAt': Timestamp.now(),
        'author': _currentUser?['name'] ?? 'User',
        'deleted': false,
        'deletedAt': null,
      };

      List<Map<String, dynamic>> currentNotes = List.from(_selectedCustomer!['notes'] ?? []);
      currentNotes.insert(0, newNote);

      if (mounted) {
        setState(() {
          _selectedCustomer!['notes'] = currentNotes;
          final idx = _customers.indexWhere((c) => c['id'] == customerId);
          if (idx != -1) _customers[idx]['notes'] = currentNotes;
          _noteController.clear();
        });
      }

      await FirebaseFirestore.instance.collection('customers').doc(customerId).update({
        'notes': currentNotes,
      });
    }
  }

  void _deleteNote(int index) async {
    final customerId = _selectedCustomer!['id'];
    List<Map<String, dynamic>> currentNotes = List.from(_selectedCustomer!['notes'] ?? []);
    if (index < 0 || index >= currentNotes.length) return;

    final note = currentNotes[index];
    note['deleted'] = true;
    note['deletedAt'] = Timestamp.now();
    note['deletedBy'] = _currentUser?['name'] ?? 'User';

    currentNotes[index] = note;

    if (mounted) {
      setState(() {
        _selectedCustomer!['notes'] = currentNotes;
        final idx = _customers.indexWhere((c) => c['id'] == customerId);
        if (idx != -1) _customers[idx]['notes'] = currentNotes;
      });
    }

    await FirebaseFirestore.instance.collection('customers').doc(customerId).update({
      'notes': currentNotes,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note marked as deleted (audit trail kept)'), backgroundColor: Colors.grey),
      );
    }
  }

  List<Map<String, dynamic>> _getFilteredNotes() {
    if (_selectedCustomer == null) return [];
    final notes = _selectedCustomer!['notes'] as List? ?? [];
    if (_showDeletedNotes) {
      return notes.cast<Map<String, dynamic>>();
    } else {
      return notes.where((note) => note['deleted'] != true).cast<Map<String, dynamic>>().toList();
    }
  }

  void _assignCustomer(String dept, String person) async {
    final customerId = _selectedCustomer!['id'];
    final customerName = _selectedCustomer!['name'];
    
    final assignedUser = _teamMembers.firstWhere(
      (member) => member['name'] == person && member['role'] == dept,
      orElse: () => {},
    );
    final assignedUserId = assignedUser['id'] ?? '';
    
    if (mounted) {
      setState(() {
        _selectedCustomer!['assignedTo'] = dept;
        _selectedCustomer!['assignedToPerson'] = person;
        _selectedCustomer!['assignedToUserId'] = assignedUserId;
        final idx = _customers.indexWhere((c) => c['id'] == customerId);
        if (idx != -1) {
          _customers[idx]['assignedTo'] = dept;
          _customers[idx]['assignedToPerson'] = person;
          _customers[idx]['assignedToUserId'] = assignedUserId;
        }
      });
      await _applyFiltersAndSort();
    }
    
    await FirebaseFirestore.instance.collection('customers').doc(customerId).update({
      'assignedTo': dept,
      'assignedToPerson': person,
      'assignedToUserId': assignedUserId,
    });
    
    if (assignedUserId.isNotEmpty) {
      await _createTask(
        assignedToUserId: assignedUserId,
        assignedToName: person,
        customerId: customerId,
        customerName: customerName,
        message: 'Customer "$customerName" has been assigned to you (${dept.toUpperCase()}). Please assist.',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Task created for $person'), backgroundColor: Colors.green),
        );
      }
    }
  }

  void _showTeamDialog(String dept) {
    final members = _teamMembers.where((m) => m['role'] == dept).toList();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Assign to $dept Team', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...members.map((m) => ListTile(
              leading: CircleAvatar(child: Text(m['avatar'])),
              title: Text(m['name']),
              onTap: () {
                Navigator.pop(c);
                _assignCustomer(dept, m['name']);
              },
            )),
          ],
        ),
      ),
    );
  }

  void _showTeamMgmt() async {
    if (_currentUser?['role'] == 'admin') {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
      await _loadTeamMembers();
    } else {
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Team Members'),
          content: Container(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _teamMembers.length,
              itemBuilder: (_, i) {
                final m = _teamMembers[i];
                return ListTile(
                  leading: CircleAvatar(child: Text(m['avatar'])),
                  title: Text(m['name']),
                  subtitle: Text(m['role']),
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
        ),
      );
    }
  }

  void _markRead(Map<String, dynamic> c) {
    if (c['unread'] > 0 && mounted) {
      setState(() => c['unread'] = 0);
    }
  }

  void _markAllRead() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Mark all as read'),
        content: const Text('Are you sure?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _customers.forEach((c) => c['unread'] = 0));
      await _applyFiltersAndSort();
    }
  }

  void _deleteCustomer() async {
    final customer = _selectedCustomer!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Customer'),
        content: Text('Delete ${customer['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(c, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final deleted = Map<String, dynamic>.from(customer);
      setState(() {
        _customers.removeWhere((c) => c['id'] == customer['id']);
        _selectedCustomer = null;
      });
      await FirebaseFirestore.instance.collection('customers').doc(customer['id']).delete();
      await _applyFiltersAndSort();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${customer['name']} deleted'),
          action: SnackBarAction(label: 'UNDO', onPressed: () => setState(() => _customers.add(deleted))),
        ));
      }
    }
  }

  Widget _buildAssignBtn(String title, IconData icon, Color color, String val) {
    return Expanded(
      child: OutlinedButton(
        onPressed: () => _showTeamDialog(val),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _selectedCustomer!['assignedTo'] == val ? color : Colors.grey),
          backgroundColor: _selectedCustomer!['assignedTo'] == val ? color.withOpacity(0.1) : null,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(icon, size: 16, color: _selectedCustomer!['assignedTo'] == val ? color : Colors.grey), const SizedBox(width: 4), Text(title, style: TextStyle(fontSize: 12))]),
      ),
    );
  }

  Widget _buildFilterChip(String label, String val) => FilterChip(label: Text(label), selected: _selectedFilter == val, onSelected: (_) => setState(() => _selectedFilter = val));

  void _onSearchChanged(String value) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      setState(() => _searchQuery = value);
      _applyFiltersAndSort();
    });
  }

  void _clearSearch() {
    setState(() => _searchQuery = '');
    _applyFiltersAndSort();
  }

  void _openDashboard() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DashboardScreen()));
  }

  void _openTasks() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const TasksScreen()));
  }

  String _formatDateTime(DateTime d) {
    return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // ========== UPDATED _openChat WITH TASK COMPLETION CONFIRMATION ==========
  void _openChat() async {
    final customer = _selectedCustomer!;
    final customerId = customer['id'];
    final hasPendingTask = _customerIdsWithPendingTasks.contains(customerId);
    
    if (hasPendingTask) {
      final shouldComplete = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Complete Task?'),
          content: Text('Do you want to mark the task for "${customer['name']}" as completed?'),
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
        final tasksQuery = await FirebaseFirestore.instance
            .collection('tasks')
            .where('customerId', isEqualTo: customerId)
            .where('assignedToUserId', isEqualTo: currentUserId)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get();
        
        for (var doc in tasksQuery.docs) {
          await doc.reference.update({
            'status': 'completed',
            'completedAt': FieldValue.serverTimestamp(),
          });
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Task completed!'), backgroundColor: Colors.green),
          );
        }
      }
    }
    
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(customer: customer)));
  }

  @override
  Widget build(BuildContext context) {
    final userRole = _currentUser?['role'] ?? 'user';
    final userName = _currentUser?['name'] ?? 'User';
    Color roleColor;
    switch (userRole) {
      case 'admin':
        roleColor = Colors.red;
        break;
      case 'sales':
        roleColor = Colors.blue;
        break;
      case 'support':
        roleColor = Colors.green;
        break;
      case 'delivery':
        roleColor = Colors.orange;
        break;
      default:
        roleColor = Colors.grey;
    }

    Widget customerList;
    if (_isLoading || _isFiltering) {
      customerList = _buildLoadingSkeleton();
    } else if (_filteredAndSortedCustomers.isEmpty) {
      customerList = _buildEmptyState();
    } else {
      customerList = ListView.builder(
        shrinkWrap: true,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _filteredAndSortedCustomers.length,
        itemBuilder: (_, i) {
          final c = _filteredAndSortedCustomers[i];
          final hasPendingTask = _customerIdsWithPendingTasks.contains(c['id']);
          return RepaintBoundary(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: hasPendingTask
                    ? const BorderSide(color: Colors.red, width: 2)
                    : BorderSide.none,
              ),
              child: InkWell(
                onTap: () {
                  _markRead(c);
                  setState(() => _selectedCustomer = c);
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(backgroundColor: Colors.green[100], child: Text(c['name'][0], style: const TextStyle(fontWeight: FontWeight.bold))),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                    if (hasPendingTask) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Text(
                                          'Task',
                                          style: TextStyle(color: Colors.white, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                Text(c['business'], style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                                if (c['assignedToPerson'].isNotEmpty) Text(c['assignedToPerson'], style: TextStyle(fontSize: 9, color: Colors.grey[500])),
                              ],
                            ),
                          ),
                          Column(
                            children: [
                              Text(c['time'], style: TextStyle(fontSize: 10, color: Colors.grey[500])),
                              if (c['unread'] > 0)
                                Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: Text('${c['unread']}', style: const TextStyle(color: Colors.white, fontSize: 9))),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        children: (c['tags'] as List).map((t) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: _getTagColor(t).withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                          child: Text(t, style: TextStyle(fontSize: 9, color: _getTagColor(t))),
                        )).toList(),
                      ),
                      const SizedBox(height: 6),
                      Text(c['lastMessage'], maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('WhatsApp Unified Inbox'),
            Row(
              children: [
                Text('$userName ($userRole)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal)),
                const SizedBox(width: 8),
                Container(width: 10, height: 10, decoration: BoxDecoration(color: roleColor, shape: BoxShape.circle)),
              ],
            ),
          ],
        ),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.cloud_upload), onPressed: _loadCustomers, tooltip: 'Refresh'),
          IconButton(icon: const Icon(Icons.people), onPressed: _showTeamMgmt, tooltip: 'Team'),
          IconButton(icon: const Icon(Icons.mark_email_read), onPressed: _markAllRead),
          StreamBuilder<QuerySnapshot>(
            stream: currentUserId != null
                ? FirebaseFirestore.instance
                    .collection('tasks')
                    .where('assignedToUserId', isEqualTo: currentUserId)
                    .where('status', isEqualTo: 'pending')
                    .snapshots()
                : null,
            builder: (context, snapshot) {
              final pendingCount = snapshot.data?.docs.length ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.assignment),
                    onPressed: _openTasks,
                    tooltip: 'My Tasks',
                  ),
                  if (pendingCount > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$pendingCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          IconButton(icon: const Icon(Icons.file_download), onPressed: _exportToCsv),
          IconButton(icon: const Icon(Icons.picture_as_pdf), onPressed: _exportToPdf),
          IconButton(icon: const Icon(Icons.dashboard), onPressed: _openDashboard, tooltip: 'Dashboard'),
          IconButton(icon: const Icon(Icons.settings), onPressed: _openSettings),
          if (_isLoading) const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(30),
          child: ValueListenableBuilder<bool>(
            valueListenable: _isOnlineNotifier,
            builder: (context, isOnline, _) {
              return Container(
                width: double.infinity,
                color: isOnline ? Colors.green[700] : Colors.red[700],
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Center(
                  child: Text(
                    isOnline ? 'Online' : 'Offline',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: constraints.maxWidth,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: constraints.maxWidth - (_selectedCustomer != null ? 380 : 0).clamp(300, double.infinity),
                    child: Column(
                      children: [
                        // Search bar
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: 'Search by name, business, or phone number...',
                              prefixIcon: const Icon(Icons.search),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      onPressed: _clearSearch,
                                    )
                                  : null,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onChanged: _onSearchChanged,
                          ),
                        ),
                        // Assignment filter chips
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(children: [
                            _buildFilterChip('All', 'all'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Sales', 'sales'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Support', 'support'),
                            const SizedBox(width: 8),
                            _buildFilterChip('Delivery', 'delivery'),
                          ]),
                        ),
                        if (_selectedFilter != 'all' && _teamMembersByRole.isNotEmpty)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              FilterChip(label: const Text('All'), selected: _selectedPersonFilter == 'all', onSelected: (_) => setState(() => _selectedPersonFilter = 'all')),
                              ..._teamMembersByRole.map((m) => FilterChip(
                                label: Text(m['name']),
                                selected: _selectedPersonFilter == m['name'],
                                onSelected: (_) => setState(() => _selectedPersonFilter = m['name']),
                                avatar: CircleAvatar(radius: 12, backgroundColor: Colors.green[100], child: Text(m['avatar'], style: const TextStyle(fontSize: 10))),
                              )),
                            ]),
                          ),
                        // Compact Dashboard Card
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Text('Payments', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                                      const SizedBox(width: 8),
                                      Text(
                                        'KES ${_dashboardTotalPayments.toStringAsFixed(2)}',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.green.shade200),
                                    ),
                                    child: DropdownButton<String>(
                                      value: _dashboardDateFilter,
                                      underline: const SizedBox(),
                                      icon: const Icon(Icons.arrow_drop_down, color: Colors.green, size: 20),
                                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                                      items: const [
                                        DropdownMenuItem(value: 'today', child: Text('Today')),
                                        DropdownMenuItem(value: 'thisWeek', child: Text('This Week')),
                                        DropdownMenuItem(value: 'thisMonth', child: Text('This Month')),
                                        DropdownMenuItem(value: 'custom', child: Text('Custom Range')),
                                      ],
                                      onChanged: (String? newValue) async {
                                        if (newValue == 'custom') {
                                          await _selectCustomDateRange();
                                        } else if (newValue != null) {
                                          setState(() {
                                            _dashboardDateFilter = newValue;
                                            _customDateRange = null;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              if (_dashboardDateFilter == 'custom' && _customDateRange != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '${_formatDate(_customDateRange!.start)} - ${_formatDate(_customDateRange!.end)}',
                                    style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Compact Stats Row
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                          decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: Row(children: [
                            _buildStatItem(Icons.people, 'Total', _stats['total']),
                            _buildStatItem(Icons.mark_email_unread, 'Unread', _stats['unread']),
                            _buildStatItem(Icons.currency_exchange, 'Debt', 'KES ${_stats['debtTotal']}'),
                            _buildStatItem(Icons.star, 'VIP', _stats['vipCount']),
                          ]),
                        ),
                        const SizedBox(height: 8),
                        // Customer list
                        Expanded(
                          child: RefreshIndicator(
                            key: _refreshIndicatorKey,
                            onRefresh: () async {
                              await _loadCustomers();
                              await _applyFiltersAndSort();
                            },
                            child: customerList,
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
                                Expanded(child: Text(_selectedCustomer!['name'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: _editCustomer),
                                IconButton(icon: const Icon(Icons.delete, color: Colors.white), onPressed: _deleteCustomer),
                                IconButton(icon: const Icon(Icons.message, color: Colors.white), onPressed: _openChat, tooltip: 'WhatsApp Chat'),
                                IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedCustomer = null)),
                              ],
                            ),
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Customer details
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      children: [
                                        Row(children: [const Icon(Icons.business, size: 16), const SizedBox(width: 8), Expanded(child: Text(_selectedCustomer!['business']))]),
                                        const SizedBox(height: 8),
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Padding(padding: EdgeInsets.only(top: 2), child: Icon(Icons.phone, size: 16)),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: (_selectedCustomer!['phoneNumbers'] as List<String>)
                                                    .map((phone) => Chip(label: Text(phone), visualDensity: VisualDensity.compact, backgroundColor: Colors.grey[200]))
                                                    .toList(),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Debt management
                                  Container(
                                    margin: const EdgeInsets.only(top: 16),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Current Debt'), Text('KES ${_selectedCustomer!['debtAmount'].toStringAsFixed(0)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]),
                                        ElevatedButton.icon(onPressed: _manageDebt, icon: const Icon(Icons.edit, size: 18), label: const Text('Manage Debt'), style: ElevatedButton.styleFrom(backgroundColor: Colors.green)),
                                      ],
                                    ),
                                  ),
                                  // M-PESA
                                  Container(
                                    margin: const EdgeInsets.only(top: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(12)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Row(children: [Icon(Icons.mobile_friendly, color: Colors.blue), SizedBox(width: 8), Text('Request Payment via M-PESA', style: TextStyle(fontWeight: FontWeight.bold))]),
                                        const SizedBox(height: 12),
                                        SizedBox(
                                          width: double.infinity,
                                          child: ElevatedButton.icon(
                                            onPressed: _isMpesaRequesting ? null : _requestMpesaPayment,
                                            icon: _isMpesaRequesting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.payment, size: 18),
                                            label: Text(_isMpesaRequesting ? 'Sending...' : 'Request Payment'),
                                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  // Notes and Transactions tabs
                                  DefaultTabController(
                                    length: 2,
                                    child: Column(
                                      children: [
                                        if (_currentUser?['role'] == 'admin')
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [
                                              TextButton.icon(
                                                onPressed: () {
                                                  setState(() {
                                                    _showDeletedNotes = !_showDeletedNotes;
                                                  });
                                                },
                                                icon: Icon(_showDeletedNotes ? Icons.visibility_off : Icons.visibility),
                                                label: Text(_showDeletedNotes ? 'Hide Deleted' : 'Show Deleted'),
                                                style: TextButton.styleFrom(foregroundColor: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        const TabBar(tabs: [Tab(text: 'Notes'), Tab(text: 'Transactions')]),
                                        SizedBox(
                                          height: 300,
                                          child: TabBarView(
                                            children: [
                                              // Notes tab
                                              Column(
                                                children: [
                                                  Expanded(
                                                    child: Container(
                                                      padding: const EdgeInsets.all(12),
                                                      decoration: BoxDecoration(color: Colors.grey[50], borderRadius: BorderRadius.circular(12)),
                                                      child: _getFilteredNotes().isEmpty
                                                          ? Center(
                                                              child: Text(
                                                                _showDeletedNotes ? 'No notes (deleted or otherwise)' : 'No active notes',
                                                              ),
                                                            )
                                                          : ListView.builder(
                                                              itemCount: _getFilteredNotes().length,
                                                              itemBuilder: (context, index) {
                                                                final note = _getFilteredNotes()[index];
                                                                final text = note['text'] ?? '';
                                                                final createdAt = (note['createdAt'] as Timestamp?)?.toDate();
                                                                final author = note['author'] ?? 'User';
                                                                final isDeleted = note['deleted'] == true;
                                                                final deletedAt = (note['deletedAt'] as Timestamp?)?.toDate();
                                                                final deletedBy = note['deletedBy'] ?? 'Unknown';

                                                                return Dismissible(
                                                                  key: Key('note_${note['text']}_${note['createdAt']}'),
                                                                  direction: isDeleted ? DismissDirection.none : DismissDirection.endToStart,
                                                                  onDismissed: isDeleted ? null : (_) => _deleteNote(index),
                                                                  background: isDeleted
                                                                      ? null
                                                                      : Container(
                                                                          color: Colors.red,
                                                                          alignment: Alignment.centerRight,
                                                                          padding: const EdgeInsets.only(right: 20),
                                                                          child: const Icon(Icons.delete, color: Colors.white),
                                                                        ),
                                                                  child: Card(
                                                                    margin: const EdgeInsets.symmetric(vertical: 4),
                                                                    color: isDeleted ? Colors.grey[100] : null,
                                                                    child: ListTile(
                                                                      title: Text(
                                                                        text,
                                                                        style: TextStyle(
                                                                          decoration: isDeleted ? TextDecoration.lineThrough : null,
                                                                          color: isDeleted ? Colors.grey : null,
                                                                        ),
                                                                      ),
                                                                      subtitle: Column(
                                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                                        children: [
                                                                          Text('$author • ${createdAt != null ? _formatDateTime(createdAt) : 'Unknown date'}'),
                                                                          if (isDeleted && deletedAt != null)
                                                                            Text(
                                                                              'Deleted by $deletedBy on ${_formatDateTime(deletedAt)}',
                                                                              style: const TextStyle(fontSize: 10, color: Colors.red),
                                                                            ),
                                                                        ],
                                                                      ),
                                                                      trailing: isDeleted
                                                                          ? null
                                                                          : IconButton(
                                                                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                                                              onPressed: () => _deleteNote(index),
                                                                              tooltip: 'Soft delete (kept for audit)',
                                                                            ),
                                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                                    ),
                                                                  ),
                                                                );
                                                              },
                                                            ),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: TextField(
                                                          controller: _noteController,
                                                          decoration: const InputDecoration(hintText: 'Add a note...', border: OutlineInputBorder()),
                                                          onSubmitted: (_) => _addNote(),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      InkWell(
                                                        onTap: _addNote,
                                                        child: Container(
                                                          padding: const EdgeInsets.all(10),
                                                          decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle),
                                                          child: const Icon(Icons.send, color: Colors.white, size: 18),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              // Transaction history
                                              _buildTransactionHistory(),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('Assign To', style: TextStyle(fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 12),
                                  Row(children: [
                                    _buildAssignBtn('Sales', Icons.trending_up, Colors.blue, 'sales'),
                                    const SizedBox(width: 4),
                                    _buildAssignBtn('Support', Icons.support_agent, Colors.green, 'support'),
                                    const SizedBox(width: 4),
                                    _buildAssignBtn('Delivery', Icons.local_shipping, Colors.orange, 'delivery'),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: _addCustomer, backgroundColor: Colors.green, child: const Icon(Icons.add, color: Colors.white)),
    );
  }

  Widget _buildTransactionHistory() {
    final cid = _selectedCustomer!['id'];
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .where('customerId', isEqualTo: cid)
          .where('tenantId', isEqualTo: currentTenantId)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) return const Center(child: Text('No transactions yet'));
        return ListView.builder(
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data() as Map<String, dynamic>;
            final type = d['type'];
            final amount = (d['amount'] as num).toDouble();
            final prev = (d['previousDebt'] as num).toDouble();
            final nxt = (d['newDebt'] as num).toDouble();
            final note = d['note'] ?? '';
            final ts = (d['timestamp'] as Timestamp?)?.toDate();
            return Card(
              child: ListTile(
                leading: Icon(type == 'add_debt' ? Icons.add_circle : (type == 'reduce_debt' ? Icons.payment : Icons.mobile_friendly), color: type == 'add_debt' ? Colors.red : Colors.green),
                title: Text('${type == 'add_debt' ? 'Debt Added' : (type == 'reduce_debt' ? 'Manual Payment' : 'M-PESA Payment')}: KES ${amount.toStringAsFixed(2)}'),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Debt: KES ${prev.toStringAsFixed(2)} → KES ${nxt.toStringAsFixed(2)}'),
                  if (note.isNotEmpty) Text(note, style: const TextStyle(fontSize: 12)),
                  if (ts != null) Text(_formatDate(ts), style: const TextStyle(fontSize: 10)),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime d) => '${d.day}/${d.month}/${d.year}';

  void _showErrorAndLogout(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
    FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const AuthWrapper()), (route) => false);
    }
  }

  Widget _buildLoadingSkeleton() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        itemCount: 5,
        itemBuilder: (_, __) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(width: double.infinity, height: 14, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(width: 100, height: 12, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty || _selectedFilter != 'all' ? 'No matching customers' : 'No customers yet',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          if (_searchQuery.isNotEmpty || _selectedFilter != 'all')
            TextButton.icon(
              onPressed: () => setState(() {
                _searchQuery = '';
                _selectedFilter = 'all';
                _selectedPersonFilter = 'all';
              }),
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear filters'),
            )
          else
            TextButton.icon(
              onPressed: _addCustomer,
              icon: const Icon(Icons.add),
              label: const Text('Add your first customer'),
            ),
        ],
      ),
    );
  }

  void _openSettings() => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
}