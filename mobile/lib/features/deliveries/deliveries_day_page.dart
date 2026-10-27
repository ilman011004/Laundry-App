import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/whatsapp.dart';
import '../settings/business_repository.dart';
import 'deliveries_repository.dart';
import 'delivery_day_repository.dart';
import 'delivery_models.dart';

String _dayKey(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

DateTime _businessToday() {
  final b = toBusinessTime(DateTime.now());
  return DateTime(b.year, b.month, b.day);
}

String _buildMessage(DeliveryTask t, String businessName) {
  final d = t.delivery;
  final b = StringBuffer();
  b.writeln('*$businessName*');
  b.writeln('Halo ${t.customerName}, kami mengingatkan jadwal '
      '${d.type == 'PICKUP' ? 'penjemputan' : 'pengantaran'} cucian Anda '
      '(No. order ${t.orderNumber}).');
  if (d.scheduledAt != null) b.writeln('Jadwal: ${formatDateTime(d.scheduledAt!)}');
  if (d.addressSnapshot != null && d.addressSnapshot!.isNotEmpty) {
    b.writeln('Alamat: ${d.addressSnapshot}');
  }
  b.writeln();
  b.writeln('Mohon pastikan ada yang menerima di lokasi. Terima kasih.');
  return b.toString().trim();
}

class DeliveriesDayPage extends ConsumerStatefulWidget {
  const DeliveriesDayPage({super.key});

  @override
  ConsumerState<DeliveriesDayPage> createState() => _DeliveriesDayPageState();
}

class _DeliveriesDayPageState extends ConsumerState<DeliveriesDayPage> {
  late DateTime _day = _businessToday();
  bool _busy = false;

  String get _key => _dayKey(_day);

  void _reload() => ref.invalidate(deliveriesByDayProvider(_key));

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _shift(int days) => setState(() => _day = _day.add(Duration(days: days)));

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _day = DateTime(d.year, d.month, d.day));
  }

  Future<void> _setStatus(DeliveryTask t, String status) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(deliveriesRepositoryProvider).setStatus(t.delivery.id, status);
      ref.invalidate(deliveriesProvider(t.delivery.orderId));
      if (mounted) {
        _reload();
        _snack('Status menjadi ${deliveryStatusLabel[status]}');
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _whatsApp(DeliveryTask t) async {
    final biz = ref.read(businessProvider).asData?.value;
    final ok = await openWhatsApp(t.customerPhone, _buildMessage(t, biz?.name ?? 'Laundry'));
    if (!ok && mounted) {
      _snack('Tidak bisa membuka WhatsApp. Periksa nomor HP pelanggan.');
    }
  }

  Widget _card(DeliveryTask t) {
    final theme = Theme.of(context);
    final d = t.delivery;
    final time = d.scheduledAt == null
        ? '--.--'
        : DateFormat('HH.mm').format(toBusinessTime(d.scheduledAt!));

    return Card(
      child: InkWell(
        onTap: () => context.push('/orders/${d.orderId}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(time, style: theme.textTheme.titleLarge),
                  const SizedBox(width: 12),
                  Icon(d.type == 'PICKUP'
                      ? Icons.upload_outlined
                      : Icons.local_shipping_outlined),
                  const SizedBox(width: 4),
                  Text(deliveryTypeLabel[d.type] ?? d.type),
                  const Spacer(),
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(deliveryStatusLabel[d.status] ?? d.status),
                  ),
                ],
              ),
              Text(t.customerName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text('${t.orderNumber} • ${t.customerPhone}',
                  style: theme.textTheme.bodySmall),
              if (d.addressSnapshot != null && d.addressSnapshot!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Alamat: ${d.addressSnapshot}'),
                ),
              if (d.notes != null && d.notes!.isNotEmpty)
                Text('Catatan: ${d.notes}'),
              if (d.status == 'SCHEDULED' || d.status == 'ON_THE_WAY') ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (d.status == 'SCHEDULED')
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _setStatus(t, 'ON_THE_WAY'),
                        child: const Text('Berangkat'),
                      ),
                    if (d.status == 'ON_THE_WAY')
                      FilledButton.tonal(
                        onPressed: _busy ? null : () => _setStatus(t, 'DONE'),
                        child: const Text('Selesai'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _whatsApp(t),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('WhatsApp'),
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(deliveriesByDayProvider(_key));
    ref.watch(businessProvider); // dimuat lebih dulu untuk pesan WhatsApp
    final isToday = _key == _dayKey(_businessToday());

    return Scaffold(
      appBar: AppBar(title: const Text('Jadwal antar-jemput')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Hari sebelumnya',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: _pickDay,
                    child: Text(
                      '${isToday ? 'Hari ini • ' : ''}'
                      '${DateFormat('EEEE, d MMM y', 'id_ID').format(_day)}',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hari berikutnya',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _shift(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(errorMessage(e), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      OutlinedButton(onPressed: _reload, child: const Text('Coba lagi')),
                    ],
                  ),
                ),
              ),
              data: (all) {
                final tasks = all.where((t) => t.delivery.status != 'CANCELLED').toList();
                final pickups = tasks.where((t) => t.delivery.type == 'PICKUP').length;
                final dropoffs = tasks.length - pickups;
                final done = tasks.where((t) => t.delivery.status == 'DONE').length;

                return RefreshIndicator(
                  onRefresh: () async {
                    _reload();
                    await ref.read(deliveriesByDayProvider(_key).future);
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (tasks.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child: Center(child: Text('Tidak ada jadwal pada hari ini.')),
                        )
                      else ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '$pickups jemput • $dropoffs antar • $done selesai',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        for (final t in tasks) _card(t),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}