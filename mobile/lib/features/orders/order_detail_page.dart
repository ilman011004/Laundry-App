import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import '../auth/auth_controller.dart';
import '../pos/pos_models.dart' show formatQty;
import 'order_models.dart';
import 'orders_repository.dart';
import '../deliveries/delivery_section.dart';

const _flow = ['RECEIVED', 'WASHING', 'DRYING', 'IRONING', 'READY', 'COMPLETED'];

/// Status tujuan yang valid: hanya maju, dan "Selesai" hanya dari "Siap".
List<String> _nextStatuses(String current) {
  final i = _flow.indexOf(current);
  if (i < 0) return const [];
  return [
    for (final s in _flow.skip(i + 1))
      if (s != 'COMPLETED' || current == 'READY') s,
  ];
}

class OrderDetailPage extends ConsumerStatefulWidget {
  const OrderDetailPage({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends ConsumerState<OrderDetailPage> {
  bool _changed = false;
  bool _busy = false;

  OrdersRepository get _repo => ref.read(ordersRepositoryProvider);

  void _refresh() => ref.invalidate(orderDetailProvider(widget.orderId));

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<String?> Function() action, String successText) async {
    if (_busy) return;
    setState(() => _busy = true);

    // Disimpan sebelum await agar aman walau halaman sudah ditutup.
    final revision = ref.read(ordersRevisionProvider.notifier);

    try {
      final warning = await action();
      _changed = true;
      revision.bump(); // Beranda (kas dan ringkasan) ikut dimuat ulang
      if (mounted) {
        _refresh();
        _snack(warning ?? successText);
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _pay(OrderDetail o) async {
    final r = await showDialog<({int amount, String method, String note})>(
      context: context,
      builder: (_) => _PaymentDialog(remaining: o.remaining),
    );
    if (r == null) return;
    await _run(() async {
      await _repo.pay(o.id, amount: r.amount, method: r.method, note: r.note);
      return null;
    }, 'Pembayaran ${formatRupiah(r.amount)} tercatat');
  }

  Future<void> _changeStatus(OrderDetail o) async {
    final r = await showDialog<({String status, String note})>(
      context: context,
      builder: (_) => _StatusDialog(options: _nextStatuses(o.workStatus), remaining: o.remaining),
    );
    if (r == null) return;
    await _run(
      () => _repo.updateStatus(o.id, status: r.status, note: r.note),
      'Status diubah menjadi ${labelOf(workStatusLabel, r.status)}',
    );
  }

  Future<void> _cancel(OrderDetail o) async {
    final note = await showDialog<String>(
      context: context,
      builder: (_) => const _CancelDialog(),
    );
    if (note == null) return;
    await _run(() async {
      await _repo.cancel(o.id, note: note);
      return null;
    }, 'Pesanan dibatalkan');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(orderDetailProvider(widget.orderId));
    final isOwner = ref.watch(authControllerProvider).user?.isOwner ?? false;
    final order = async.asData?.value;

    final canCancel = isOwner &&
        order != null &&
        !order.isCancelled &&
        !order.isCompleted &&
        order.paidAmount == 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(order?.orderNumber ?? 'Detail Pesanan'),
          actions: [
            if (canCancel)
              PopupMenuButton<String>(
                onSelected: (_) => _cancel(order),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'cancel', child: Text('Batalkan pesanan')),
                ],
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
                  OutlinedButton(onPressed: _refresh, child: const Text('Coba lagi')),
                ],
              ),
            ),
          ),
          data: _buildContent,
        ),
        bottomNavigationBar: order == null ? null : _buildActions(order),
      ),
    );
  }

  Widget? _buildActions(OrderDetail o) {
    final canPay = !o.isCancelled && o.remaining > 0;
    final canStatus = !o.isCancelled && !o.isCompleted;
    if (!canPay && !canStatus) return null;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            if (canStatus)
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _changeStatus(o),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Ubah status'),
                  ),
                ),
              ),
            if (canStatus && canPay) const SizedBox(width: 12),
            if (canPay)
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _pay(o),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Bayar'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false, Color? color}) {
    final base = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    final style = color == null ? base : base?.copyWith(color: color);
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

  Widget _buildContent(OrderDetail o) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref.read(orderDetailProvider(widget.orderId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // --- Ringkasan ---
          Text(o.customerName, style: theme.textTheme.headlineSmall),
          Text(o.customerPhone),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(labelOf(workStatusLabel, o.workStatus))),
              Chip(label: Text(labelOf(paymentStatusLabel, o.paymentStatus))),
            ],
          ),
          const SizedBox(height: 8),
          Text('Masuk: ${formatDateTime(o.receivedAt)}'),
          if (o.estimatedDoneAt != null && !o.isCancelled)
            Text('Estimasi selesai: ${formatDateTime(o.estimatedDoneAt!)}'),
          if (o.completedAt != null) Text('Diserahkan: ${formatDateTime(o.completedAt!)}'),
          if (o.notes != null && o.notes!.isNotEmpty) Text('Catatan: ${o.notes}'),
          const SizedBox(height: 16),

          // --- Rincian ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Rincian', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final it in o.items) ...[
                    _row(
                      '${it.serviceName} × ${formatQty(it.quantity)} ${it.unit}',
                      formatRupiah(it.lineTotal - it.addonsTotal),
                    ),
                    for (final a in it.addons) _row('   + ${a.name}', formatRupiah(a.amount)),
                    if (it.notes != null && it.notes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 12, bottom: 4),
                        child: Text('Catatan: ${it.notes}', style: theme.textTheme.bodySmall),
                      ),
                  ],
                  const Divider(),
                  _row('Kecepatan${o.speedName == null ? '' : ' (${o.speedName})'}',
                      formatRupiah(o.speedFee)),
                  _row('Penerimaan${o.fulfillmentName == null ? '' : ' (${o.fulfillmentName})'}',
                      formatRupiah(o.deliveryFee)),
                  if (o.discount > 0) _row('Diskon', '-${formatRupiah(o.discount)}'),
                  const Divider(),
                  _row('Total', formatRupiah(o.total), bold: true),
                  _row('Sudah dibayar', formatRupiah(o.paidAmount)),
                  if (!o.isCancelled)
                    _row('Sisa tagihan', formatRupiah(o.remaining),
                        bold: true,
                        color: o.remaining > 0 ? theme.colorScheme.error : null),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          DeliverySection(order: o),

          // --- Pembayaran ---
          Text('Riwayat pembayaran', style: theme.textTheme.titleMedium),
          if (o.payments.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada pembayaran.'),
            ),
          for (final p in o.payments)
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: Text('${formatRupiah(p.amount)} • ${labelOf(paymentMethodLabel, p.method)}'),
                subtitle: Text(
                  '${formatDateTime(p.paidAt)}'
                  '${p.note == null || p.note!.isEmpty ? '' : '\n${p.note}'}',
                ),
                isThreeLine: p.note != null && p.note!.isNotEmpty,
              ),
            ),
          const SizedBox(height: 16),

          // --- Riwayat status ---
          Text('Riwayat status', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          for (final h in o.history.reversed)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.history, size: 20),
              title: Text(labelOf(workStatusLabel, h.toStatus)),
              subtitle: Text(
                '${formatDateTime(h.createdAt)}'
                '${h.changedBy == null ? '' : ' • ${h.changedBy}'}'
                '${h.note == null || h.note!.isEmpty ? '' : '\n${h.note}'}',
              ),
            ),
        ],
      ),
    );
  }
}

