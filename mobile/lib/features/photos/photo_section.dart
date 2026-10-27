import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/api_error.dart';
import '../../core/format.dart';
import '../../core/whatsapp.dart';
import '../deliveries/deliveries_repository.dart';
import '../deliveries/delivery_models.dart';
import '../orders/order_models.dart';
import '../settings/business_repository.dart';
import 'photo_models.dart';
import 'photos_repository.dart';

const _maxPerKind = 10; // sama dengan batas di backend

/// Pesan WhatsApp: cucian sudah siap. Isinya mengikuti cara penerimaan pesanan.
/// [dropoff] adalah jadwal antar yang masih aktif (boleh null).
String _buildReadyMessage(
  OrderDetail o, {
  required String businessName,
  Delivery? dropoff,
  String phone = '',
  String address = '',
}) {
  final b = StringBuffer();
  final method = o.receiveMethod;
  final delivered = method == 'DELIVERY' || method == 'PICKUP_DELIVERY';

  b.writeln('*$businessName*');
  b.writeln('Halo ${o.customerName}, cucian Anda dengan No. order ${o.orderNumber} '
      'sudah selesai${delivered ? '.' : ' dan siap diambil.'}');
  b.writeln();
  if (o.remaining > 0) {
    b.writeln('Total: ${formatRupiah(o.total)}');
    b.writeln('Sisa pembayaran: ${formatRupiah(o.remaining)}');
  } else {
    b.writeln('Status pembayaran: Lunas');
  }
  b.writeln();

  if (method == 'SELF_PICKUP') {
    b.writeln('Silakan diambil di tempat kami.');
  } else if (delivered) {
    if (dropoff?.scheduledAt != null) {
      b.writeln('Cucian akan kami antar pada ${formatDateTime(dropoff!.scheduledAt!)}.');
    } else {
      b.writeln('Cucian akan kami antar. Jadwal pengantaran akan kami kabari.');
    }
    final addr = dropoff?.addressSnapshot;
    if (addr != null && addr.isNotEmpty) b.writeln('Alamat: $addr');
    if (o.remaining > 0) {
      b.writeln('Mohon siapkan pembayaran sisa tagihan saat cucian tiba.');
    }
  }

  b.writeln('Terima kasih sudah mempercayakan cucian Anda kepada kami.');
  if (phone.isNotEmpty || address.isNotEmpty) {
    b.writeln();
    if (address.isNotEmpty) b.writeln(address);
    if (phone.isNotEmpty) b.writeln('Telp/WA: $phone');
  }
  return b.toString().trim();
}

class PhotoSection extends ConsumerStatefulWidget {
  const PhotoSection({super.key, required this.order});

  final OrderDetail order;

  @override
  ConsumerState<PhotoSection> createState() => _PhotoSectionState();
}

class _PhotoSectionState extends ConsumerState<PhotoSection> {
  final _picker = ImagePicker();
  bool _busy = false;

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add(String kind) async {
    if (_busy) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Ambil foto'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Dari galeri'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    setState(() => _busy = true);
    try {
      final x = await _picker.pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 80,
      );
      if (x != null) {
        await ref
            .read(photosRepositoryProvider)
            .upload(widget.order.id, x.path, kind);
        ref.invalidate(orderPhotosProvider(widget.order.id));
        if (mounted) _snack('Foto tersimpan');
      }
    } catch (e) {
      if (mounted) _snack(errorMessage(e));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _notifyReady() async {
    final biz = ref.read(businessProvider).asData?.value;

    // Ambil jadwal antar yang masih aktif. Jika gagal dimuat, pesan tetap terkirim tanpa jadwal.
    Delivery? dropoff;
    try {
      final list = await ref.read(deliveriesProvider(widget.order.id).future);
      for (final d in list) {
        if (d.type == 'DROPOFF' && d.isActive) {
          dropoff = d;
          break;
        }
      }
    } catch (_) {}

    final msg = _buildReadyMessage(
      widget.order,
      businessName: biz?.name ?? 'Laundry',
      dropoff: dropoff,
      phone: biz?.phone ?? '',
      address: biz?.address ?? '',
    );
    final ok = await openWhatsApp(widget.order.customerPhone, msg);
    if (!mounted) return;
    if (!ok) {
      _snack('Tidak bisa membuka WhatsApp. Periksa nomor HP pelanggan.');
    }
  }

  void _open(List<OrderPhoto> all, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => _PhotoViewer(photos: all, initial: index)),
    );
  }

  Widget _group(String kind, List<OrderPhoto> all) {
    final items = all.where((p) => p.kind == kind).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(photoKindLabel[kind]!, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in items)
                InkWell(
                  onTap: () => _open(all, all.indexOf(p)),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(width: 88, height: 88, child: _Thumb(photoId: p.id)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final async = ref.watch(orderPhotosProvider(o.id));
    ref.watch(businessProvider); // dimuat lebih dulu untuk pesan WhatsApp

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Foto cucian', style: Theme.of(context).textTheme.titleMedium),
              async.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Foto gagal dimuat. ${errorMessage(e)}',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    TextButton(
                      onPressed: () => ref.invalidate(orderPhotosProvider(o.id)),
                      child: const Text('Coba lagi'),
                    ),
                  ],
                ),
                data: (all) {
                  final readyCount = all.where((p) => p.kind == 'READY').length;
                  final isReady = o.workStatus == 'READY';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (all.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Belum ada foto.'),
                        ),
                      _group('RECEIVED', all),
                      _group('READY', all),

                      // Belum siap: hanya petunjuk
                      if (!isReady && !o.isCancelled && !o.isCompleted)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Foto siap diambil dan konfirmasi ke pelanggan bisa dilakukan '
                            'setelah status pesanan menjadi Siap.',
                          ),
                        ),

                      // Status Siap: foto dan konfirmasi
                      if (isReady) ...[
                        if (readyCount < _maxPerKind) ...[
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _add('READY'),
                              icon: _busy
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add_a_photo_outlined),
                              label: const Text('Tambah foto siap diambil'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: _busy ? null : _notifyReady,
                            icon: const Icon(Icons.send),
                            label: const Text('Kabari pelanggan via WhatsApp'),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Isi pesan menyesuaikan cara penerimaan pesanan (ambil sendiri atau antar). '
                          'WhatsApp tidak bisa menerima foto otomatis dari aplikasi, '
                          'jadi foto dikirim manual dari galeri jika diperlukan.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({required this.photoId});

  final int photoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(photoBytesProvider(photoId));
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (_, _) => InkWell(
        onTap: () => ref.invalidate(photoBytesProvider(photoId)),
        child: const Center(child: Icon(Icons.broken_image_outlined)),
      ),
      data: (bytes) => Image.memory(bytes, fit: BoxFit.cover, cacheWidth: 300),
    );
  }
}

class _PhotoViewer extends ConsumerStatefulWidget {
  const _PhotoViewer({required this.photos, required this.initial});

  final List<OrderPhoto> photos;
  final int initial;

  @override
  ConsumerState<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends ConsumerState<_PhotoViewer> {
  late final PageController _page = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.photos[_index];
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${photoKindLabel[current.kind]} (${_index + 1}/${widget.photos.length})'),
      ),
      body: PageView.builder(
        controller: _page,
        itemCount: widget.photos.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (_, i) {
          final async = ref.watch(photoBytesProvider(widget.photos[i].id));
          return async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Text(errorMessage(e), style: const TextStyle(color: Colors.white)),
            ),
            data: (bytes) => InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.memory(bytes)),
            ),
          );
        },
      ),
    );
  }
}