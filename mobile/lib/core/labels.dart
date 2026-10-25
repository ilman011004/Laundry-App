// Kode dari API tetap berbahasa Inggris; yang tampil ke pengguna bahasa Indonesia.

const workStatusLabel = {
  'RECEIVED': 'Diterima',
  'WASHING': 'Dicuci',
  'DRYING': 'Dikeringkan',
  'IRONING': 'Disetrika',
  'READY': 'Siap diambil/diantar',
  'COMPLETED': 'Selesai',
  'CANCELLED': 'Dibatalkan',
};

const paymentStatusLabel = {
  'UNPAID': 'Belum bayar',
  'PARTIAL': 'Belum lunas',
  'PAID': 'Lunas',
};

const paymentMethodLabel = {
  'CASH': 'Tunai',
  'TRANSFER': 'Transfer',
  'QRIS': 'QRIS',
};

const receiveMethodLabel = {
  'SELF_PICKUP': 'Ambil sendiri',
  'DELIVERY': 'Diantar',
  'PICKUP_DELIVERY': 'Jemput dan antar',
};

const deliveryTypeLabel = {
  'PICKUP': 'Jemput',
  'DROPOFF': 'Antar',
};

const deliveryStatusLabel = {
  'SCHEDULED': 'Terjadwal',
  'ON_THE_WAY': 'Dalam perjalanan',
  'DONE': 'Selesai',
  'CANCELLED': 'Dibatalkan',
};

const roleLabel = {
  'OWNER': 'Pemilik',
  'CASHIER': 'Kasir',
};

/// Ambil label; jika kode tidak dikenal, tampilkan kodenya apa adanya.
String labelOf(Map<String, String> map, String? code) {
  if (code == null) return '-';
  return map[code] ?? code;
}