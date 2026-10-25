import 'package:intl/intl.dart';
import 'config.dart';

final _rupiah = NumberFormat.currency(
  locale: 'id_ID',
  symbol: 'Rp ',
  decimalDigits: 0,
);

/// 76000 -> "Rp 76.000"
String formatRupiah(num value) => _rupiah.format(value);

/// Ubah waktu dari API (UTC) menjadi waktu lokal usaha.
DateTime toBusinessTime(DateTime utc) =>
    utc.toUtc().add(const Duration(hours: AppConfig.tzOffsetHours));

/// "24 Okt 2026"
String formatDate(DateTime utc) =>
    DateFormat('d MMM y', 'id_ID').format(toBusinessTime(utc));

/// "24 Okt 2026, 13.45"
String formatDateTime(DateTime utc) =>
    DateFormat('d MMM y, HH.mm', 'id_ID').format(toBusinessTime(utc));

/// Parse teks tanggal dari API ("2026-10-24T06:21:28.811Z"); null jika kosong.
DateTime? parseApiDate(String? text) =>
    text == null ? null : DateTime.parse(text);