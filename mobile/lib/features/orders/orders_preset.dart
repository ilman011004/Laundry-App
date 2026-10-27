import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pintasan dari Beranda ke tab Pesanan dengan filter tertentu.
/// `n` dinaikkan setiap kali dibuka, supaya ketukan yang sama tetap terbaca.
class OrdersPreset extends Notifier<({String? view, int n})> {
  @override
  ({String? view, int n}) build() => (view: null, n: 0);

  void open(String view) => state = (view: view, n: state.n + 1);
}

final ordersPresetProvider =
    NotifierProvider<OrdersPreset, ({String? view, int n})>(OrdersPreset.new);

const ordersViewLabel = {
  'inProgress': 'Sedang diproses',
  'ready': 'Siap diambil',
  'completedToday': 'Selesai hari ini',
  'unpaid': 'Belum lunas',
};