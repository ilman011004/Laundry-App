import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../auth/auth_controller.dart';
import '../cash/cash_repository.dart';
import '../deliveries/deliveries_day_page.dart';
import '../deliveries/delivery_day_repository.dart';
import '../settings/business_repository.dart';
import 'dashboard_repository.dart';
import '../orders/orders_preset.dart';

String _lateText(DateTime? est) {
  if (est == null) return '';
  final m = DateTime.now().toUtc().difference(est.toUtc()).inMinutes;
  if (m < 60) return 'telat ${m < 1 ? 1 : m} menit';
  if (m < 48 * 60) return 'telat ${m ~/ 60} jam';
  return 'telat ${m ~/ (24 * 60)} hari';
}

/// Tanggal usaha hari ini, format "YYYY-MM-DD".
String _todayKey() =>
    DateFormat('yyyy-MM-dd').format(toBusinessTime(DateTime.now()));

/// Buka tab Pesanan dengan filter yang sesuai kartu yang diketuk.
void _openOrders(BuildContext context, WidgetRef ref, String view) {
  ref.read(ordersPresetProvider.notifier).open(view);
  context.go('/orders');
}

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final async = ref.watch(dashboardProvider);
    final bizName =
        ref.watch(businessProvider).asData?.value.name ?? 'Laundry';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              bizName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              '${user?.name ?? '-'} • ${labelOf(roleLabel, user?.role)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pengaturan',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(errorMessage(e), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(dashboardProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(businessProvider);
            ref.invalidate(deliveriesByDayProvider(_todayKey()));
            ref.invalidate(dashboardProvider);
            await ref.read(dashboardProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _CashHero(
                cash: d.cash,
                money: d.money,
                onOpen: () => context.push('/cash'),
              ),
              if (d.overdue > 0) ...[
                const SizedBox(height: 16),
                _OverdueCard(d: d),
              ],
              const SizedBox(height: 20),
              const _DeliveryCard(),
              const SizedBox(height: 20),

              _Section('Ringkasan pesanan'),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Sedang diproses',
                      value: '${d.inProgress}',
                      icon: Icons.local_laundry_service,
                      color: Colors.blue,
                      onTap: () =>
                          _openOrders(context, ref, 'inProgress'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      label: 'Siap diambil',
                      value: '${d.ready}',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.green,
                      onTap: () => _openOrders(context, ref, 'ready'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      label: 'Selesai hari ini',
                      value: '${d.completedToday}',
                      icon: Icons.check_circle_outline,
                      color: Colors.blueGrey,
                      onTap: () =>
                          _openOrders(context, ref, 'completedToday'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              _Section('Pembayaran'),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Pesanan belum lunas',
                      value: '${d.unpaidCount}',
                      icon: Icons.hourglass_bottom,
                      color: Colors.orange,
                      onTap: () => _openOrders(context, ref, 'unpaid'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _Stat(
                      label: 'Tagihan yang belum dibayar',
                      value: formatRupiah(d.outstanding),
                      icon: Icons.receipt_long,
                      color: Colors.red,
                      onTap: () => _openOrders(context, ref, 'unpaid'),
                    ),
                  ),
                ],
              ),

              if (d.topDebts.isNotEmpty) ...[
                const SizedBox(height: 10),
                Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'Tagihan terbesar',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      for (final t in d.topDebts)
                        ListTile(
                          dense: true,
                          title: Text(t.customerName),
                          subtitle: Text(t.orderNumber),
                          trailing: Text(
                            formatRupiah(t.remaining),
                            style: TextStyle(
                              color: theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onTap: () =>
                              context.push('/orders/${t.id}'),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _Section('Hari ini'),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Pesanan masuk',
                      value: '${d.ordersToday}',
                      icon: Icons.add_shopping_cart,
                      color: Colors.teal,
                    ),
                  ),
                  if (d.money != null) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        label: 'Uang masuk',
                        value: formatRupiah(d.money!.incomeToday),
                        icon: Icons.trending_up,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ],
              ),
              if (d.money != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _Stat(
                        label: 'Masuk bulan ini',
                        value: formatRupiah(d.money!.incomeMonth),
                        icon: Icons.calendar_month,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _Stat(
                        label: 'Pengeluaran bulan ini',
                        value: formatRupiah(d.money!.expensesMonth),
                        icon: Icons.trending_down,
                        color: Colors.brown,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

/// Kartu pintu masuk ke layar Jadwal antar-jemput, dengan jumlah tugas hari ini.
class _DeliveryCard extends ConsumerWidget {
  const _DeliveryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveriesByDayProvider(_todayKey()));

    final subtitle = async.when(
      loading: () => 'Memuat jadwal...',
      error: (_, _) => 'Ketuk untuk melihat jadwal',
      data: (list) {
        final active =
            list.where((t) => t.delivery.status != 'CANCELLED').toList();
        if (active.isEmpty) return 'Tidak ada jadwal hari ini';
        final pending =
            active.where((t) => t.delivery.status != 'DONE').length;
        return pending == 0
            ? 'Semua ${active.length} tugas hari ini selesai'
            : '$pending dari ${active.length} tugas belum selesai';
      },
    );

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: const CircleAvatar(
          child: Icon(Icons.local_shipping_outlined),
        ),
        title: const Text(
          'Jadwal antar-jemput',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const DeliveriesDayPage(),
          ),
        ),
      ),
    );
  }
}

class _CashHero extends StatelessWidget {
  const _CashHero({
    required this.cash,
    required this.money,
    required this.onOpen,
  });

  final CashSummary cash;
  final Money? money;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = cs.onPrimary;

    Widget line(String label, int value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: text.withValues(alpha: 0.85),
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                formatRupiah(value),
                style: TextStyle(
                  color: text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );

    final isOwner = cash.isOwner;
    final amount = isOwner ? cash.total : cash.held;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            cs.primary,
            Color.lerp(cs.primary, Colors.black, 0.4)!,
          ],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_outlined,
                      color: text,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isOwner
                            ? 'Total kas usaha (tunai)'
                            : 'Kas saya (tunai)',
                        style: TextStyle(
                          color: text.withValues(alpha: 0.9),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: text,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  formatRupiah(amount),
                  style: TextStyle(
                    color: text,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (isOwner) ...[
                  line('Di pemilik', cash.ownerCash),
                  line('Di tangan kasir', cash.cashierHeldTotal),
                  line(
                    'Setoran belum diterima (${cash.pendingCount})',
                    cash.pendingTotal,
                  ),
                  if (money != null) ...[
                    Divider(
                      color: text.withValues(alpha: 0.3),
                    ),
                    line('Transfer (di luar kas)', money!.transfer),
                    line('QRIS (di luar kas)', money!.qris),
                  ],
                ] else ...[
                  if (cash.pendingDeposits > 0)
                    line(
                      'Setoran menunggu pemilik',
                      cash.pendingDeposits,
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: onOpen,
                      icon: const Icon(Icons.savings_outlined),
                      label: const Text('Setor ke pemilik'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  const _OverdueCard({required this.d});

  final Dashboard d;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      color: cs.errorContainer,
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              Icons.warning_amber_rounded,
              color: cs.onErrorContainer,
            ),
            title: Text(
              '${d.overdue} pesanan melewati estimasi selesai',
              style: TextStyle(
                color: cs.onErrorContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Segera diselesaikan',
              style: TextStyle(
                color: cs.onErrorContainer,
              ),
            ),
          ),
          for (final o in d.overdueList)
            ListTile(
              dense: true,
              title: Text(
                o.customerName,
                style: TextStyle(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${o.orderNumber} • ${labelOf(workStatusLabel, o.workStatus)}',
                style: TextStyle(
                  color: cs.onErrorContainer,
                ),
              ),
              trailing: Text(
                _lateText(o.estimatedDoneAt),
                style: TextStyle(
                  color: cs.error,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              onTap: () => context.push('/orders/${o.id}'),
            ),
          if (d.overdue > d.overdueList.length)
            TextButton(
              onPressed: () => context.go('/orders'),
              child: Text(
                'Lihat ${d.overdue - d.overdueList.length} lainnya',
              ),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(
                  icon,
                  color: color,
                  size: 18,
                ),
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}