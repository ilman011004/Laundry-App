import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../customers/customer_models.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

class CartLine {
  const CartLine({
    required this.uid,
    required this.service,
    this.quantity = 1,
    this.addonIds = const {},
    this.notes = '',
  });

  final int uid;
  final PosService service;
  final double quantity;
  final Set<int> addonIds;
  final String notes;

  CartLine copyWith({double? quantity, Set<int>? addonIds, String? notes}) =>
      CartLine(
        uid: uid,
        service: service,
        quantity: quantity ?? this.quantity,
        addonIds: addonIds ?? this.addonIds,
        notes: notes ?? this.notes,
      );
}

const _keep = Object();

class PosState {
  const PosState({
    this.customer,
    this.lines = const [],
    this.speedId,
    this.fulfillmentId,
    this.discount = 0,
    this.notes = '',
    this.preview,
    this.previewing = false,
    this.previewError,
    this.saving = false,
  });

  final Customer? customer;
  final List<CartLine> lines;
  final int? speedId;
  final int? fulfillmentId;
  final int discount;
  final String notes;
  final PricePreview? preview;
  final bool previewing;
  final String? previewError;
  final bool saving;

  PosState copyWith({
    Object? customer = _keep,
    List<CartLine>? lines,
    Object? speedId = _keep,
    Object? fulfillmentId = _keep,
    int? discount,
    String? notes,
    Object? preview = _keep,
    bool? previewing,
    Object? previewError = _keep,
    bool? saving,
  }) =>
      PosState(
        customer: customer == _keep ? this.customer : customer as Customer?,
        lines: lines ?? this.lines,
        speedId: speedId == _keep ? this.speedId : speedId as int?,
        fulfillmentId:
            fulfillmentId == _keep ? this.fulfillmentId : fulfillmentId as int?,
        discount: discount ?? this.discount,
        notes: notes ?? this.notes,
        preview: preview == _keep ? this.preview : preview as PricePreview?,
        previewing: previewing ?? this.previewing,
        previewError:
            previewError == _keep ? this.previewError : previewError as String?,
        saving: saving ?? this.saving,
      );
}

typedef SaveResult = ({String? error, String? orderNumber, int? total});

class PosController extends Notifier<PosState> {
  Timer? _timer;
  int _req = 0;
  int _uid = 0;

  @override
  PosState build() {
    ref.onDispose(() => _timer?.cancel());
    return const PosState();
  }

  /// Dipanggil saat layar dibuka: muat katalog terbaru dan pilih nilai awal.
  Future<void> start() async {
    ref.invalidate(catalogProvider);
    await _applyDefaults();
  }

  Future<void> _applyDefaults() async {
    try {
      final cat = await ref.read(catalogProvider.future);
      final speedOk = cat.speeds.any((s) => s.id == state.speedId);
      final fulfOk = cat.fulfillments.any((f) => f.id == state.fulfillmentId);
      state = state.copyWith(
        speedId: speedOk
            ? state.speedId
            : (cat.speeds.isEmpty ? null : cat.speeds.first.id),
        fulfillmentId: fulfOk
            ? state.fulfillmentId
            : (cat.fulfillments.isEmpty ? null : cat.fulfillments.first.id),
      );
      _schedulePreview();
    } catch (_) {
      // Kesalahan katalog ditampilkan oleh layar.
    }
  }

  void setCustomer(Customer c) => state = state.copyWith(customer: c);

  void addLine(PosService s) {
    state = state.copyWith(
      lines: [...state.lines, CartLine(uid: ++_uid, service: s)],
    );
    _schedulePreview();
  }

  void removeLine(int uid) {
    state = state.copyWith(
      lines: state.lines.where((l) => l.uid != uid).toList(),
    );
    _schedulePreview();
  }

  void updateLine(int uid, {double? quantity, Set<int>? addonIds, String? notes}) {
    state = state.copyWith(
      lines: [
        for (final l in state.lines)
          if (l.uid == uid)
            l.copyWith(quantity: quantity, addonIds: addonIds, notes: notes)
          else
            l,
      ],
    );
    if (quantity != null || addonIds != null) _schedulePreview();
  }

  void setSpeed(int id) {
    state = state.copyWith(speedId: id);
    _schedulePreview();
  }

  void setFulfillment(int id) {
    state = state.copyWith(fulfillmentId: id);
    _schedulePreview();
  }

  void setDiscount(int value) {
    state = state.copyWith(discount: value);
    _schedulePreview();
  }

  void setNotes(String value) => state = state.copyWith(notes: value);

  Map<String, dynamic> _input({bool withCustomer = false}) {
    final s = state;
    return {
      if (withCustomer && s.customer != null) 'customerId': s.customer!.id,
      'items': [
        for (final l in s.lines)
          {
            'serviceId': l.service.id,
            'quantity': l.quantity,
            if (l.addonIds.isNotEmpty) 'addonIds': l.addonIds.toList(),
            if (l.notes.trim().isNotEmpty) 'notes': l.notes.trim(),
          },
      ],
      if (s.speedId != null) 'speedId': s.speedId,
      if (s.fulfillmentId != null) 'fulfillmentId': s.fulfillmentId,
      'discount': s.discount,
      if (s.notes.trim().isNotEmpty) 'notes': s.notes.trim(),
    };
  }

  void _schedulePreview() {
    _timer?.cancel();
    final s = state;
    if (s.lines.isEmpty || s.lines.any((l) => l.quantity <= 0)) {
      _req++;
      state = s.copyWith(preview: null, previewing: false, previewError: null);
      return;
    }
    state = s.copyWith(previewing: true, previewError: null);
    _timer = Timer(const Duration(milliseconds: 400), _runPreview);
  }

  Future<void> _runPreview() async {
    final id = ++_req;
    try {
      final p = await ref.read(posRepositoryProvider).preview(_input());
      if (id != _req) return;
      state = state.copyWith(preview: p, previewing: false, previewError: null);
    } catch (e) {
      if (id != _req) return;
      state = state.copyWith(
        preview: null,
        previewing: false,
        previewError: errorMessage(e),
      );
    }
  }

  Future<SaveResult> save() async {
    final s = state;
    if (s.saving) return (error: null, orderNumber: null, total: null);
    if (s.customer == null) {
      return (error: 'Pilih pelanggan dulu.', orderNumber: null, total: null);
    }
    if (s.lines.isEmpty) {
      return (error: 'Tambahkan minimal satu layanan.', orderNumber: null, total: null);
    }
    if (s.lines.any((l) => l.quantity <= 0)) {
      return (error: 'Berat atau jumlah harus lebih dari 0.', orderNumber: null, total: null);
    }

    state = s.copyWith(saving: true);
    try {
      final r = await ref
          .read(posRepositoryProvider)
          .create(_input(withCustomer: true));
      _timer?.cancel();
      _req++;
      state = const PosState();
      await _applyDefaults();
      return (error: null, orderNumber: r.orderNumber, total: r.total);
    } catch (e) {
      state = state.copyWith(saving: false);
      return (error: errorMessage(e), orderNumber: null, total: null);
    }
  }
}

final posControllerProvider =
    NotifierProvider<PosController, PosState>(PosController.new);