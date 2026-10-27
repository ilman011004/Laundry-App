import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import 'customer_picker.dart';
import 'pos_controller.dart';
import 'pos_models.dart';

// ============================================================ Bagian umum

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.hint});

  final String text;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (hint != null) Text(hint!, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant,
        width: selected ? 2 : 1,
      ),
    );

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: shape,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? cs.primary : cs.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
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

/// Rincian harga dari backend (dipakai di langkah 2 dan 4).
class PriceSummary extends StatelessWidget {
  const PriceSummary({super.key, required this.state});

  final PosState state;

  Widget _row(BuildContext context, String label, String value, {bool bold = false}) {
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = state.preview;

    Widget content;
    if (state.previewError != null) {
      content = Text(
        state.previewError!,
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else if (p == null) {
      content = Text(
        state.previewing ? 'Menghitung...' : 'Isi jumlah cucian untuk melihat rincian harga.',
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in p.lines) ...[
            _row(
              context,
              '${l.serviceName} × ${formatQty(l.quantity)}',
              formatRupiah(l.lineTotal - l.addons.fold<int>(0, (s, a) => s + a.amount)),
            ),
            for (final a in l.addons) _row(context, '   + ${a.name}', formatRupiah(a.amount)),
          ],
          const Divider(),
          _row(
            context,
            'Kecepatan${p.speedName == null ? '' : ' (${p.speedName})'}',
            formatRupiah(p.speedFee),
          ),
          _row(
            context,
            'Penerimaan${p.fulfillmentName == null ? '' : ' (${p.fulfillmentName})'}',
            formatRupiah(p.deliveryFee),
          ),
          if (p.discount > 0) _row(context, 'Diskon', '-${formatRupiah(p.discount)}'),
          const Divider(),
          _row(context, 'Total', formatRupiah(p.total), bold: true),
          if (p.estimatedDoneAt != null) ...[
            const SizedBox(height: 8),
            Text(
              'Estimasi selesai: ${formatDateTime(p.estimatedDoneAt!)}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rincian harga', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            content,
          ],
        ),
      ),
    );
  }
}

// ======================================================= Langkah 1: Pelanggan

class CustomerStep extends ConsumerWidget {
  const CustomerStep({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customer = ref.watch(posControllerProvider.select((s) => s.customer));
    final locked = ref.watch(posControllerProvider.select((s) => s.locked));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const _SectionTitle(
          'Pelanggan',
          hint: 'Pilih pelanggan lama atau tambahkan pelanggan baru',
        ),
        Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: CircleAvatar(
              child: Icon(customer == null ? Icons.person_outline : Icons.person),
            ),
            title: Text(
              customer?.name ?? 'Belum ada pelanggan dipilih',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              customer == null ? 'Cari berdasarkan nama atau nomor HP' : customer.phone,
            ),
            trailing: customer == null
                ? null
                : const Icon(Icons.check_circle, color: Colors.green),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: locked
              ? null
              : () async {
                  final c = await showCustomerPicker(context);
                  if (c != null) ref.read(posControllerProvider.notifier).setCustomer(c);
                },
          icon: const Icon(Icons.search),
          label: Text(customer == null ? 'Cari atau tambah pelanggan' : 'Ganti pelanggan'),
        ),
      ],
    );
  }
}

// ========================================================= Langkah 2: Layanan

class ServicesStep extends ConsumerStatefulWidget {
  const ServicesStep({super.key, required this.catalog});

  final PosCatalog catalog;

  @override
  ConsumerState<ServicesStep> createState() => _ServicesStepState();
}

