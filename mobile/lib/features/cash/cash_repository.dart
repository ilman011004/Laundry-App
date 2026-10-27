import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';

class CashierHeld {
  const CashierHeld({required this.id, required this.name, required this.held});
  final int id;
  final String name;
  final int held;
}

class CashSummary {
  const CashSummary({
    required this.isOwner,
    this.held = 0,
    this.pendingDeposits = 0,
    this.total = 0,
    this.ownerCash = 0,
    this.cashierHeldTotal = 0,
    this.pendingTotal = 0,
    this.pendingCount = 0,
    this.cashiers = const [],
  });

  final bool isOwner;
  // Kasir
  final int held;
  final int pendingDeposits;
  // Pemilik
  final int total;
  final int ownerCash;
  final int cashierHeldTotal;
  final int pendingTotal;
  final int pendingCount;
  final List<CashierHeld> cashiers;

  factory CashSummary.fromJson(Map<String, dynamic> j) {
    final isOwner = j.containsKey('cashiers');
    int n(String k) => (j[k] as int?) ?? 0;
    return CashSummary(
      isOwner: isOwner,
      held: n('held'),
      pendingDeposits: n('pendingDeposits'),
      total: n('total'),
      ownerCash: n('ownerCash'),
      cashierHeldTotal: n('cashierHeldTotal'),
      pendingTotal: n('pendingTotal'),
      pendingCount: n('pendingCount'),
      cashiers: ((j['cashiers'] as List?) ?? []).map((e) {
        final m = e as Map<String, dynamic>;
        return CashierHeld(
          id: m['id'] as int,
          name: m['name'] as String,
          held: m['held'] as int,
        );
      }).toList(),
    );
  }
}

class CashDeposit {
  const CashDeposit({
    required this.id,
    required this.cashierName,
    required this.amount,
    required this.status,
    required this.createdAt,
    this.note,
  });

  final int id;
  final String cashierName;
  final int amount;
  final String status; // PENDING, CONFIRMED
  final DateTime createdAt;
  final String? note;

  bool get isPending => status == 'PENDING';

  factory CashDeposit.fromJson(Map<String, dynamic> j) => CashDeposit(
        id: j['id'] as int,
        cashierName: j['cashierName'] as String,
        amount: j['amount'] as int,
        status: j['status'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
        note: j['note'] as String?,
      );
}

class CashOverview {
  const CashOverview({required this.summary, required this.deposits});
  final CashSummary summary;
  final List<CashDeposit> deposits;
}

class CashRepository {
  CashRepository(this._ref);

  final Ref _ref;

  Future<CashOverview> overview() async {
    final res = await _ref.read(dioProvider).get('/api/cash');
    final d = res.data['data'] as Map<String, dynamic>;
    return CashOverview(
      summary: CashSummary.fromJson(d['summary'] as Map<String, dynamic>),
      deposits: (d['deposits'] as List)
          .map((e) => CashDeposit.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> deposit(int amount, String? note) async {
    await _ref.read(dioProvider).post('/api/cash/deposits', data: {
      'amount': amount,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
    });
  }

  Future<void> confirm(int id) async {
    await _ref.read(dioProvider).post('/api/cash/deposits/$id/confirm');
  }
}

final cashRepositoryProvider =
    Provider<CashRepository>((ref) => CashRepository(ref));

final cashOverviewProvider = FutureProvider.autoDispose<CashOverview>((ref) {
  return ref.watch(cashRepositoryProvider).overview();
});