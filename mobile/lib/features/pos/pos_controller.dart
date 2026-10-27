import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_error.dart';
import '../customers/customer_models.dart';
import '../orders/orders_repository.dart';
import 'pos_models.dart';
import 'pos_repository.dart';

/// Jumlah foto cucian saat diterima. Ubah kMinPhotos menjadi 0 jika foto tidak wajib.
const kMinPhotos = 1;
const kMaxPhotos = 6;

enum PayMode { later, deposit, full }

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

  CartLine copyWith({
    PosService? service,
    double? quantity,
    Set<int>? addonIds,
    String? notes,
  }) =>
      CartLine(
        uid: uid,
        service: service ?? this.service,
        quantity: quantity ?? this.quantity,
        addonIds: addonIds ?? this.addonIds,
        notes: notes ?? this.notes,
      );
}

class CreatedOrder {
  const CreatedOrder({
    required this.id,
    required this.orderNumber,
    required this.total,
  });

  final int id;
  final String orderNumber;
  final int total;
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
    this.photos = const [],
    this.payMode = PayMode.later,
    this.payMethod = 'CASH',
    this.deposit = 0,
    this.payNote = '',
    this.created,
    this.photosUploaded = 0,
    this.paymentDone = false,
    this.submitting = false,
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

  // Langkah 3 dan 4
  final List<String> photos; // lokasi file di HP, belum terunggah
  final PayMode payMode;
  final String payMethod;
  final int deposit;
  final String payNote;

  // Kemajuan penyimpanan
  final CreatedOrder? created;
  final int photosUploaded;
  final bool paymentDone;
  final bool submitting;

  /// Setelah pesanan dibuat di server, isian tidak boleh diubah lagi.
  bool get locked => created != null;

