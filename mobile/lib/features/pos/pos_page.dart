import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import 'pos_controller.dart';
import 'pos_nota_view.dart';
import 'pos_repository.dart';
import 'pos_steps.dart';

class PosPage extends ConsumerStatefulWidget {
  const PosPage({super.key});

  @override
  ConsumerState<PosPage> createState() => _PosPageState();
}

class _PosPageState extends ConsumerState<PosPage> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(posControllerProvider.notifier).start());
  }

  PosController get _ctrl => ref.read(posControllerProvider.notifier);

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  bool _canContinue(PosState s) => switch (_step) {
        0 => s.customer != null,
        1 => s.lines.isNotEmpty &&
            s.lines.every((l) => l.quantity > 0) &&
            s.preview != null &&
            !s.previewing &&
            s.previewError == null,
        2 => s.photos.length >= kMinPhotos,
        _ => true,
      };

  Future<void> _submit() async {
    final error = await _ctrl.submit();
    if (!mounted) return;
    if (error != null) _snack(error);
  }

  Future<void> _newOrder() async {
    await _ctrl.reset();
    if (mounted) setState(() => _step = 0);
  }

  Future<bool> _confirm(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirmClear() async {
    if (await _confirm('Kosongkan form?', 'Semua isian pesanan ini akan dihapus.', 'Kosongkan')) {
      await _newOrder();
    }
  }

  Future<void> _closeUnfinished(String orderNumber) async {
    final ok = await _confirm(
      'Tutup tanpa menyelesaikan?',
      'Pesanan $orderNumber sudah tersimpan di sistem. Foto atau pembayaran yang '
          'belum terkirim tidak akan dilanjutkan, dan bisa dicatat dari tab Pesanan.',
      'Tutup',
    );
    if (ok) await _newOrder();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(posControllerProvider);
    final catalog = ref.watch(catalogProvider);

    if (state.done) {
      return PosNotaView(order: state.created!, onNewOrder: _newOrder);
    }

    final step = state.locked ? 3 : _step;

    Widget body;
    switch (step) {
      case 0:
        body = const CustomerStep();
      case 1:
        body = catalog.when(
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
          data: (cat) => ServicesStep(catalog: cat),
        );
      case 2:
        body = const PhotosStep();
      default:
        body = const PaymentStep();
    }

    return PopScope(
      canPop: step == 0 && !state.locked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (state.locked) {
          _snack('Selesaikan penyimpanan dulu, atau pilih "Tutup tanpa menyelesaikan".');
          return;
        }
        setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kasir'),
          actions: [
            if (state.locked)
              TextButton(
                onPressed: state.submitting
                    ? null
                    : () => _closeUnfinished(state.created!.orderNumber),
                child: const Text('Tutup tanpa menyelesaikan'),
              )
            else
              IconButton(
                tooltip: 'Kosongkan form',
                icon: const Icon(Icons.restart_alt),
                onPressed: _confirmClear,
              ),
          ],
        ),
        body: Column(
          children: [
            _StepHeader(current: step),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: _bottomBar(state, step),
      ),
    );
  }

  Widget _bottomBar(PosState state, int step) {
    final theme = Theme.of(context);
    final total = state.created?.total ?? state.preview?.total;
    final isLast = step == 3;
    final canSave = state.created != null || (total != null && !state.previewing);

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (step >= 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(child: Text('Total', style: theme.textTheme.bodyMedium)),
                      Text(
                        total == null ? '-' : formatRupiah(total),
                        style: theme.textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  if (step > 0 && !state.locked) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: state.submitting ? null : () => setState(() => _step--),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Kembali'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isLast
                          ? ((canSave && !state.submitting) ? _submit : null)
                          : (_canContinue(state) ? () => setState(() => _step++) : null),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: state.submitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(
                                !isLast
                                    ? 'Lanjut'
                                    : (state.created != null
                                        ? 'Lanjutkan penyimpanan'
                                        : 'Simpan pesanan'),
                              ),
                      ),
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

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});

  final int current;

  static const _labels = ['Pelanggan', 'Layanan', 'Foto', 'Bayar'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          for (var i = 0; i < _labels.length; i++)
            Expanded(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: i <= current ? cs.primary : cs.surfaceContainerHighest,
                    foregroundColor: i <= current ? cs.onPrimary : cs.onSurfaceVariant,
                    child: i < current
                        ? const Icon(Icons.check, size: 16)
                        : Text('${i + 1}', style: const TextStyle(fontSize: 13)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}