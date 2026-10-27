import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/api_error.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/whatsapp.dart';
import '../orders/order_models.dart';
import '../settings/business_repository.dart';
import 'deliveries_repository.dart';
import 'delivery_models.dart';

/// Jenis pengantaran yang boleh dijadwalkan untuk cara penerimaan pesanan.
List<String> _allowedTypes(String? receiveMethod) => switch (receiveMethod) {
      'SELF_PICKUP' => const [],
      'DELIVERY' => const ['DROPOFF'],
      _ => const ['PICKUP', 'DROPOFF'],
    };

String _buildMessage(OrderDetail o, Delivery d, String businessName) {
  final b = StringBuffer();
  b.writeln('*$businessName*');
  b.writeln('Halo ${o.customerName}, berikut jadwal '
      '${d.type == 'PICKUP' ? 'penjemputan' : 'pengantaran'} cucian Anda.');
  b.writeln();
  b.writeln('No. order: ${o.orderNumber}');
  b.writeln('${deliveryTypeLabel[d.type]}: '
      '${d.scheduledAt == null ? 'jadwal menyusul' : formatDateTime(d.scheduledAt!)}');
  if (d.addressSnapshot != null && d.addressSnapshot!.isNotEmpty) {
    b.writeln('Alamat: ${d.addressSnapshot}');
  }
  if (d.notes != null && d.notes!.isNotEmpty) b.writeln('Catatan: ${d.notes}');
  if (d.type == 'DROPOFF' && o.remaining > 0) {
    b.writeln();
    b.writeln('Sisa pembayaran: ${formatRupiah(o.remaining)}');
  }
  b.writeln();
  b.writeln('Mohon pastikan ada yang menerima di lokasi. Terima kasih.');
  return b.toString().trim();
}

class DeliverySection extends ConsumerStatefulWidget {
  const DeliverySection({super.key, required this.order});

  final OrderDetail order;

  @override
  ConsumerState<DeliverySection> createState() => _DeliverySectionState();
}

class _DeliverySectionState extends ConsumerState<DeliverySection> {
  bool _busy = false;

  DeliveriesRepository get _repo => ref.read(deliveriesRepositoryProvider);

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _reload() => ref.invalidate(deliveriesProvider(widget.order.id));

  Future<void> _run(Future<void> Function() action, String okText) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        _reload();
        _snack(okText);
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _schedule(String type) async {
    final r = await showDialog<_FormResult>(
      context: context,
      builder: (_) => _DeliveryFormDialog(type: type),
    );
    if (r == null) return;
    await _run(
      () => _repo.create(
        orderId: widget.order.id,
        type: type,
        scheduledAt: r.scheduledAt,
        address: r.address,
        notes: r.notes,
      ),
      'Jadwal ${deliveryTypeLabel[type]!.toLowerCase()} tersimpan',
    );
  }

  Future<void> _edit(Delivery d) async {
    final r = await showDialog<_FormResult>(
      context: context,
      builder: (_) => _DeliveryFormDialog(type: d.type, existing: d),
    );
    if (r == null) return;
    await _run(
      () => _repo.update(d.id,
          scheduledAt: r.scheduledAt, address: r.address, notes: r.notes),
      'Jadwal diperbarui',
    );
  }

