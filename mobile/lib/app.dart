import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/customers/customer_detail_page.dart';
import 'features/customers/customer_form_page.dart';
import 'features/customers/customers_list_page.dart';
import 'features/home/home_page.dart';
import 'features/orders/order_detail_page.dart';
import 'features/orders/orders_list_page.dart';
import 'features/pos/pos_page.dart';
import 'features/shell/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// Router yang otomatis memindahkan halaman sesuai status login.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(authControllerProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final location = state.matchedLocation;

      return switch (auth.status) {
        AuthStatus.unknown => location == '/splash' ? null : '/splash',
        AuthStatus.loggedOut => location == '/login' ? null : '/login',
        AuthStatus.loggedIn =>
          (location == '/login' || location == '/splash') ? '/' : null,
      };
    },
    routes: [
      GoRoute(path: '/splash', builder: (context, state) => const SplashPage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => MainShell(shell: shell),
        // Urutan cabang harus sama dengan urutan tab di main_shell.dart:
        // Beranda, Kasir, Pesanan, Pelanggan.
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (context, state) => const HomePage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/pos', builder: (context, state) => const PosPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/orders',
              builder: (context, state) => const OrdersListPage(),
              routes: [
                GoRoute(
                  path: ':id',
                  builder: (context, state) => OrderDetailPage(
                    orderId: int.parse(state.pathParameters['id']!),
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/customers',
              builder: (context, state) => const CustomersListPage(),
              routes: [
                // 'new' harus di atas ':id' supaya tidak dianggap sebagai id
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: _rootKey,
                  builder: (context, state) => const CustomerFormPage(),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) => CustomerDetailPage(
                    customerId: int.parse(state.pathParameters['id']!),
                  ),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: _rootKey,
                      builder: (context, state) => CustomerFormPage(
                        customerId: int.parse(state.pathParameters['id']!),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
});

class LaundryApp extends ConsumerWidget {
  const LaundryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Laundry',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: ref.watch(routerProvider),
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

/// Layar singkat saat aplikasi memeriksa sesi login yang tersimpan.
class SplashPage extends StatelessWidget {
  const SplashPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}