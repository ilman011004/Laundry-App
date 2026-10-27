import '../../core/format.dart';

const deliveryTypeLabel = {'PICKUP': 'Jemput', 'DROPOFF': 'Antar'};

const deliveryStatusLabel = {
  'SCHEDULED': 'Dijadwalkan',
  'ON_THE_WAY': 'Dalam perjalanan',
  'DONE': 'Selesai',
  'CANCELLED': 'Dibatalkan',
};

class Delivery {
  const Delivery({
    required this.id,
    required this.orderId,
    required this.type,
    required this.status,
    this.addressSnapshot,
    this.scheduledAt,
    this.notes,
  });

  final int id;
  final int orderId;
  final String type;
  final String status;
  final String? addressSnapshot;
  final DateTime? scheduledAt;
  final String? notes;

  bool get isActive => status != 'CANCELLED';
  bool get canEdit => status == 'SCHEDULED';

  factory Delivery.fromJson(Map<String, dynamic> j) => Delivery(
        id: j['id'] as int,
        orderId: j['orderId'] as int,
        type: j['type'] as String,
        status: j['status'] as String,
        addressSnapshot: j['addressSnapshot'] as String?,
        scheduledAt: parseApiDate(j['scheduledAt'] as String?),
        notes: j['notes'] as String?,
      );
}