  bool get done =>
      created != null && paymentDone && photosUploaded >= photos.length;

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
    List<String>? photos,
    PayMode? payMode,
    String? payMethod,
    int? deposit,
    String? payNote,
    Object? created = _keep,
    int? photosUploaded,
    bool? paymentDone,
    bool? submitting,
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
        photos: photos ?? this.photos,
        payMode: payMode ?? this.payMode,
        payMethod: payMethod ?? this.payMethod,
        deposit: deposit ?? this.deposit,
        payNote: payNote ?? this.payNote,
        created: created == _keep ? this.created : created as CreatedOrder?,
        photosUploaded: photosUploaded ?? this.photosUploaded,
        paymentDone: paymentDone ?? this.paymentDone,
        submitting: submitting ?? this.submitting,
      );
}

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
      final s = state;
      final speedOk = cat.speeds.any((x) => x.id == s.speedId);
      final fulfOk = cat.fulfillments.any((x) => x.id == s.fulfillmentId);
      final needLine = s.lines.isEmpty && cat.services.isNotEmpty && !s.locked;

      state = s.copyWith(
        speedId: speedOk
            ? s.speedId
            : (cat.speeds.isEmpty ? null : cat.speeds.first.id),
        fulfillmentId: fulfOk
            ? s.fulfillmentId
            : (cat.fulfillments.isEmpty ? null : cat.fulfillments.first.id),
        lines: needLine
            ? [CartLine(uid: ++_uid, service: cat.services.first)]
            : s.lines,
      );
      if (!state.locked) _schedulePreview();
    } catch (_) {
      // Kesalahan katalog ditampilkan oleh layar.
    }
  }

  /// Mulai pesanan baru dari nol.
  Future<void> reset() async {
    _timer?.cancel();
    _req++;
    state = const PosState();
    await _applyDefaults();
  }

  // ---------------------------------------------------------- Isian pesanan

  void setCustomer(Customer c) {
    if (state.locked) return;
    state = state.copyWith(customer: c);
  }

  void addLine(PosService s) {
    if (state.locked) return;
    state = state.copyWith(
      lines: [...state.lines, CartLine(uid: ++_uid, service: s)],
    );
    _schedulePreview();
  }

  void changeService(int uid, PosService s) {
    if (state.locked) return;
    state = state.copyWith(
      lines: [
        for (final l in state.lines) l.uid == uid ? l.copyWith(service: s) : l,
      ],
    );
    _schedulePreview();
  }

  void removeLine(int uid) {
    if (state.locked) return;
    state = state.copyWith(
      lines: state.lines.where((l) => l.uid != uid).toList(),
    );
    _schedulePreview();
  }

  void updateLine(int uid, {double? quantity, Set<int>? addonIds, String? notes}) {
    if (state.locked) return;
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
    if (state.locked) return;
    state = state.copyWith(speedId: id);
    _schedulePreview();
  }

  void setFulfillment(int id) {
    if (state.locked) return;
    state = state.copyWith(fulfillmentId: id);
    _schedulePreview();
  }

  void setDiscount(int value) {
    if (state.locked) return;
    state = state.copyWith(discount: value);
    _schedulePreview();
  }

  void setNotes(String value) {
    if (state.locked) return;
    state = state.copyWith(notes: value);
  }

  // ------------------------------------------------------------------ Foto

  void addPhoto(String path) {
    if (state.locked || state.photos.length >= kMaxPhotos) return;
    state = state.copyWith(photos: [...state.photos, path]);
  }

  void removePhoto(int index) {
    if (state.locked || index < 0 || index >= state.photos.length) return;
    final list = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: list);
  }

  // ------------------------------------------------------------ Pembayaran

  void setPayMode(PayMode m) {
    if (state.paymentDone) return;
    state = state.copyWith(payMode: m);
  }

  void setPayMethod(String m) {
    if (state.paymentDone) return;
    state = state.copyWith(payMethod: m);
  }

  void setDeposit(int v) {
    if (state.paymentDone) return;
    state = state.copyWith(deposit: v);
  }

  void setPayNote(String v) {
    if (state.paymentDone) return;
    state = state.copyWith(payNote: v);
  }

  // --------------------------------------------------------- Pratinjau harga

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

  // ---------------------------------------------------------- Simpan pesanan

  String? _validate() {
    final s = state;
    if (s.customer == null) return 'Pilih pelanggan dulu.';
    if (s.lines.isEmpty) return 'Tambahkan minimal satu jenis cucian.';
    if (s.lines.any((l) => l.quantity <= 0)) {
      return 'Berat atau jumlah harus lebih dari 0.';
    }
    if (s.photos.length < kMinPhotos) {
      return 'Ambil minimal $kMinPhotos foto cucian.';
    }
    final total = s.preview?.total;
    if (total == null) return 'Harga belum terhitung. Periksa kembali layanan.';
    if (s.payMode == PayMode.deposit && (s.deposit <= 0 || s.deposit > total)) {
      return 'Uang muka harus lebih dari 0 dan tidak melebihi total.';
    }
    return null;
  }

  /// Menyimpan pesanan secara bertahap: buat pesanan, unggah foto, catat pembayaran.
  /// Aman dipanggil ulang: tahap yang sudah berhasil tidak diulang.
  /// Mengembalikan pesan error (bahasa Indonesia), atau null jika berhasil.
  Future<String?> submit() async {
    if (state.submitting) return null;

    if (state.created == null) {
      final problem = _validate();
      if (problem != null) return problem;
    }

    state = state.copyWith(submitting: true);
    try {
      // 1. Buat pesanan
      if (state.created == null) {
        final r = await ref.read(posRepositoryProvider).create(_input(withCustomer: true));
        state = state.copyWith(
          created: CreatedOrder(id: r.id, orderNumber: r.orderNumber, total: r.total),
        );
        ref.read(ordersRevisionProvider.notifier).bump();
      }
      final created = state.created!;

      // 2. Unggah foto satu per satu
      while (state.photosUploaded < state.photos.length) {
        await ref.read(posRepositoryProvider).uploadPhoto(
              created.id,
              state.photos[state.photosUploaded],
              'RECEIVED',
            );
        state = state.copyWith(photosUploaded: state.photosUploaded + 1);
      }

      // 3. Catat pembayaran
      if (!state.paymentDone) {
        final amount = switch (state.payMode) {
          PayMode.later => 0,
          PayMode.deposit => state.deposit,
          PayMode.full => created.total,
        };
        if (amount > 0) {
          await ref.read(ordersRepositoryProvider).pay(
                created.id,
                amount: amount,
                method: state.payMethod,
                note: state.payNote,
              );
          ref.read(ordersRevisionProvider.notifier).bump();
        }
        state = state.copyWith(paymentDone: true);
      }

      state = state.copyWith(submitting: false);
      return null;
    } catch (e) {
      state = state.copyWith(submitting: false);
      return errorMessage(e);
    }
  }
}

final posControllerProvider =
    NotifierProvider<PosController, PosState>(PosController.new);