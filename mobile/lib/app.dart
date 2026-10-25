import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/api_providers.dart';
import 'core/theme.dart';

final _router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (context, state) => const ConnectionCheckPage()),
  ],
);

class LaundryApp extends StatelessWidget {
  const LaundryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Laundry',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
      locale: const Locale('id', 'ID'),
      supportedLocales: const [Locale('id', 'ID')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}

/// Halaman sementara untuk memastikan aplikasi bisa menghubungi backend.
/// Akan diganti oleh layar login di tahap berikutnya.
class ConnectionCheckPage extends ConsumerWidget {
  const ConnectionCheckPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final health = ref.watch(healthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Laundry')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              health.when(
                loading: () => const CircularProgressIndicator(),
                error: (e, _) => Text('Terjadi kesalahan: $e'),
                data: (message) => Text(message, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => ref.invalidate(healthProvider),
                child: const Text('Cek ulang'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}