import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/api_providers.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
  });

  final int id;
  final String name;
  final String username;
  final String role; // 'OWNER' atau 'CASHIER'

  bool get isOwner => role == 'OWNER';

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as int,
        name: json['name'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
      );
}

enum AuthStatus { unknown, loggedOut, loggedIn }

class AuthState {
  const AuthState._(this.status, this.user);
  const AuthState.unknown() : this._(AuthStatus.unknown, null);
  const AuthState.loggedOut() : this._(AuthStatus.loggedOut, null);
  const AuthState.loggedIn(AuthUser user) : this._(AuthStatus.loggedIn, user);

  final AuthStatus status;
  final AuthUser? user;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    // Pulihkan sesi setelah build selesai (token tersimpan dari login sebelumnya).
    Future.microtask(_restore);
    return const AuthState.unknown();
  }

  Future<void> _restore() async {
    final storage = ref.read(tokenStorageProvider);
    final hasToken = await storage.readAccess() != null ||
        await storage.readRefresh() != null;

    if (!hasToken) {
      state = const AuthState.loggedOut();
      return;
    }

    try {
      final res = await ref.read(dioProvider).get('/api/auth/me');
      state = AuthState.loggedIn(
        AuthUser.fromJson(res.data['user'] as Map<String, dynamic>),
      );
    } catch (_) {
      // Jika 401, interceptor sudah membersihkan token dan mengakhiri sesi.
      state = const AuthState.loggedOut();
    }
  }

  /// Mengembalikan pesan error (bahasa Indonesia), atau null jika berhasil.
  Future<String?> login(String username, String password) async {
    try {
      final res = await ref.read(dioProvider).post(
        '/api/auth/login',
        data: {'username': username.trim(), 'password': password},
      );
      final data = res.data as Map<String, dynamic>;

      await ref.read(tokenStorageProvider).save(
            access: data['accessToken'] as String,
            refresh: data['refreshToken'] as String,
          );
      state = AuthState.loggedIn(
        AuthUser.fromJson(data['user'] as Map<String, dynamic>),
      );
      return null;
    } catch (e) {
      return errorMessage(e);
    }
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clear();
    state = const AuthState.loggedOut();
  }

  /// Dipanggil interceptor saat token tidak bisa diperbarui lagi.
  void sessionExpired() {
    state = const AuthState.loggedOut();
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthState>(AuthController.new);