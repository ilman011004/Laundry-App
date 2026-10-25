import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import 'customer_models.dart';

class CustomersRepository {
  CustomersRepository(this._dio);

  final Dio _dio;

  Future<CustomerPage> list({String? search, int page = 1, int limit = 20}) async {
    final res = await _dio.get('/api/customers', queryParameters: {
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      'page': page,
      'limit': limit,
    });
    final meta = res.data['meta'] as Map<String, dynamic>;
    return CustomerPage(
      items: (res.data['data'] as List)
          .map((e) => Customer.fromJson(e as Map<String, dynamic>))
          .toList(),
      page: meta['page'] as int,
      totalPages: meta['totalPages'] as int,
    );
  }

  Future<CustomerDetail> detail(int id) async {
    final res = await _dio.get('/api/customers/$id');
    return CustomerDetail.fromJson(res.data['data'] as Map<String, dynamic>);
  }

  Future<void> create({
    required String name,
    required String phone,
    String? notes,
    String? addressLabel,
    String? address,
  }) async {
    await _dio.post('/api/customers', data: {
      'name': name.trim(),
      'phone': phone.trim(),
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (address != null && address.trim().isNotEmpty)
        'address': {
          'label': (addressLabel == null || addressLabel.trim().isEmpty)
              ? 'Rumah'
              : addressLabel.trim(),
          'address': address.trim(),
        },
    });
  }

  Future<void> update(int id, {required String name, required String phone, String? notes}) async {
    await _dio.patch('/api/customers/$id', data: {
      'name': name.trim(),
      'phone': phone.trim(),
      'notes': (notes == null || notes.trim().isEmpty) ? null : notes.trim(),
    });
  }

  Future<void> addAddress(int id, {required String label, required String address}) async {
    await _dio.post('/api/customers/$id/addresses', data: {
      'label': label.trim().isEmpty ? 'Rumah' : label.trim(),
      'address': address.trim(),
    });
  }

  Future<void> setDefaultAddress(int id, int addressId) async {
    await _dio.patch('/api/customers/$id/addresses/$addressId', data: {'isDefault': true});
  }

  Future<void> deleteAddress(int id, int addressId) async {
    await _dio.delete('/api/customers/$id/addresses/$addressId');
  }
}

final customersRepositoryProvider =
    Provider<CustomersRepository>((ref) => CustomersRepository(ref.watch(dioProvider)));

final customerDetailProvider =
    FutureProvider.autoDispose.family<CustomerDetail, int>((ref, id) {
  return ref.watch(customersRepositoryProvider).detail(id);
});