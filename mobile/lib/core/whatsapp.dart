import 'package:url_launcher/url_launcher.dart';

/// "0812-3456-789" atau "+62 812 3456 789" menjadi "628123456789".
/// Mengembalikan null jika nomor tidak valid.
String? normalizePhoneForWhatsApp(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('0')) {
    d = '62${d.substring(1)}';
  } else if (d.startsWith('8')) {
    d = '62$d';
  }
  return d.length >= 10 ? d : null;
}

/// Membuka WhatsApp dengan pesan yang sudah terisi. Kasir tinggal menekan kirim.
/// Mengembalikan false jika WhatsApp gagal dibuka atau nomor tidak valid.
Future<bool> openWhatsApp(String rawPhone, String message) async {
  final phone = normalizePhoneForWhatsApp(rawPhone);
  if (phone == null) return false;

  final uri = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}