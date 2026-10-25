import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

class CustomerDetailPage extends ConsumerStatefulWidget {
  const CustomerDetailPage({super.key, required this.customerId});

  final int customerId;

  @override
  ConsumerState<CustomerDetailPage> createState() => _CustomerDetailPageState();
}

class _CustomerDetailPageState extends ConsumerState<CustomerDetailPage> {
  bool _changed = false; // memberi tahu daftar agar dimuat ulang

  void _refresh() => ref.invalidate(customerDetailProvider(widget.customerId));

  void _snack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      _changed = true;
      _refresh();
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
  }

  Future<void> _edit() async {
    final ok = await context.push<bool>('/customers/${widget.customerId}/edit');
    if (ok == true) {
      _changed = true;
      _refresh();
    }
  }

  Future<void> _addAddress() async {
    final result = await showDialog<({String label, String address})>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (result == null) return;
    await _run(() => ref
        .read(customersRepositoryProvider)
        .addAddress(widget.customerId, label: result.label, address: result.address));
  }

  Future<void> _deleteAddress(CustomerAddress a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus alamat?'),
        content: Text('${a.label}: ${a.address}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
        () => ref.read(customersRepositoryProvider).deleteAddress(widget.customerId, a.id));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(customerDetailProvider(widget.customerId));

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) context.pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Detail Pelanggan'),
          actions: [
            IconButton(tooltip: 'Ubah', icon: const Icon(Icons.edit), onPressed: _edit),
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
      ),
    );
  }

  Widget _buildContent(CustomerDetail d) {
    final theme = Theme.of(context);
    final c = d.customer;

    return RefreshIndicator(
      onRefresh: () async {
        _refresh();
        await ref.read(customerDetailProvider(widget.customerId).future);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text(c.name, style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(c.phone, style: theme.textTheme.bodyLarge),
          if (c.notes != null && c.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(c.notes!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _StatCard(label: 'Pesanan', value: '${d.totalOrders}')),
              const SizedBox(width: 8),
              Expanded(child: _StatCard(label: 'Total belanja', value: formatRupiah(d.totalSpent))),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  label: 'Tagihan',
                  value: formatRupiah(d.outstanding),
                  highlight: d.outstanding > 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('Alamat', style: theme.textTheme.titleMedium)),
              TextButton.icon(
                onPressed: _addAddress,
                icon: const Icon(Icons.add),
                label: const Text('Tambah'),
              ),
            ],
          ),
          if (c.addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Belum ada alamat.'),
            ),
          for (final a in c.addresses)
            Card(
              child: ListTile(
                leading: Icon(a.isDefault ? Icons.star : Icons.place_outlined),
                title: Text(a.isDefault ? '${a.label} (utama)' : a.label),
                subtitle: Text(a.address),
                trailing: PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'default') {
                      _run(() => ref
                          .read(customersRepositoryProvider)
                          .setDefaultAddress(widget.customerId, a.id));
                    } else if (v == 'delete') {
                      _deleteAddress(a);
                    }
                  },
                  itemBuilder: (_) => [
                    if (!a.isDefault)
                      const PopupMenuItem(value: 'default', child: Text('Jadikan utama')),
                    const PopupMenuItem(value: 'delete', child: Text('Hapus')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text('Pesanan aktif', style: theme.textTheme.titleMedium),
          if (d.activeOrders.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Tidak ada pesanan aktif.'),
            ),
          for (final o in d.activeOrders)
            Card(
              child: ListTile(
                title: Text(o.orderNumber),
                subtitle: Text(
                  '${labelOf(workStatusLabel, o.workStatus)} • '
                  '${labelOf(paymentStatusLabel, o.paymentStatus)}',
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatRupiah(o.total)),
                    if (o.remaining > 0)
                      Text('Sisa ${formatRupiah(o.remaining)}',
                          style: TextStyle(color: theme.colorScheme.error, fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.label, required this.value, this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: highlight ? theme.colorScheme.error : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController(text: 'Rumah');
  final _address = TextEditingController();

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tambah alamat'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _label,
              decoration: const InputDecoration(labelText: 'Label'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _address,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Alamat lengkap'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Alamat wajib diisi' : null,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(context, (label: _label.text, address: _address.text));
          },
          child: const Text('Simpan'),
        ),
      ],
    );
  }
}