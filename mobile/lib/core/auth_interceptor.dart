import 'package:dio/dio.dart';
import 'token_storage.dart';

/// Menambahkan token ke setiap permintaan, dan memperbarui token otomatis
/// saat server menjawab 401 (token kedaluwarsa).
class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required this.dio,
    required this.storage,
    required this.onSessionExpired,
  });

  final Dio dio;
  final TokenStorage storage;
  final void Function() onSessionExpired;

  // Jika beberapa permintaan gagal bersamaan, penyegaran cukup dilakukan sekali.
  Future<bool>? _refreshing;

  static bool _isAuthPath(String path) =>
      path.startsWith('/api/auth/login') || path.startsWith('/api/auth/refresh');

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    if (!_isAuthPath(options.path)) {
      final token = await storage.readAccess();
      if (token != null) options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final is401 = err.response?.statusCode == 401;

    // Hanya 401 pada endpoint biasa yang dicoba ulang, dan hanya satu kali.
    if (!is401 || _isAuthPath(request.path) || request.extra['retried'] == true) {
      return handler.next(err);
    }

    bool refreshed;
    try {
      _refreshing ??= _refreshTokens().whenComplete(() => _refreshing = null);
      refreshed = await _refreshing!;
    } on DioException catch (e) {
      // Gagal karena jaringan: sesi tidak dianggap berakhir.
      return handler.next(e);
    }

    if (!refreshed) return handler.next(err);
        // FormData tidak bisa dikirim ulang. Token sudah diperbarui, pemanggil cukup mencoba lagi.
    if (request.data is FormData) return handler.next(err);

    try {
      final token = await storage.readAccess();
      request.headers['Authorization'] = 'Bearer $token';
      request.extra['retried'] = true;
      final response = await dio.fetch(request);
      handler.resolve(response);
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  /// true = token berhasil diperbarui, false = sesi berakhir.
  Future<bool> _refreshTokens() async {
    final refresh = await storage.readRefresh();
    if (refresh == null) {
      await _expire();
      return false;
    }

    // Klien terpisah tanpa interceptor supaya tidak terjadi perulangan.
    final plain = Dio(
      BaseOptions(
        baseUrl: dio.options.baseUrl,
        connectTimeout: dio.options.connectTimeout,
        receiveTimeout: dio.options.receiveTimeout,
      ),
    );

    try {
      final res = await plain.post(
        '/api/auth/refresh',
        data: {'refreshToken': refresh},
      );
      final data = res.data as Map<String, dynamic>;
      await storage.save(
        access: data['accessToken'] as String,
        refresh: data['refreshToken'] as String,
      );
      return true;
    } on DioException catch (e) {
      if (e.response == null) rethrow; // jaringan bermasalah
      await _expire();
      return false;
    }
  }

  Future<void> _expire() async {
    await storage.clear();
    onSessionExpired();
  }
}