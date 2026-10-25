import 'package:dio/dio.dart';

/// Ubah error apa pun menjadi pesan bahasa Indonesia untuk pengguna.
String errorMessage(Object error) {
  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Server terlalu lama menjawab. Coba lagi.';
      case DioExceptionType.connectionError:
        return 'Tidak bisa terhubung ke server. Periksa koneksi dan pastikan server berjalan.';
      default:
        break;
    }

    // Backend mengirim {"message": "...", "details": ...}
    final data = error.response?.data;
    if (data is Map && data['message'] is String) {
      return data['message'] as String;
    }

    final code = error.response?.statusCode;
    if (code != null) return 'Terjadi kesalahan pada server (kode $code).';
  }
  return 'Terjadi kesalahan. Coba lagi.';
}