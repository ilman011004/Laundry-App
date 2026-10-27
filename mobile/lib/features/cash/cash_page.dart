import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../auth/auth_controller.dart';
import '../home/dashboard_repository.dart';
import 'cash_repository.dart';

class CashPage extends ConsumerWidget {
  const CashPage({super.key});

  void _snack(BuildContext context, String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(cashOverviewProvider);
    ref.invalidate(dashboardProvider);
  }

  Future<void> _deposit(BuildContext context, WidgetRef ref, int held) async {
    final r = await showDialog<({int amount, String note})>(
      context: context,
      builder: (_) => _DepositDialog(held: held),
    );
    if (r == null) return;

    String message = 'Setoran dikirim, menunggu konfirmasi pemilik';
    try {
      await ref.read(cashRepositoryProvider).deposit(r.amount, r.note);
      _refreshAll(ref);
    } catch (e) {
      message = errorMessage(e);
    }
    if (context.mounted) _snack(context, message);
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref, CashDeposit d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Terima setoran?'),
        content: Text(
          'Pastikan uang ${formatRupiah(d.amount)} dari ${d.cashierName} '
          'sudah Anda terima.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Belum'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sudah diterima'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    String message = 'Setoran diterima';
    try {
      await ref.read(cashRepositoryProvider).confirm(d.id);
      _refreshAll(ref);
    } catch (e) {
      message = errorMessage(e);
    }
    if (context.mounted) _snack(context, message);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOwner = ref.watch(authControllerProvider).user?.isOwner ?? false;
    final async = ref.watch(cashOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: Text(isOwner ? 'Kas Usaha' : 'Kas Saya')),
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
                  onPressed: () => ref.invalidate(cashOverviewProvider),
                  child: const Text('Coba lagi'),
                ),
              ],
            ),
          ),
        ),
        data: (o) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(cashOverviewProvider);
            await ref.read(cashOverviewProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (isOwner)
                ..._ownerSections(context, ref, o)
              else
                ..._cashierSections(context, ref, o),
              const SizedBox(height: 8),
              Text('Riwayat setoran',
                  style: Theme.of(context).textTheme.titleMedium),
              if (o.deposits.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Belum ada setoran.'),
                ),
              for (final d in o.deposits)
                Card(
                  child: ListTile(
                    title: Text(formatRupiah(d.amount)),
                    subtitle: Text(
                      '${isOwner ? '${d.cashierName} • ' : ''}${formatDateTime(d.createdAt)}'
                      '${d.note == null || d.note!.isEmpty ? '' : '\n${d.note}'}',
                    ),
                    isThreeLine: d.note != null && d.note!.isNotEmpty,
                    trailing: d.isPending
                        ? (isOwner
                            ? FilledButton(
                                onPressed: () => _confirm(context, ref, d),
                                child: const Text('Terima'),
                              )
                            : const Chip(label: Text('Menunggu')))
                        : const Chip(label: Text('Diterima')),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _cashierSections(BuildContext context, WidgetRef ref, CashOverview o) {
    final s = o.summary;
    final theme = Theme.of(context);
    return [
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Uang tunai yang Anda pegang'),
              const SizedBox(height: 4),
              Text(formatRupiah(s.held),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              if (s.pendingDeposits > 0) ...[
                const SizedBox(height: 8),
                Text(
                  'Setoran menunggu konfirmasi pemilik: ${formatRupiah(s.pendingDeposits)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: s.held > 0 ? () => _deposit(context, ref, s.held) : null,
                  icon: const Icon(Icons.savings_outlined),
                  label: const Text('Setor ke pemilik'),
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Kas bertambah saat pelanggan membayar tunai. Transfer dan QRIS '
        'tidak masuk kas. Setelah menyerahkan uang, buat setoran di sini '
        'agar pemilik bisa mengonfirmasi.',
      ),
    ];
  }

  List<Widget> _ownerSections(BuildContext context, WidgetRef ref, CashOverview o) {
    final s = o.summary;
    final theme = Theme.of(context);

    Widget row(String label, int value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Expanded(child: Text(label)),
              Text(
                formatRupiah(value),
                style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null,
              ),
            ],
          ),
        );

    return [
      Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Total kas usaha'),
              const SizedBox(height: 4),
              Text(formatRupiah(s.total),
                  style: theme.textTheme.headlineMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const Divider(height: 24),
              row('Di pemilik', s.ownerCash),
              row('Di tangan kasir', s.cashierHeldTotal),
              row('Setoran belum diterima', s.pendingTotal),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Text('Kas per kasir', style: theme.textTheme.titleMedium),
      if (s.cashiers.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('Belum ada kasir.'),
        ),
      for (final c in s.cashiers)
        Card(
          child: ListTile(
            leading: CircleAvatar(
              child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
            ),
            title: Text(c.name),
            trailing: Text(formatRupiah(c.held),
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
    ];
  }
}

class _DepositDialog extends StatefulWidget {
  const _DepositDialog({required this.held});

  final int held;

  @override
  State<_DepositDialog> createState() => _DepositDialogState();
}

class _DepositDialogState extends State<_DepositDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount =
      TextEditingController(text: widget.held.toString());
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Setor ke pemilik'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kas yang Anda pegang: ${formatRupiah(widget.held)}'),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'Nominal disetor',
                  prefixText: 'Rp ',
                  suffixIcon: TextButton(
                    onPressed: () => _amount.text = widget.held.toString(),
                    child: const Text('Semua'),
                  ),
                ),
                validator: (v) {
                  final n = int.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Nominal harus lebih dari 0';
                  if (n > widget.held) return 'Melebihi kas yang dipegang';
                  return null;
                },
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
            Navigator.pop(context, (amount: int.parse(_amount.text), note: _note.text));
          },
          child: const Text('Kirim setoran'),
        ),
      ],
    );
  }
}