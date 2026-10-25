import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'pos_models.dart';

class PosRepository {
  PosRepository(this._dio);

  final Dio _dio;

  Future<PosCatalog> catalog() async {
    final res = await _dio.get('/api/catalog');
    return PosCatalog.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<PricePreview> preview(Map<String, dynamic> input) async {
    final res = await _dio.post('/api/orders/preview', data: input);
    return PricePreview.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<({int id, String orderNumber, int total})> create(
      Map<String, dynamic> input) async {
    final res = await _dio.post('/api/orders', data: input);
    final d = res.data['data'] as Map<String, dynamic>;
    return (
      id: d['id'] as int,
      orderNumber: d['orderNumber'] as String,
      total: d['total'] as int,
    );
  }
}

final posRepositoryProvider =
    Provider<PosRepository>((ref) => PosRepository(ref.watch(dioProvider)));

final catalogProvider = FutureProvider.autoDispose<PosCatalog>((ref) {
  return ref.watch(posRepositoryProvider).catalog();
});