import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import '../auth/auth_controller.dart';

class Business {
  const Business({required this.name, required this.address, required this.phone});

  final String name;
  final String address;
  final String phone;

  factory Business.fromJson(Map<String, dynamic> j) => Business(
        name: (j['name'] as String?) ?? 'Laundry',
        address: (j['address'] as String?) ?? '',
        phone: (j['phone'] as String?) ?? '',
      );
}

/// Dimuat ulang otomatis saat pengguna berganti.
final businessProvider = FutureProvider<Business>((ref) async {
  ref.watch(authControllerProvider.select((s) => s.user?.id));
  final res = await ref.watch(dioProvider).get('/api/business');
  return Business.fromJson(res.data['data'] as Map<String, dynamic>);
});

Future<void> saveBusiness(
  Ref ref, {
  required String name,
  required String address,
  required String phone,
}) async {
  await ref.read(dioProvider).patch('/api/business', data: {
    'name': name.trim(),
    'address': address.trim(),
    'phone': phone.trim(),
  });
  ref.invalidate(businessProvider);
}