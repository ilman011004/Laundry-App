import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config.dart';

/// Satu klien Dio untuk seluruh aplikasi.
/// Token login dan penanganan token kedaluwarsa ditambahkan di tahap berikutnya.
final dioProvider = Provider<Dio>((ref) {
  return Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: {'Accept': 'application/json'},
    ),
  );
});

/// Cek koneksi ke backend lewat GET /health.
/// Kesalahan ditangkap di sini dan diubah menjadi pesan, bukan dilempar.
final healthProvider = FutureProvider.autoDispose<String>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get('/health');
    final data = res.data;
    if (data is Map && data['status'] == 'ok') {
      return 'Server terhubung dan database aktif.';
    }
    return 'Server menjawab, tetapi statusnya tidak normal.';
  } on DioException catch (e) {
    if (e.response?.statusCode == 503) {
      return 'Server aktif, tetapi database tidak terjangkau.';
    }
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Tidak bisa terhubung ke server di ${AppConfig.apiBaseUrl}.\n'
          'Pastikan backend berjalan dan alamatnya benar.';
    }
    return 'Terjadi kesalahan: ${e.message ?? e.type.name}';
  }
});