class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.label,
    required this.address,
    required this.isDefault,
    this.notes,
  });

  final int id;
  final String label;
  final String address;
  final String? notes;
  final bool isDefault;

  factory CustomerAddress.fromJson(Map<String, dynamic> j) => CustomerAddress(
        id: j['id'] as int,
        label: j['label'] as String,
        address: j['address'] as String,
        notes: j['notes'] as String?,
        isDefault: j['isDefault'] as bool? ?? false,
      );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.notes,
    this.addresses = const [],
    this.orderCount = 0,
  });

  final int id;
  final String name;
  final String phone;
  final String? notes;
  final List<CustomerAddress> addresses;

  /// Jumlah pesanan (tidak termasuk yang dibatalkan). Hanya terisi pada daftar pelanggan.
  final int orderCount;

  /// Pelanggan dianggap langganan mulai jumlah pesanan ini.
  static const regularThreshold = 5;
  bool get isRegular => orderCount >= regularThreshold;

  /// Alamat utama (pada daftar, backend hanya mengirim alamat utama).
  CustomerAddress? get defaultAddress {
    for (final a in addresses) {
      if (a.isDefault) return a;
    }
    return addresses.isEmpty ? null : addresses.first;
  }

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: j['id'] as int,
        name: j['name'] as String,
        phone: j['phone'] as String,
        notes: j['notes'] as String?,
        addresses: ((j['addresses'] as List?) ?? [])
            .map((e) => CustomerAddress.fromJson(e as Map<String, dynamic>))
            .toList(),
        orderCount: (j['orderCount'] as int?) ?? 0,
      );
}

class CustomerPage {
  const CustomerPage({required this.items, required this.page, required this.totalPages});

  final List<Customer> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class ActiveOrder {
  const ActiveOrder({
    required this.id,
    required this.orderNumber,
    required this.workStatus,
    required this.paymentStatus,
    required this.total,
    required this.paidAmount,
  });

  final int id;
  final String orderNumber;
  final String workStatus;
  final String paymentStatus;
  final int total;
  final int paidAmount;

  int get remaining => total - paidAmount;

  factory ActiveOrder.fromJson(Map<String, dynamic> j) => ActiveOrder(
        id: j['id'] as int,
        orderNumber: j['orderNumber'] as String,
        workStatus: j['workStatus'] as String,
        paymentStatus: j['paymentStatus'] as String,
        total: j['total'] as int,
        paidAmount: j['paidAmount'] as int,
      );
}

class CustomerDetail {
  const CustomerDetail({
    required this.customer,
    required this.activeOrders,
    required this.totalOrders,
    required this.totalSpent,
    required this.outstanding,
  });

  final Customer customer;
  final List<ActiveOrder> activeOrders;
  final int totalOrders;
  final int totalSpent;
  final int outstanding;

  factory CustomerDetail.fromJson(Map<String, dynamic> j) {
    final summary = j['summary'] as Map<String, dynamic>;
    return CustomerDetail(
      customer: Customer.fromJson(j),
      activeOrders: ((j['activeOrders'] as List?) ?? [])
          .map((e) => ActiveOrder.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalOrders: summary['totalOrders'] as int,
      totalSpent: summary['totalSpent'] as int,
      outstanding: summary['outstanding'] as int,
    );
  }
}