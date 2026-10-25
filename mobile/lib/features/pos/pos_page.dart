import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import 'customer_picker.dart';
import 'pos_controller.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  final _discount = TextEditingController();
  final _notes = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(posControllerProvider.notifier).start());
  }

  @override
  void dispose() {
    _discount.dispose();
    _notes.dispose();
    super.dispose();
  }

  PosController get _ctrl => ref.read(posControllerProvider.notifier);

  Future<void> _pickCustomer() async {
    final c = await showCustomerPicker(context);
    if (c != null) _ctrl.setCustomer(c);
  }

  Future<void> _addService(PosCatalog cat) async {
    final s = await showModalBottomSheet<PosService>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final s in cat.services)
              ListTile(
                title: Text(s.name),
                subtitle: Text('${formatRupiah(s.price)} / ${s.unit}'),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (s != null) _ctrl.addLine(s);
  }

  Future<void> _save() async {
    final r = await _ctrl.save();
    if (!mounted) return;

    if (r.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.error!)));
      return;
    }
    if (r.orderNumber == null) return;

    _discount.clear();
    _notes.clear();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pesanan tersimpan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.orderNumber!, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Total ${formatRupiah(r.total ?? 0)}'),
            const SizedBox(height: 8),
            const Text('Status pembayaran: belum bayar.'),
          ],
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posControllerProvider);
    final catalog = ref.watch(catalogProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Kasir')),
      body: catalog.when(
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
                  onPressed: () => _ctrl.start(),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (cat) => _buildForm(cat, state),
      ),
      bottomNavigationBar: _buildBottomBar(state),
    );
  }

  Widget _buildForm(PosCatalog cat, PosState state) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // --- Pelanggan ---
        Card(
          child: ListTile(
            leading: const Icon(Icons.person),
            title: Text(state.customer?.name ?? 'Pilih pelanggan'),
            subtitle: state.customer == null ? null : Text(state.customer!.phone),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCustomer,
          ),
        ),
        const SizedBox(height: 16),

        // --- Layanan ---
        Row(
          children: [
            Expanded(child: Text('Layanan', style: theme.textTheme.titleMedium)),
            TextButton.icon(
              onPressed: cat.services.isEmpty ? null : () => _addService(cat),
              icon: const Icon(Icons.add),
              label: const Text('Tambah layanan'),
            ),
          ],
        ),
        if (state.lines.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Belum ada layanan. Ketuk "Tambah layanan".'),
          ),
        for (final line in state.lines)
          _LineCard(
            key: ValueKey(line.uid),
            line: line,
            addons: cat.addons,
            onQuantity: (q) => _ctrl.updateLine(line.uid, quantity: q),
            onAddons: (ids) => _ctrl.updateLine(line.uid, addonIds: ids),
            onNotes: (t) => _ctrl.updateLine(line.uid, notes: t),
            onRemove: () => _ctrl.removeLine(line.uid),
          ),
        const SizedBox(height: 16),

        // --- Kecepatan ---
        Text('Kecepatan', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in cat.speeds)
              ChoiceChip(
                label: Text(
                  [
                    o.name,
                    o.tariffLabel,
                    if (o.durationLabel != null) o.durationLabel!,
                  ].join(' • '),
                ),
                selected: state.speedId == o.id,
                onSelected: (_) => _ctrl.setSpeed(o.id),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // --- Penerimaan ---
        Text('Penerimaan', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in cat.fulfillments)
              ChoiceChip(
                label: Text('${o.name} • ${o.tariffLabel}'),
                selected: state.fulfillmentId == o.id,
                onSelected: (_) => _ctrl.setFulfillment(o.id),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // --- Diskon & catatan ---
        TextField(
          controller: _discount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Diskon (Rp)',
            prefixText: 'Rp ',
          ),
          onChanged: (v) => _ctrl.setDiscount(int.tryParse(v) ?? 0),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Catatan pesanan (opsional)'),
          onChanged: _ctrl.setNotes,
        ),
        const SizedBox(height: 16),

        // --- Rincian harga ---
        _PriceSummary(state: state),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildBottomBar(PosState state) {
    final theme = Theme.of(context);
    final total = state.preview?.total;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total', style: theme.textTheme.bodySmall),
                  Text(
                    total == null ? '-' : formatRupiah(total),
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: (state.saving || state.previewing || total == null) ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: state.saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Simpan pesanan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineCard extends StatefulWidget {
  const _LineCard({
    super.key,
    required this.line,
    required this.addons,
    required this.onQuantity,
    required this.onAddons,
    required this.onNotes,
    required this.onRemove,
  });

  final CartLine line;
  final List<PosOption> addons;
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

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(s.name, style: theme.textTheme.titleSmall),
                      Text('${formatRupiah(s.price)} / ${s.unit}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    textAlign: TextAlign.end,
                    decoration: InputDecoration(
                      isDense: true,
                      suffixText: s.unit,
                    ),
                    onChanged: (v) => widget.onQuantity(
                      double.tryParse(v.replaceAll(',', '.')) ?? 0,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Hapus',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            if (widget.addons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final a in widget.addons)
                    FilterChip(
                      label: Text('${a.name} ${a.tariffLabel}'),
                      selected: widget.line.addonIds.contains(a.id),
                      onSelected: (on) {
                        final ids = {...widget.line.addonIds};
                        on ? ids.add(a.id) : ids.remove(a.id);
                        widget.onAddons(ids);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _notes,
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

class _PriceSummary extends StatelessWidget {
  const _PriceSummary({required this.state});

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
      content = Text(state.previewError!,
          style: TextStyle(color: theme.colorScheme.error));
    } else if (p == null) {
      content = Text(
        state.previewing ? 'Menghitung...' : 'Tambahkan layanan untuk melihat rincian harga.',
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in p.lines) ...[
            _row(context, '${l.serviceName} × ${formatQty(l.quantity)}',
                formatRupiah(l.lineTotal - l.addons.fold<int>(0, (s, a) => s + a.amount))),
            for (final a in l.addons)
              _row(context, '   + ${a.name}', formatRupiah(a.amount)),
          ],
          const Divider(),
          _row(context, 'Kecepatan${p.speedName == null ? '' : ' (${p.speedName})'}',
              formatRupiah(p.speedFee)),
          _row(context, 'Penerimaan${p.fulfillmentName == null ? '' : ' (${p.fulfillmentName})'}',
              formatRupiah(p.deliveryFee)),
          if (p.discount > 0) _row(context, 'Diskon', '-${formatRupiah(p.discount)}'),
          const Divider(),
          _row(context, 'Total', formatRupiah(p.total), bold: true),
          if (p.estimatedDoneAt != null) ...[
            const SizedBox(height: 8),
            Text('Estimasi selesai: ${formatDateTime(p.estimatedDoneAt!)}',
                style: theme.textTheme.bodySmall),
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