  Future<void> _status(Delivery d, String status) async {
    if (status == 'CANCELLED') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Batalkan jadwal?'),
          content: Text('Jadwal ${deliveryTypeLabel[d.type]!.toLowerCase()} ini akan dibatalkan.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Kembali')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Batalkan')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _run(
      () => _repo.setStatus(d.id, status),
      'Status menjadi ${deliveryStatusLabel[status]}',
    );
  }

  Future<void> _whatsApp(Delivery d) async {
    final biz = ref.read(businessProvider).asData?.value;
    final msg = _buildMessage(widget.order, d, biz?.name ?? 'Laundry');
    final ok = await openWhatsApp(widget.order.customerPhone, msg);
    if (!ok && mounted) {
      _snack('Tidak bisa membuka WhatsApp. Periksa nomor HP pelanggan.');
    }
  }

  Widget _card(Delivery d) {
    final theme = Theme.of(context);
    final active = d.isActive;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(d.type == 'PICKUP' ? Icons.upload_outlined : Icons.local_shipping_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${deliveryTypeLabel[d.type]} cucian',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(deliveryStatusLabel[d.status] ?? d.status),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              d.scheduledAt == null
                  ? 'Belum ada jadwal'
                  : 'Jadwal: ${formatDateTime(d.scheduledAt!)}',
            ),
            if (d.addressSnapshot != null && d.addressSnapshot!.isNotEmpty)
              Text('Alamat: ${d.addressSnapshot}'),
            if (d.notes != null && d.notes!.isNotEmpty) Text('Catatan: ${d.notes}'),
            if (active) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (d.status == 'SCHEDULED')
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _status(d, 'ON_THE_WAY'),
                      child: const Text('Berangkat'),
                    ),
                  if (d.status == 'ON_THE_WAY')
                    FilledButton.tonal(
                      onPressed: _busy ? null : () => _status(d, 'DONE'),
                      child: const Text('Selesai'),
                    ),
                  if (d.status != 'DONE')
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => _whatsApp(d),
                      icon: const Icon(Icons.send, size: 18),
                      label: const Text('WhatsApp'),
                    ),
                  if (d.status != 'DONE')
                    PopupMenuButton<String>(
                      enabled: !_busy,
                      onSelected: (v) {
                        if (v == 'edit') {
                          _edit(d);
                        } else {
                          _status(d, v);
                        }
                      },
                      itemBuilder: (_) => [
                        if (d.canEdit)
                          const PopupMenuItem(value: 'edit', child: Text('Ubah jadwal')),
                        if (d.status == 'SCHEDULED')
                          const PopupMenuItem(value: 'DONE', child: Text('Tandai selesai')),
                        const PopupMenuItem(value: 'CANCELLED', child: Text('Batalkan jadwal')),
                      ],
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    ref.watch(businessProvider); // dimuat lebih dulu untuk pesan WhatsApp
    final async = ref.watch(deliveriesProvider(o.id));

    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Jadwal pengantaran gagal dimuat. ${errorMessage(e)}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
            TextButton(onPressed: _reload, child: const Text('Coba lagi')),
          ],
        ),
      ),
      data: (list) {
        final canSchedule = !o.isCancelled && !o.isCompleted;
        final missing = canSchedule
            ? [
                for (final t in _allowedTypes(o.receiveMethod))
                  if (!list.any((d) => d.type == t && d.isActive)) t,
              ]
            : <String>[];

        if (list.isEmpty && missing.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Jemput dan antar', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              for (final d in list) _card(d),
              for (final t in missing)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _schedule(t),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text('Jadwalkan ${deliveryTypeLabel[t]!.toLowerCase()}'),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ======================= FORM =======================

typedef _FormResult = ({DateTime scheduledAt, String address, String notes});

class _DeliveryFormDialog extends StatefulWidget {
  const _DeliveryFormDialog({required this.type, this.existing});

  final String type;
  final Delivery? existing;

  @override
  State<_DeliveryFormDialog> createState() => _DeliveryFormDialogState();
}

class _DeliveryFormDialogState extends State<_DeliveryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _address =
      TextEditingController(text: widget.existing?.addressSnapshot ?? '');
  late final TextEditingController _notes =
      TextEditingController(text: widget.existing?.notes ?? '');
  DateTime? _date;
  TimeOfDay? _time;

  @override
  void initState() {
    super.initState();
    final at = widget.existing?.scheduledAt;
    if (at != null) {
      final b = toBusinessTime(at);
      _date = DateTime(b.year, b.month, b.day);
      _time = TimeOfDay(hour: b.hour, minute: b.minute);
    }
  }

  @override
  void dispose() {
    _address.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final nb = toBusinessTime(DateTime.now());
    final today = DateTime(nb.year, nb.month, nb.day);
    final initial = (_date != null && !_date!.isBefore(today)) ? _date! : today;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (t != null) setState(() => _time = t);
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final label = deliveryTypeLabel[widget.type]!.toLowerCase();

    return AlertDialog(
      title: Text(isEdit ? 'Ubah jadwal $label' : 'Jadwalkan $label'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickDate,
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: Text(
                        _date == null
                            ? 'Pilih tanggal'
                            : DateFormat('d MMM y', 'id_ID').format(_date!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickTime,
                      icon: const Icon(Icons.access_time, size: 18),
                      label: Text(
                        _time == null
                            ? 'Pilih jam'
                            : '${_two(_time!.hour)}.${_two(_time!.minute)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Alamat',
                  helperText: isEdit
                      ? null
                      : 'Kosongkan untuk memakai alamat utama pelanggan',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  final t = (v ?? '').trim();
                  if (t.isNotEmpty && t.length < 5) return 'Alamat minimal 5 karakter';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notes,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Catatan (opsional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: (_date == null || _time == null)
              ? null
              : () {
                  if (!_formKey.currentState!.validate()) return;
                  // Tanggal dan jam yang dipilih adalah waktu usaha, kirim sebagai UTC.
                  final utc = DateTime.utc(
                    _date!.year,
                    _date!.month,
                    _date!.day,
                    _time!.hour,
                    _time!.minute,
                  ).subtract(const Duration(hours: AppConfig.tzOffsetHours));
                  Navigator.pop(context, (
                    scheduledAt: utc,
                    address: _address.text.trim(),
                    notes: _notes.text.trim(),
                  ));
                },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}