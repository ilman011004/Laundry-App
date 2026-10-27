import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'delivery_models.dart';

class DeliveriesRepository {
  DeliveriesRepository(this._dio);

  final Dio _dio;

  Future<List<Delivery>> forOrder(int orderId) async {
    final res = await _dio.get('/api/deliveries', queryParameters: {
      'orderId': orderId,
      'limit': 20,
    });
    return (res.data['data'] as List)
        .map((e) => Delivery.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({
    required int orderId,
    required String type,
    required DateTime scheduledAt,
    String address = '',
    String notes = '',
  }) async {
    await _dio.post('/api/deliveries', data: {
      'orderId': orderId,
      'type': type,
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      if (address.trim().isNotEmpty) 'address': address.trim(),
      if (notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  Future<void> update(
    int id, {
    required DateTime scheduledAt,
    String address = '',
    String notes = '',
  }) async {
    await _dio.patch('/api/deliveries/$id', data: {
      'scheduledAt': scheduledAt.toUtc().toIso8601String(),
      if (address.trim().isNotEmpty) 'address': address.trim(),
      'notes': notes.trim(),
    });
  }

  Future<void> setStatus(int id, String status) async {
    await _dio.patch('/api/deliveries/$id/status', data: {'status': status});
  }
}

final deliveriesRepositoryProvider = Provider<DeliveriesRepository>(
    (ref) => DeliveriesRepository(ref.watch(dioProvider)));

final deliveriesProvider =
    FutureProvider.autoDispose.family<List<Delivery>, int>((ref, orderId) {
  return ref.watch(deliveriesRepositoryProvider).forOrder(orderId);
});