// ======================= DIALOG =======================

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.remaining});

  final int remaining;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount =
      TextEditingController(text: widget.remaining.toString());
  final _note = TextEditingController();
  String _method = 'CASH';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Catat pembayaran'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Sisa tagihan: ${formatRupiah(widget.remaining)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Nominal',
                  prefixText: 'Rp ',
                  suffixIcon: TextButton(
                    onPressed: () => _amount.text = widget.remaining.toString(),
                    child: const Text('Lunasi'),
                  ),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Nominal harus lebih dari 0';
                  if (n > widget.remaining) return 'Melebihi sisa tagihan';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final e in paymentMethodLabel.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _method == e.key,
                      onSelected: (_) => setState(() => _method = e.key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (
              amount: int.parse(_amount.text),
              method: _method,
              note: _note.text,
            ));
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _StatusDialog extends StatefulWidget {
  const _StatusDialog({required this.options, required this.remaining});

  final List<String> options;
  final int remaining;

  @override
  State<_StatusDialog> createState() => _StatusDialogState();
}

class _StatusDialogState extends State<_StatusDialog> {
  late String _selected = widget.options.first;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ubah status'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: _selected,
              onChanged: (v) => setState(() => _selected = v ?? _selected),
              child: Column(
                children: [
                  for (final s in widget.options)
                    RadioListTile<String>(
                      value: s,
                      contentPadding: EdgeInsets.zero,
                      title: Text(labelOf(workStatusLabel, s)),
                    ),
                ],
              ),
            ),
            if (_selected == 'COMPLETED' && widget.remaining > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Perhatian: masih ada sisa tagihan ${formatRupiah(widget.remaining)}.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(context, (status: _selected, note: _note.text)),
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Batalkan pesanan?'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _note,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Alasan pembatalan'),
          validator: (v) =>
              (v == null || v.trim().length < 3) ? 'Alasan minimal 3 karakter' : null,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Kembali')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, _note.text.trim());
          },
          child: const Text('Batalkan'),
        ),
      ],
    );
  }
}