import '../../core/format.dart';

/// Nilai desimal dari backend bisa berupa angka atau teks ("5.00").
double _toDouble(Object? v) => double.tryParse('$v') ?? 0;

class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.orderNumber,
    required this.workStatus,
    required this.paymentStatus,
    required this.total,
    required this.paidAmount,
    required this.customerName,
    this.speedName,
    this.estimatedDoneAt,
  });

  final int id;
  final String orderNumber;
  final String workStatus;
  final String paymentStatus;
  final int total;
  final int paidAmount;
  final String customerName;
  final String? speedName;
  final DateTime? estimatedDoneAt;

  int get remaining => total - paidAmount;

  factory OrderSummary.fromJson(Map<String, dynamic> j) {
    final c = j['customer'] as Map<String, dynamic>?;
    return OrderSummary(
      id: j['id'] as int,
      orderNumber: j['orderNumber'] as String,
      workStatus: j['workStatus'] as String,
      paymentStatus: j['paymentStatus'] as String,
      total: j['total'] as int,
      paidAmount: j['paidAmount'] as int,
      customerName: (c?['name'] as String?) ?? '-',
      speedName: j['speedName'] as String?,
      estimatedDoneAt: parseApiDate(j['estimatedDoneAt'] as String?),
    );
  }
}

class OrderPage {
  const OrderPage({required this.items, required this.page, required this.totalPages});

  final List<OrderSummary> items;
  final int page;
  final int totalPages;

  bool get hasMore => page < totalPages;
}

class OrderAddon {
  const OrderAddon({required this.name, required this.amount});
  final String name;
  final int amount;
}

class OrderItem {
  const OrderItem({
    required this.serviceName,
    required this.pricingType,
    required this.unitPrice,
    required this.quantity,
    required this.lineTotal,
    required this.addons,
    this.notes,
  });

  final String serviceName;
  final String pricingType;
  final int unitPrice;
  final double quantity;
  final int lineTotal;
  final String? notes;
  final List<OrderAddon> addons;

  String get unit => switch (pricingType) {
        'PER_KG' => 'kg',
        'PER_ITEM' => 'item',
        _ => 'paket',
      };

  int get addonsTotal => addons.fold(0, (s, a) => s + a.amount);
}

class StatusEntry {
  const StatusEntry({
    required this.toStatus,
    required this.createdAt,
    this.changedBy,
    this.note,
  });

  final String toStatus;
  final DateTime createdAt;
  final String? changedBy;
  final String? note;
}

class PaymentEntry {
  const PaymentEntry({
    required this.amount,
    required this.method,
    required this.paidAt,
    this.note,
  });

  final int amount;
  final String method;
  final DateTime paidAt;
  final String? note;
}

class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.orderNumber,
    required this.workStatus,
    required this.paymentStatus,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.history,
    required this.payments,
    required this.speedFee,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.paidAmount,
    required this.receivedAt,
    this.speedName,
    this.fulfillmentName,
    this.receiveMethod,
    this.notes,
    this.estimatedDoneAt,
    this.completedAt,
  });

  final int id;
  final String orderNumber;
  final String workStatus;
  final String paymentStatus;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final List<StatusEntry> history;
  final List<PaymentEntry> payments;
  final String? speedName;
  final int speedFee;
  final String? fulfillmentName;
  final String? receiveMethod;
  final int deliveryFee;
  final int discount;
  final int total;
  final int paidAmount;
  final String? notes;
  final DateTime receivedAt;
  final DateTime? estimatedDoneAt;
  final DateTime? completedAt;

  int get remaining => total - paidAmount;
  bool get isCancelled => workStatus == 'CANCELLED';
  bool get isCompleted => workStatus == 'COMPLETED';

  factory OrderDetail.fromJson(Map<String, dynamic> j) {
    final c = j['customer'] as Map<String, dynamic>;
    return OrderDetail(
      id: j['id'] as int,
      orderNumber: j['orderNumber'] as String,
      workStatus: j['workStatus'] as String,
      paymentStatus: j['paymentStatus'] as String,
      customerId: c['id'] as int,
      customerName: c['name'] as String,
      customerPhone: c['phone'] as String,
      items: ((j['items'] as List?) ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return OrderItem(
          serviceName: m['serviceName'] as String,
          pricingType: m['pricingType'] as String,
          unitPrice: m['unitPrice'] as int,
          quantity: _toDouble(m['quantity']),
          lineTotal: m['lineTotal'] as int,
          notes: m['notes'] as String?,
          addons: ((m['addons'] as List?) ?? []).map((a) {
            final am = a as Map<String, dynamic>;
            return OrderAddon(name: am['name'] as String, amount: am['amount'] as int);
          }).toList(),
        );
      }).toList(),
      history: ((j['history'] as List?) ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return StatusEntry(
          toStatus: m['toStatus'] as String,
          createdAt: DateTime.parse(m['createdAt'] as String),
          changedBy: (m['changedBy'] as Map<String, dynamic>?)?['name'] as String?,
          note: m['note'] as String?,
        );
      }).toList(),
      payments: ((j['payments'] as List?) ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return PaymentEntry(
          amount: m['amount'] as int,
          method: m['method'] as String,
          paidAt: DateTime.parse(m['paidAt'] as String),
          note: m['note'] as String?,
        );
      }).toList(),
      speedName: j['speedName'] as String?,
      speedFee: j['speedFee'] as int,
      fulfillmentName: j['fulfillmentName'] as String?,
      receiveMethod: j['receiveMethod'] as String?,
      deliveryFee: j['deliveryFee'] as int,
      discount: j['discount'] as int,
      total: j['total'] as int,
      paidAmount: j['paidAmount'] as int,
      notes: j['notes'] as String?,
      receivedAt: DateTime.parse(j['receivedAt'] as String),
      estimatedDoneAt: parseApiDate(j['estimatedDoneAt'] as String?),
      completedAt: parseApiDate(j['completedAt'] as String?),
    );
  }
}