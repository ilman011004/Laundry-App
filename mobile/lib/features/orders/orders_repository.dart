import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'order_models.dart';

class OrdersRepository {
  OrdersRepository(this._dio);

  final Dio _dio;

  Future<OrderPage> list({
    String? search,
    String? workStatus,
    String? paymentStatus,
    String? view,
    int page = 1,
    int limit = 20,
  }) async {
    final res = await _dio.get('/api/orders', queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'workStatus': ?workStatus,
      'paymentStatus': ?paymentStatus,
      'view': ?view,
      'page': page,
      'limit': limit,
    });

    final meta = res.data['meta'] as Map<String, dynamic>;

    return OrderPage(
      items: (res.data['data'] as List)
          .map((e) => OrderSummary.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: meta['page'] as int,
      totalPages: meta['totalPages'] as int,
    );
  }

  Future<OrderDetail> detail(int id) async {
    final res = await _dio.get('/api/orders/$id');
    return OrderDetail.fromJson(
      res.data['data'] as Map<String, dynamic>,
    );
  }

  Future<void> pay(
    int id, {
    required int amount,
    required String method,
    String? note,
  }) async {
    await _dio.post('/api/orders/$id/payments', data: {
      'amount': amount,
      'method': method,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  /// Mengembalikan peringatan dari backend
  /// (mis. diserahkan dengan sisa tagihan), jika ada.
  Future<String?> updateStatus(
    int id, {
    required String status,
    String? note,
  }) async {
    final res = await _dio.patch('/api/orders/$id/status', data: {
      'status': status,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });

    return (res.data['data'] as Map<String, dynamic>)['warning'] as String?;
  }

  Future<void> cancel(
    int id, {
    required String note,
  }) async {
    await _dio.post(
      '/api/orders/$id/cancel',
      data: {'note': note.trim()},
    );
  }
}

final ordersRepositoryProvider = Provider<OrdersRepository>(
  (ref) => OrdersRepository(ref.watch(dioProvider)),
);

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderDetail, int>((ref, id) {
  return ref.watch(ordersRepositoryProvider).detail(id);
});

/// Dinaikkan setiap ada pesanan baru, supaya daftar pesanan memuat ulang.
class OrdersRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final ordersRevisionProvider =
    NotifierProvider<OrdersRevision, int>(OrdersRevision.new);