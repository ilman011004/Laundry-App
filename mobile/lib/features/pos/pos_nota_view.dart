import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/whatsapp.dart';
import '../orders/nota_message.dart';
import '../orders/order_models.dart';
import '../orders/orders_repository.dart';
import '../settings/business_repository.dart';
import 'pos_controller.dart';
import 'pos_models.dart' show formatQty;

/// Layar nota setelah pesanan berhasil disimpan.
class PosNotaView extends ConsumerWidget {
  const PosNotaView({super.key, required this.order, required this.onNewOrder});

  final CreatedOrder order;
  final Future<void> Function() onNewOrder;

  Future<void> _sendWhatsApp(BuildContext context, OrderDetail o, Business? biz) async {
    final message = buildNotaMessage(
      o,
      businessName: biz?.name ?? 'Laundry',
      phone: biz?.phone ?? '',
      address: biz?.address ?? '',
    );
    final ok = await openWhatsApp(o.customerPhone, message);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak bisa membuka WhatsApp. Periksa nomor HP pelanggan.'),
        ),
      );
    }
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(orderDetailProvider(order.id));
    final biz = ref.watch(businessProvider).asData?.value;
    final theme = Theme.of(context);
    final o = detail.asData?.value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nota pesanan'),
        automaticallyImplyLeading: false,
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pesanan ${order.orderNumber} sudah tersimpan, tetapi rincian nota '
                  'gagal dimuat.\n${errorMessage(e)}',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(orderDetailProvider(order.id)),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Icon(Icons.check_circle, color: Colors.green, size: 64),
            const SizedBox(height: 8),
            Text(
              'Pesanan berhasil disimpan',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            Text(
              d.orderNumber,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biz?.name ?? 'Laundry',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Divider(),
                    _row('Pelanggan', d.customerName),
                    _row('Masuk', formatDateTime(d.receivedAt)),
                    if (d.estimatedDoneAt != null)
                      _row('Estimasi selesai', formatDateTime(d.estimatedDoneAt!)),
                    const Divider(),
                    for (final it in d.items) ...[
                      _row(
                        '${it.serviceName} × ${formatQty(it.quantity)} ${it.unit}',
                        formatRupiah(it.lineTotal - it.addonsTotal),
                      ),
                      for (final a in it.addons)
                        _row('   + ${a.name}', formatRupiah(a.amount)),
                    ],
                    if (d.speedFee > 0)
                      _row(
                        'Kecepatan${d.speedName == null ? '' : ' (${d.speedName})'}',
                        formatRupiah(d.speedFee),
                      ),
                    if (d.deliveryFee > 0)
                      _row(d.fulfillmentName ?? 'Antar/jemput', formatRupiah(d.deliveryFee)),
                    if (d.discount > 0) _row('Diskon', '-${formatRupiah(d.discount)}'),
                    const Divider(),
                    _row('Total', formatRupiah(d.total), bold: true),
                    _row('Dibayar', formatRupiah(d.paidAmount)),
                    _row(
                      'Sisa tagihan',
                      formatRupiah(d.remaining),
                      bold: d.remaining > 0,
                      color: d.remaining > 0 ? theme.colorScheme.error : Colors.green,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: o == null ? null : () => _sendWhatsApp(context, o, biz),
                  icon: const Icon(Icons.send),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Kirim nota ke WhatsApp pelanggan'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/orders/${order.id}'),
                      child: const Text('Lihat detail'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: onNewOrder,
                      child: const Text('Pesanan baru'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}