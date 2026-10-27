const photoKindLabel = {
  'RECEIVED': 'Saat diterima',
  'READY': 'Saat siap diambil',
};

class OrderPhoto {
  const OrderPhoto({required this.id, required this.orderId, required this.kind});

  final int id;
  final int orderId;
  final String kind;

  factory OrderPhoto.fromJson(Map<String, dynamic> j) => OrderPhoto(
        id: j['id'] as int,
        orderId: j['orderId'] as int,
        kind: j['kind'] as String,
      );
}