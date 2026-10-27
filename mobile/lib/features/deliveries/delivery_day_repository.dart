import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'delivery_models.dart';

/// Satu tugas jemput/antar beserta data pesanan dan pelanggannya.
class DeliveryTask {
  const DeliveryTask({
    required this.delivery,
    required this.orderNumber,
    required this.orderWorkStatus,
    required this.customerName,
    required this.customerPhone,
  });

  final Delivery delivery;
  final String orderNumber;
  final String orderWorkStatus;
  final String customerName;
  final String customerPhone;

  factory DeliveryTask.fromJson(Map<String, dynamic> j) {
    final o = j['order'] as Map<String, dynamic>? ?? const {};
    final c = o['customer'] as Map<String, dynamic>? ?? const {};
    return DeliveryTask(
      delivery: Delivery.fromJson(j),
      orderNumber: (o['orderNumber'] as String?) ?? '-',
      orderWorkStatus: (o['workStatus'] as String?) ?? '',
      customerName: (c['name'] as String?) ?? '-',
      customerPhone: (c['phone'] as String?) ?? '',
    );
  }
}

/// [day] berformat "YYYY-MM-DD" (tanggal usaha).
final deliveriesByDayProvider =
    FutureProvider.autoDispose.family<List<DeliveryTask>, String>((ref, day) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get('/api/deliveries', queryParameters: {
    'from': day,
    'to': day,
    'limit': 100,
  });
  final list = (res.data['data'] as List)
      .map((e) => DeliveryTask.fromJson(e as Map<String, dynamic>))
      .toList();
  list.sort((a, b) {
    final x = a.delivery.scheduledAt, y = b.delivery.scheduledAt;
    if (x == null && y == null) return 0;
    if (x == null) return 1;
    if (y == null) return -1;
    return x.compareTo(y);
  });
  return list;
});