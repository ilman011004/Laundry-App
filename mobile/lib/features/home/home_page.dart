import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/api_providers.dart';
import '../../core/labels.dart';
import '../auth/auth_controller.dart';

/// Halaman utama sementara. Menu kasir, pesanan, dan laporan menyusul.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  // Tombol uji sementara: memanggil API yang butuh token.
  // Jika token sudah kedaluwarsa, penyegaran otomatis terjadi di balik layar.
  Future<void> _checkSession(BuildContext context, WidgetRef ref) async {
    String message;
    try {
      final res = await ref.read(dioProvider).get('/api/auth/me');
      message = 'Sesi aktif sebagai ${res.data['user']['name']}';
    } catch (e) {
      message = errorMessage(e);
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry'),
        actions: [
          IconButton(
            tooltip: 'Keluar',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Halo, ${user?.name ?? '-'}',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text('Peran: ${labelOf(roleLabel, user?.role)}'),
              const SizedBox(height: 24),
              const Text(
                'Menu kasir, pesanan, dan laporan hadir di tahap berikutnya.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => _checkSession(context, ref),
                child: const Text('Tes sesi (sementara)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}