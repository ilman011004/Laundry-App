import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_providers.dart';
import '../cash/cash_repository.dart';
import '../orders/orders_repository.dart';

class DebtItem {
  const DebtItem({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.remaining,
  });

  final int id;
  final String orderNumber;
  final String customerName;
  final int remaining;
}

class OverdueItem {
  const OverdueItem({
    required this.id,
    required this.orderNumber,
    required this.customerName,
    required this.workStatus,
    this.estimatedDoneAt,
  });

  final int id;
  final String orderNumber;
  final String customerName;
  final String workStatus;
  final DateTime? estimatedDoneAt;
}

class Money {
  const Money({
    required this.transfer,
    required this.qris,
    required this.incomeToday,
    required this.incomeMonth,
    required this.expensesMonth,
  });

  final int transfer;
  final int qris;
  final int incomeToday;
  final int incomeMonth;
  final int expensesMonth;
}

class Dashboard {
  const Dashboard({
    required this.inProgress,
    required this.ready,
    required this.completedToday,
    required this.ordersToday,
    required this.overdue,
    required this.overdueList,
    required this.unpaidCount,
    required this.outstanding,
    required this.topDebts,
    required this.cash,
    this.money,
  });

  final int inProgress;
  final int ready;
  final int completedToday;
  final int ordersToday;
  final int overdue;
  final List<OverdueItem> overdueList;
  final int unpaidCount;
  final int outstanding;
  final List<DebtItem> topDebts;
  final CashSummary cash;
  final Money? money; // null untuk Kasir

  factory Dashboard.fromJson(Map<String, dynamic> j) {
    final o = j['orders'] as Map<String, dynamic>;
    final p = j['payments'] as Map<String, dynamic>;
    final m = j['money'] as Map<String, dynamic>?;
    return Dashboard(
      inProgress: o['inProgress'] as int,
      ready: o['ready'] as int,
      completedToday: o['completedToday'] as int,
      ordersToday: o['today'] as int,
      overdue: o['overdue'] as int,
      overdueList: ((o['overdueList'] as List?) ?? []).map((e) {
        final d = e as Map<String, dynamic>;
        return OverdueItem(
          id: d['id'] as int,
          orderNumber: d['orderNumber'] as String,
          customerName: d['customerName'] as String,
          workStatus: d['workStatus'] as String,
          estimatedDoneAt: d['estimatedDoneAt'] == null
              ? null
              : DateTime.parse(d['estimatedDoneAt'] as String),
        );
      }).toList(),
      unpaidCount: p['unpaidCount'] as int,
      outstanding: p['outstanding'] as int,
      topDebts: ((p['topDebts'] as List?) ?? []).map((e) {
        final d = e as Map<String, dynamic>;
        return DebtItem(
          id: d['id'] as int,
          orderNumber: d['orderNumber'] as String,
          customerName: d['customerName'] as String,
          remaining: d['remaining'] as int,
        );
      }).toList(),
      cash: CashSummary.fromJson(j['cash'] as Map<String, dynamic>),
      money: m == null
          ? null
          : Money(
              transfer: m['transfer'] as int,
              qris: m['qris'] as int,
              incomeToday: m['incomeToday'] as int,
              incomeMonth: m['incomeMonth'] as int,
              expensesMonth: m['expensesMonth'] as int,
            ),
    );
  }
}

/// Dimuat ulang otomatis saat ada pesanan atau pembayaran baru.
final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) async {
  ref.watch(ordersRevisionProvider);
  final res = await ref.watch(dioProvider).get('/api/dashboard');
  return Dashboard.fromJson(res.data['data'] as Map<String, dynamic>);
});