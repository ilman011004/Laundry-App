import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/labels.dart';
import 'order_models.dart';
import 'orders_repository.dart';

Color _workColor(String s) => switch (s) {
      'RECEIVED' => Colors.blueGrey,
      'WASHING' => Colors.blue,
      'DRYING' => Colors.orange,
      'IRONING' => Colors.purple,
      'READY' => Colors.green,
      'COMPLETED' => Colors.grey,
      'CANCELLED' => Colors.red,
      _ => Colors.grey,
    };

Color _payColor(String s) => switch (s) {
      'UNPAID' => Colors.red,
      'PARTIAL' => Colors.orange,
      'PAID' => Colors.green,
      _ => Colors.grey,
    };

class OrdersListPage extends ConsumerStatefulWidget {
  const OrdersListPage({super.key});

  @override
  ConsumerState<OrdersListPage> createState() => _OrdersListPageState();
}

class _OrdersListPageState extends ConsumerState<OrdersListPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  final List<OrderSummary> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

  String? _workStatus;
  String? _paymentStatus;

  bool get _hasFilter =>
      _workStatus != null ||
      _paymentStatus != null ||
      _searchCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 300) _load();
    });
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scroll.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    _requestId++;
    setState(() {
      _items.clear();
      _page = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading || !_hasMore) return;
    final myRequest = _requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ref.read(ordersRepositoryProvider).list(
            search: _searchCtrl.text,
            workStatus: _workStatus,
            paymentStatus: _paymentStatus,
            page: _page + 1,
          );
      if (!mounted || myRequest != _requestId) return;
      setState(() {
        _items.addAll(result.items);
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || myRequest != _requestId) return;
      setState(() {
        _error = errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _open(int id) async {
    final changed = await context.push<bool>('/orders/$id');
    if (changed == true) _reload();
  }

  Future<void> _openFilter() async {
    final r = await showModalBottomSheet<({String? work, String? pay})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(work: _workStatus, pay: _paymentStatus),
    );
    if (r == null) return;
    _workStatus = r.work;
    _paymentStatus = r.pay;
    _reload();
  }

  void _clearFilters() {
    _searchCtrl.clear();
    _workStatus = null;
    _paymentStatus = null;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    // Muat ulang otomatis saat ada pesanan baru dari tab Kasir.
    ref.listen(ordersRevisionProvider, (_, _) => _reload());

    final filterCount =
        (_workStatus != null ? 1 : 0) + (_paymentStatus != null ? 1 : 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Pesanan')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) {
                      setState(() {});
                      _debounce?.cancel();
                      _debounce =
                          Timer(const Duration(milliseconds: 400), _reload);
                    },
                    decoration: InputDecoration(
                      hintText: 'Cari nama, nomor order, atau HP',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchCtrl.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchCtrl.clear();
                                _reload();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: filterCount > 0,
                  label: Text('$filterCount'),
                  child: IconButton.filledTonal(
                    tooltip: 'Filter',
                    icon: const Icon(Icons.tune),
                    onPressed: _openFilter,
                  ),
                ),
              ],
            ),
          ),
          if (_workStatus != null || _paymentStatus != null)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (_workStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(labelOf(workStatusLabel, _workStatus)),
                        onDeleted: () {
                          _workStatus = null;
                          _reload();
                        },
                      ),
                    ),
                  if (_paymentStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label:
                            Text(labelOf(paymentStatusLabel, _paymentStatus)),
                        onDeleted: () {
                          _paymentStatus = null;
                          _reload();
                        },
                      ),
                    ),
                ],
              ),
            ),
          Expanded(child: _buildList()),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _hasFilter ? Icons.search_off : Icons.receipt_long_outlined,
                size: 56,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                _hasFilter
                    ? 'Tidak ada pesanan yang cocok dengan pencarian atau filter ini.'
                    : 'Belum ada pesanan.\nBuat pesanan baru lewat tab Kasir.',
                textAlign: TextAlign.center,
              ),
              if (_hasFilter) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _clearFilters,
                  child: const Text('Hapus pencarian & filter'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        itemCount: _items.length + (_loading || _error != null ? 1 : 0),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: _error != null
                    ? TextButton(
                        onPressed: _load,
                        child: Text('$_error  Ketuk untuk ulang'))
                    : const CircularProgressIndicator(),
              ),
            );
          }
          return _OrderCard(order: _items[i], onTap: () => _open(_items[i].id));
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onTap});

  final OrderSummary order;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cancelled = order.workStatus == 'CANCELLED';
    final done = order.workStatus == 'COMPLETED';
    final est = order.estimatedDoneAt;

    Widget moneyNote;
    if (cancelled) {
      moneyNote = const SizedBox.shrink();
    } else if (order.remaining <= 0) {
      moneyNote = const Text('Lunas',
          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600));
    } else {
      moneyNote = Text(
        'Sisa ${formatRupiah(order.remaining)}',
        style: TextStyle(
            color: theme.colorScheme.error, fontWeight: FontWeight.w600),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.customerName,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(order.orderNumber, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Badge(
                          text: labelOf(workStatusLabel, order.workStatus),
                          color: _workColor(order.workStatus),
                        ),
                        if (!cancelled)
                          _Badge(
                            text:
                                labelOf(paymentStatusLabel, order.paymentStatus),
                            color: _payColor(order.paymentStatus),
                          ),
                      ],
                    ),
                    if (est != null && !cancelled && !done) ...[
                      const SizedBox(height: 8),
                      Text('Estimasi selesai: ${formatDateTime(est)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatRupiah(order.total),
                    style: theme.textTheme.titleMedium?.copyWith(
                      decoration:
                          cancelled ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  moneyNote,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.work, required this.pay});

  final String? work;
  final String? pay;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _work = widget.work;
  late String? _pay = widget.pay;

  Widget _group(
    String title,
    Map<String, String> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Semua'),
              selected: selected == null,
              onSelected: (_) => onChanged(null),
            ),
            for (final e in options.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: selected == e.key,
                onSelected: (_) => onChanged(e.key),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Filter pesanan',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _group('Tahap pengerjaan', workStatusLabel, _work,
                (v) => setState(() => _work = v)),
            const SizedBox(height: 20),
            _group('Pembayaran', paymentStatusLabel, _pay,
                (v) => setState(() => _pay = v)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _work = null;
                      _pay = null;
                    }),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, (work: _work, pay: _pay)),
                    child: const Text('Terapkan'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}