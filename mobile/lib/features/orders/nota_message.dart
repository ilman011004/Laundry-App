import '../../core/format.dart';
import '../pos/pos_models.dart' show formatQty;
import 'order_models.dart';

/// Teks nota yang dikirim ke WhatsApp pelanggan.
String buildNotaMessage(
  OrderDetail o, {
  required String businessName,
  String phone = '',
  String address = '',
}) {
  final b = StringBuffer();
  b.writeln('*$businessName*');
  b.writeln('Halo ${o.customerName}, terima kasih sudah mempercayakan cucian Anda kepada kami.');
  b.writeln();
  b.writeln('No. order: ${o.orderNumber}');
  b.writeln('Masuk: ${formatDateTime(o.receivedAt)}');
  if (o.estimatedDoneAt != null) {
    b.writeln('Estimasi selesai: ${formatDateTime(o.estimatedDoneAt!)}');
  }
  b.writeln();
  b.writeln('Rincian:');
  for (final it in o.items) {
    b.writeln(
      '- ${it.serviceName} ${formatQty(it.quantity)} ${it.unit}: '
      '${formatRupiah(it.lineTotal - it.addonsTotal)}',
    );
    for (final a in it.addons) {
      b.writeln('  + ${a.name}: ${formatRupiah(a.amount)}');
    }
  }
  if (o.speedFee > 0) {
    b.writeln('Kecepatan${o.speedName == null ? '' : ' (${o.speedName})'}: ${formatRupiah(o.speedFee)}');
  }
  if (o.deliveryFee > 0) {
    b.writeln('${o.fulfillmentName ?? 'Antar/jemput'}: ${formatRupiah(o.deliveryFee)}');
  }
  if (o.discount > 0) {
    b.writeln('Diskon: -${formatRupiah(o.discount)}');
  }
  b.writeln();
  b.writeln('*Total: ${formatRupiah(o.total)}*');
  b.writeln('Dibayar: ${formatRupiah(o.paidAmount)}');
  if (o.remaining > 0) {
    b.writeln('Sisa pembayaran: ${formatRupiah(o.remaining)}');
  } else {
    b.writeln('Status: Lunas');
  }
  b.writeln();
  b.writeln('Kami akan mengabari Anda lagi saat cucian siap diambil.');
  if (phone.isNotEmpty || address.isNotEmpty) {
    b.writeln();
    if (address.isNotEmpty) b.writeln(address);
    if (phone.isNotEmpty) b.writeln('Telp/WA: $phone');
  }
  return b.toString().trim();
}