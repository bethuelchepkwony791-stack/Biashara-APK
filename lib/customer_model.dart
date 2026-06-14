class Customer {
  final String id;
  final String name;
  final String businessName;
  final String phone;
  final List<String> tags;
  final String assignedTo;
  final double debtAmount;
  final String notes;
  final DateTime lastMessageTime;
  final String lastMessage;
  final int unreadCount;

  Customer({
    required this.id,
    required this.name,
    required this.businessName,
    required this.phone,
    required this.tags,
    required this.assignedTo,
    required this.debtAmount,
    required this.notes,
    required this.lastMessageTime,
    required this.lastMessage,
    required this.unreadCount,
  });

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'businessName': businessName,
      'phone': phone,
      'tags': tags,
      'assignedTo': assignedTo,
      'debtAmount': debtAmount,
      'notes': notes,
      'lastMessageTime': lastMessageTime,
      'lastMessage': lastMessage,
      'unreadCount': unreadCount,
    };
  }

  factory Customer.fromMap(String id, Map<String, dynamic> map) {
    return Customer(
      id: id,
      name: map['name'] ?? '',
      businessName: map['businessName'] ?? '',
      phone: map['phone'] ?? '',
      tags: List<String>.from(map['tags'] ?? []),
      assignedTo: map['assignedTo'] ?? 'unassigned',
      debtAmount: (map['debtAmount'] ?? 0).toDouble(),
      notes: map['notes'] ?? '',
      lastMessageTime: (map['lastMessageTime'] as DateTime?) ?? DateTime.now(),
      lastMessage: map['lastMessage'] ?? '',
      unreadCount: map['unreadCount'] ?? 0,
    );
  }
}