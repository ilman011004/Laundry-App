import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../orders/orders_preset.dart';
import '../settings/business_repository.dart';
import 'dashboard_repository.dart';

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
    final bizName = ref.watch(businessProvider).asData?.value.name ?? 'Laundry';

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
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
            edgeOffset: MediaQuery.of(context).padding.top,
            onRefresh: () async {
              ref.invalidate(businessProvider);
              ref.invalidate(deliveriesByDayProvider(_todayKey()));
              ref.invalidate(dashboardProvider);
              await ref.read(dashboardProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              children: [
                _Header(
                  bizName: bizName,
                  userName: user?.name ?? '-',
                  cash: d.cash,
                  money: d.money,
                  onOpenCash: () => context.push('/cash'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (d.overdue > 0) ...[
                        const SizedBox(height: 8),
                        _OverdueCard(d: d),
                      ],

                      const _Section('Ringkasan pesanan'),
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _StackTile(
                                label: 'Sedang diproses',
                                value: '${d.inProgress}',
                                icon: Icons.local_laundry_service_outlined,
                                color: Colors.blue,
                                onTap: () =>
                                    _openOrders(context, ref, 'inProgress'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StackTile(
                                label: 'Siap diambil',
                                value: '${d.ready}',
                                icon: Icons.inventory_2_outlined,
                                color: Colors.green,
                                onTap: () => _openOrders(context, ref, 'ready'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _StackTile(
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
                      ),

                      const SizedBox(height: 12),
                      const _DeliveryCard(),

                      const _Section('Pembayaran'),
                      _Grid(children: [
                        _Tile(
                          label: 'Pesanan belum lunas',
                          value: '${d.unpaidCount}',
                          icon: Icons.hourglass_bottom,
                          color: Colors.orange.shade800,
                          onTap: () => _openOrders(context, ref, 'unpaid'),
                        ),
                        _Tile(
                          label: 'Tagihan belum dibayar',
                          value: formatRupiah(d.outstanding),
                          icon: Icons.receipt_long_outlined,
                          color: Colors.red.shade700,
                          onTap: () => _openOrders(context, ref, 'unpaid'),
                        ),
                      ]),

                      const _Section('Hari ini'),
                      _Grid(children: [
                        _Tile(
                          label: 'Pesanan masuk',
                          value: '${d.ordersToday}',
                          icon: Icons.add_shopping_cart,
                          color: Colors.teal,
                        ),
                        if (d.money != null)
                          _Tile(
                            label: 'Uang masuk',
                            value: formatRupiah(d.money!.incomeToday),
                            icon: Icons.trending_up,
                            color: Colors.green.shade700,
                          ),
                        if (d.money != null)
                          _Tile(
                            label: 'Masuk bulan ini',
                            value: formatRupiah(d.money!.incomeMonth),
                            icon: Icons.calendar_month_outlined,
                            color: Colors.indigo,
                          ),
                        if (d.money != null)
                          _Tile(
                            label: 'Pengeluaran bulan ini',
                            value: formatRupiah(d.money!.expensesMonth),
                            icon: Icons.trending_down,
                            color: Colors.brown,
                          ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================ Header

class _Header extends StatelessWidget {
  const _Header({
    required this.bizName,
    required this.userName,
    required this.cash,
    required this.money,
    required this.onOpenCash,
  });

  final String bizName;
  final String userName;
  final CashSummary cash;
  final Money? money;
  final VoidCallback onOpenCash;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final on = cs.onPrimary;
    final top = MediaQuery.of(context).padding.top;
    final isOwner = cash.isOwner;
    final amount = isOwner ? cash.total : cash.held;
    final today = DateFormat('EEEE, d MMMM y', 'id_ID')
        .format(toBusinessTime(DateTime.now()));

    Widget line(String label, int value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 13)),
              ),
              Text(formatRupiah(value),
                  style: TextStyle(color: on, fontSize: 13, fontWeight: FontWeight.w600)),
            ],
          ),
        );

    return Container(
      padding: EdgeInsets.fromLTRB(20, top + 14, 20, 20),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.4)!],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            bizName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: on, fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            'Halo, $userName  •  $today',
            style: TextStyle(color: on.withValues(alpha: 0.8), fontSize: 13),
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onOpenCash,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: on.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          isOwner ? 'Total kas usaha (tunai)' : 'Kas saya (tunai)',
                          style: TextStyle(color: on.withValues(alpha: 0.9)),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: on, size: 20),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatRupiah(amount),
                    style: TextStyle(color: on, fontSize: 28, fontWeight: FontWeight.w800),
                  ),
                  if (isOwner) ...[
                    const SizedBox(height: 8),
                    line('Di pemilik', cash.ownerCash),
                    line('Di tangan kasir', cash.cashierHeldTotal),
                    line('Setoran belum diterima (${cash.pendingCount})',
                        cash.pendingTotal),
                    if (money != null) ...[
                      Divider(color: on.withValues(alpha: 0.3)),
                      line('Transfer (di luar kas)', money!.transfer),
                      line('QRIS (di luar kas)', money!.qris),
                    ],
                  ] else ...[
                    if (cash.pendingDeposits > 0) ...[
                      const SizedBox(height: 8),
                      line('Setoran menunggu pemilik', cash.pendingDeposits),
                    ],
                    const SizedBox(height: 10),
                    FilledButton.tonalIcon(
                      onPressed: onOpenCash,
                      icon: const Icon(Icons.savings_outlined),
                      label: const Text('Setor ke pemilik'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================ Bagian umum

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(
          text,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      );
}

/// Kisi dua kolom. Jumlah kartu ganjil tetap rapi.
class _Grid extends StatelessWidget {
  const _Grid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final second = i + 1 < children.length ? children[i + 1] : const SizedBox();
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: children[i]),
              const SizedBox(width: 10),
              Expanded(child: second),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
  }
}

/// Kartu lebar: ikon di kiri, angka dan label di kanan.
class _Tile extends StatelessWidget {
  const _Tile({
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
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    Text(
                      label,
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Kartu sempit untuk tiga kartu berjajar: ikon di atas, angka dan label di bawah.
class _StackTile extends StatelessWidget {
  const _StackTile({
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
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));

    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(height: 10),
              Text(
                value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pintu masuk ke layar Jadwal antar-jemput.
class _DeliveryCard extends ConsumerWidget {
  const _DeliveryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deliveriesByDayProvider(_todayKey()));
    final theme = Theme.of(context);

    final subtitle = async.when(
      loading: () => 'Memuat jadwal...',
      error: (_, _) => 'Ketuk untuk melihat jadwal',
      data: (list) {
        final active = list.where((t) => t.delivery.status != 'CANCELLED').toList();
        if (active.isEmpty) return 'Tidak ada jadwal hari ini';
        final pending = active.where((t) => t.delivery.status != 'DONE').length;
        return pending == 0
            ? 'Semua ${active.length} tugas hari ini selesai'
            : '$pending dari ${active.length} tugas belum selesai';
      },
    );

    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    return Material(
      color: theme.colorScheme.surface,
      elevation: 1,
      shadowColor: Colors.black26,
      shape: shape,
      child: ListTile(
        shape: shape,
        leading: CircleAvatar(
          backgroundColor: Colors.deepPurple.withValues(alpha: 0.14),
          child: const Icon(Icons.local_shipping_outlined, color: Colors.deepPurple),
        ),
        title: const Text('Jadwal antar-jemput',
            style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const DeliveriesDayPage()),
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
      margin: EdgeInsets.zero,
      color: cs.errorContainer,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer),
            title: Text(
              '${d.overdue} pesanan melewati estimasi selesai',
              style: TextStyle(color: cs.onErrorContainer, fontWeight: FontWeight.w700),
            ),
            subtitle: Text('Segera diselesaikan',
                style: TextStyle(color: cs.onErrorContainer)),
          ),
          for (final o in d.overdueList)
            ListTile(
              dense: true,
              title: Text(o.customerName,
                  style: TextStyle(
                      color: cs.onErrorContainer, fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${o.orderNumber} • ${labelOf(workStatusLabel, o.workStatus)}',
                style: TextStyle(color: cs.onErrorContainer),
              ),
              trailing: Text(
                _lateText(o.estimatedDoneAt),
                style: TextStyle(
                    color: cs.error, fontWeight: FontWeight.w700, fontSize: 12),
              ),
              onTap: () => context.push('/orders/${o.id}'),
            ),
          if (d.overdue > d.overdueList.length)
            TextButton(
              onPressed: () => context.go('/orders'),
              child: Text('Lihat ${d.overdue - d.overdueList.length} lainnya'),
            ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}