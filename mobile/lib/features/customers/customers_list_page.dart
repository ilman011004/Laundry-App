import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/api_error.dart';
import 'customer_models.dart';
import 'customers_repository.dart';

class CustomersListPage extends ConsumerStatefulWidget {
  const CustomersListPage({super.key});

  @override
  ConsumerState<CustomersListPage> createState() => _CustomersListPageState();
}

class _CustomersListPageState extends ConsumerState<CustomersListPage> {
  final _scroll = ScrollController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  final List<Customer> _items = [];
  int _page = 0;
  bool _hasMore = true;
  bool _loading = false;
  String? _error;
  int _requestId = 0;

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
      final result = await ref
          .read(customersRepositoryProvider)
          .list(search: _searchCtrl.text, page: _page + 1);
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

  void _onSearchChanged(String _) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reload);
  }

  Future<void> _open(String location) async {
    final changed = await context.push<bool>(location);
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pelanggan')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open('/customers/new'),
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Cari nama atau nomor HP',
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  const SizedBox(width: 4),
                  Text(
                    '= langganan (${Customer.regularThreshold} pesanan atau lebih)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
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
          child: Text(
            _searchCtrl.text.trim().isEmpty
                ? 'Belum ada pelanggan.\nKetuk "Tambah" untuk menambahkan.'
                : 'Pelanggan tidak ditemukan.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
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
          final c = _items[i];
          return _CustomerCard(customer: c, onTap: () => _open('/customers/${c.id}'));
        },
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard({required this.customer, required this.onTap});

  final Customer customer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = customer;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  CircleAvatar(
                    radius: 22,
                    child: Text(c.name.isEmpty ? '?' : c.name[0].toUpperCase()),
                  ),
                  if (c.isRegular)
                    const Positioned(
                      right: -4,
                      top: -4,
                      child: Icon(Icons.star, size: 18, color: Colors.amber),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            c.name,
                            style: theme.textTheme.titleMedium,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (c.isRegular) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Langganan',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF8A6100),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(c.phone, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 2),
                    Text(
                      c.orderCount == 0
                          ? 'Belum pernah laundry'
                          : '${c.orderCount}x laundry',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}