class _ServicesStepState extends ConsumerState<ServicesStep> {
  late final TextEditingController _discount;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    final s = ref.read(posControllerProvider);
    _discount = TextEditingController(text: s.discount > 0 ? '${s.discount}' : '');
    _notes = TextEditingController(text: s.notes);
  }

  @override
  void dispose() {
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.catalog;
    final state = ref.watch(posControllerProvider);
    final ctrl = ref.read(posControllerProvider.notifier);
    final locked = state.locked;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const _SectionTitle(
          'Jenis layanan',
          hint: 'Menentukan kecepatan dan estimasi selesai',
        ),
        if (cat.speeds.isEmpty)
          const Text('Belum ada pilihan kecepatan. Pemilik dapat menambahkannya.'),
        for (final o in cat.speeds)
          _ChoiceCard(
            title: o.name,
            subtitle: [
              if (o.durationLabel != null) 'Estimasi ${o.durationLabel}',
              o.tariffLabel,
            ].join(' • '),
            selected: state.speedId == o.id,
            onTap: locked ? null : () => ctrl.setSpeed(o.id),
          ),

        const _SectionTitle('Cucian', hint: 'Jenis pakaian atau barang, lalu berat atau jumlahnya'),
        if (cat.services.isEmpty)
          const Text('Belum ada jenis cucian. Pemilik dapat menambahkannya.'),
        for (final line in state.lines)
          _LineCard(
            key: ValueKey(line.uid),
            line: line,
            services: cat.services,
            addons: cat.addons,
            locked: locked,
            canRemove: state.lines.length > 1,
            onService: (s) => ctrl.changeService(line.uid, s),
            onQuantity: (q) => ctrl.updateLine(line.uid, quantity: q),
            onAddons: (ids) => ctrl.updateLine(line.uid, addonIds: ids),
            onNotes: (t) => ctrl.updateLine(line.uid, notes: t),
            onRemove: () => ctrl.removeLine(line.uid),
          ),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: (locked || cat.services.isEmpty)
              ? null
              : () => ctrl.addLine(cat.services.first),
          icon: const Icon(Icons.add),
          label: const Text('Tambah jenis cucian'),
        ),

        const _SectionTitle('Penerimaan', hint: 'Ambil sendiri, diantar, atau jemput dan antar'),
        if (cat.fulfillments.isEmpty)
          const Text('Belum ada pilihan penerimaan. Pemilik dapat menambahkannya.'),
        for (final o in cat.fulfillments)
          _ChoiceCard(
            title: o.name,
            subtitle: o.tariffLabel,
            selected: state.fulfillmentId == o.id,
            onTap: locked ? null : () => ctrl.setFulfillment(o.id),
          ),

        const _SectionTitle('Diskon dan catatan'),
        TextField(
          controller: _discount,
          enabled: !locked,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Diskon (Rp)',
            prefixText: 'Rp ',
          ),
          onChanged: (v) => ctrl.setDiscount(int.tryParse(v) ?? 0),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          enabled: !locked,
          decoration: const InputDecoration(labelText: 'Catatan pesanan (opsional)'),
          onChanged: ctrl.setNotes,
        ),
        const SizedBox(height: 16),
        PriceSummary(state: state),
      ],
    );
  }
}

class _LineCard extends StatefulWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.services,
    required this.addons,
    required this.locked,
    required this.canRemove,
    required this.onService,
    required this.onQuantity,
    required this.onAddons,
    required this.onNotes,
    required this.onRemove,
  });

  final CartLine line;
  final List<PosService> services;
  final List<PosOption> addons;
  final bool locked;
  final bool canRemove;
  final ValueChanged<PosService> onService;
  final ValueChanged<double> onQuantity;
  final ValueChanged<Set<int>> onAddons;
  final ValueChanged<String> onNotes;
  final VoidCallback onRemove;

  @override
  State<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends State<_LineCard> {
  late final TextEditingController _qty =
      TextEditingController(text: formatQty(widget.line.quantity));
  late final TextEditingController _notes =
      TextEditingController(text: widget.line.notes);

  @override
  void dispose() {
    _qty.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.line.service;
    final known = widget.services.any((x) => x.id == s.id);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: known ? s.id : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Jenis pakaian / barang',
                    ),
                    items: [
                      for (final x in widget.services)
                        DropdownMenuItem(
                          value: x.id,
                          child: Text(
                            '${x.name} • ${formatRupiah(x.price)}/${x.unit}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: widget.locked
                        ? null
                        : (id) {
                            if (id == null) return;
                            widget.onService(widget.services.firstWhere((x) => x.id == id));
                          },
                  ),
                ),
                if (widget.canRemove && !widget.locked)
                  IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qty,
              enabled: !widget.locked,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: 'Jumlah / berat',
                suffixText: s.unit,
                helperText: '${formatRupiah(s.price)} per ${s.unit}',
              ),
              onChanged: (v) =>
                  widget.onQuantity(double.tryParse(v.replaceAll(',', '.')) ?? 0),
            ),
            if (widget.addons.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Tambahan', style: theme.textTheme.bodySmall),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in widget.addons)
                    FilterChip(
                      label: Text('${a.name} ${a.tariffLabel}'),
                      selected: widget.line.addonIds.contains(a.id),
                      onSelected: widget.locked
                          ? null
                          : (on) {
                              final ids = {...widget.line.addonIds};
                              on ? ids.add(a.id) : ids.remove(a.id);
                              widget.onAddons(ids);
                            },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _notes,
              enabled: !widget.locked,
              decoration: const InputDecoration(
                isDense: true,
                labelText: 'Catatan pakaian (noda, luntur, dll.)',
              ),
              onChanged: widget.onNotes,
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================== Langkah 3: Foto

class PhotosStep extends ConsumerStatefulWidget {
  const PhotosStep({super.key});

  @override
  ConsumerState<PhotosStep> createState() => _PhotosStepState();
}

class _PhotosStepState extends ConsumerState<PhotosStep> {
  final _picker = ImagePicker();
  bool _busy = false;

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pick(ImageSource source) async {
    if (_busy) return;
    if (ref.read(posControllerProvider).photos.length >= kMaxPhotos) {
      _snack('Maksimal $kMaxPhotos foto.');
      return;
    }
    setState(() => _busy = true);
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (x != null) ref.read(posControllerProvider.notifier).addPhoto(x.path);
    } catch (_) {
      if (mounted) _snack('Tidak bisa membuka kamera atau galeri.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posControllerProvider);
    final ctrl = ref.read(posControllerProvider.notifier);
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _SectionTitle(
          'Dokumentasi cucian',
          hint: kMinPhotos > 0
              ? 'Foto kondisi cucian saat diterima. Minimal $kMinPhotos, maksimal $kMaxPhotos foto.'
              : 'Foto kondisi cucian saat diterima. Maksimal $kMaxPhotos foto.',
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: (_busy || state.locked) ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera),
                label: const Text('Ambil foto'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_busy || state.locked) ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Dari galeri'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (state.photos.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.add_a_photo_outlined, size: 40),
                SizedBox(height: 8),
                Text('Belum ada foto.', textAlign: TextAlign.center),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: state.photos.length,
            itemBuilder: (context, i) => ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(state.photos[i]), fit: BoxFit.cover, cacheWidth: 400),
                  if (!state.locked)
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton.filled(
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        tooltip: 'Hapus foto',
                        icon: const Icon(Icons.close),
                        onPressed: () => ctrl.removePhoto(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        Text(
          '${state.photos.length} dari maksimal $kMaxPhotos foto. '
          'Foto diunggah ke server saat pesanan disimpan, sebagai bukti kondisi cucian.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

// ======================================================== Langkah 4: Bayar

class PaymentStep extends ConsumerStatefulWidget {
  const PaymentStep({super.key});

  @override
  ConsumerState<PaymentStep> createState() => _PaymentStepState();
}

class _PaymentStepState extends ConsumerState<PaymentStep> {
  late final TextEditingController _deposit;
  late final TextEditingController _note;
  final _cash = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = ref.read(posControllerProvider);
    _deposit = TextEditingController(text: s.deposit > 0 ? '${s.deposit}' : '');
    _note = TextEditingController(text: s.payNote);
  }

  @override
  void dispose() {
    _deposit.dispose();
    _note.dispose();
    _cash.dispose();
    super.dispose();
  }

  Widget _info(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label)),
            Expanded(
              child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posControllerProvider);
    final ctrl = ref.read(posControllerProvider.notifier);
    final theme = Theme.of(context);
    final p = state.preview;
    final created = state.created;
    final total = created?.total ?? p?.total ?? 0;
    final payLocked = state.paymentDone || state.submitting;

    final due = switch (state.payMode) {
      PayMode.later => 0,
      PayMode.deposit => state.deposit,
      PayMode.full => total,
    };
    final received = int.tryParse(_cash.text) ?? 0;
    final change = received - due;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const _SectionTitle('Konfirmasi pesanan'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _info('Pelanggan', state.customer?.name ?? '-'),
                _info('Nomor HP', state.customer?.phone ?? '-'),
                if (p?.speedName != null) _info('Layanan', p!.speedName!),
                if (p?.fulfillmentName != null) _info('Penerimaan', p!.fulfillmentName!),
                _info('Foto', '${state.photos.length} lembar'),
                if (state.notes.trim().isNotEmpty) _info('Catatan', state.notes.trim()),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        PriceSummary(state: state),

        // ---- Progres penyimpanan (setelah pesanan dibuat)
        if (created != null) ...[
          const SizedBox(height: 12),
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Pesanan ${created.orderNumber} sudah dibuat',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        state.photosUploaded >= state.photos.length
                            ? Icons.check_circle
                            : Icons.sync_problem,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text('Foto terkirim ${state.photosUploaded}/${state.photos.length}'),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(
                        state.paymentDone ? Icons.check_circle : Icons.sync_problem,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(state.paymentDone ? 'Pembayaran tercatat' : 'Pembayaran belum tercatat'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Ketuk "Lanjutkan penyimpanan" untuk menyelesaikan.'),
                ],
              ),
            ),
          ),
        ],

        // ---- Pembayaran
        const _SectionTitle('Pembayaran'),
        SegmentedButton<PayMode>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: PayMode.later, label: Text('Bayar nanti')),
            ButtonSegment(value: PayMode.deposit, label: Text('Uang muka')),
            ButtonSegment(value: PayMode.full, label: Text('Lunas')),
          ],
          selected: {state.payMode},
          onSelectionChanged: payLocked ? null : (s) => ctrl.setPayMode(s.first),
        ),
        if (state.payMode != PayMode.later) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final e in paymentMethodLabel.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: state.payMethod == e.key,
                  onSelected: payLocked ? null : (_) => ctrl.setPayMethod(e.key),
                ),
            ],
          ),
        ],
        if (state.payMode == PayMode.deposit) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _deposit,
            enabled: !payLocked,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Nominal uang muka',
              prefixText: 'Rp ',
            ),
            onChanged: (v) => ctrl.setDeposit(int.tryParse(v) ?? 0),
          ),
        ],
        if (state.payMode != PayMode.later && state.payMethod == 'CASH' && due > 0) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _cash,
            enabled: !payLocked,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Uang diterima (opsional)',
              prefixText: 'Rp ',
              helperText: received <= 0
                  ? 'Untuk menghitung kembalian'
                  : (change >= 0
                      ? 'Kembalian ${formatRupiah(change)}'
                      : 'Uang kurang ${formatRupiah(-change)}'),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        if (state.payMode != PayMode.later) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            enabled: !payLocked,
            decoration: const InputDecoration(labelText: 'Catatan pembayaran (opsional)'),
            onChanged: ctrl.setPayNote,
          ),
        ],
        const SizedBox(height: 12),
        Text(
          state.payMode == PayMode.later
              ? 'Pesanan disimpan dengan status belum bayar.'
              : 'Sisa tagihan setelah pembayaran ini: ${formatRupiah(total - due < 0 ? 0 : total - due)}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}