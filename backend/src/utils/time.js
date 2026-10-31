// Zona waktu usaha. Indonesia tidak memakai jam musim panas, jadi selisih jamnya tetap.
const HOUR = 3600 * 1000;

const ZONES = {
  'Asia/Jakarta': 7, // WIB
  'Asia/Makassar': 8, // WITA
  'Asia/Jayapura': 9, // WIT
};
const ALIASES = {
  'Asia/Pontianak': 'Asia/Jakarta',
  'Asia/Ujung_Pandang': 'Asia/Makassar',
};
const DEFAULT_TIMEZONE = 'Asia/Jakarta';

// Dipertahankan agar kode lama yang belum diubah tetap jalan
const TZ_OFFSET_HOURS = ZONES[DEFAULT_TIMEZONE];

// Nilai yang tidak dikenal (atau dikirim sembarangan) jatuh ke zona bawaan
function normalizeTimezone(tz) {
  const name = Object.hasOwn(ALIASES, tz) ? ALIASES[tz] : tz;
  return Object.hasOwn(ZONES, name) ? name : DEFAULT_TIMEZONE;
}

function offsetOf(tz) {
  return ZONES[normalizeTimezone(tz)];
}

function localParts(date, tz) {
  const s = new Date(date.getTime() + offsetOf(tz) * HOUR);
  return { y: s.getUTCFullYear(), m: s.getUTCMonth(), d: s.getUTCDate() };
}

// Awal hari (00:00 waktu lokal usaha) sebagai objek Date UTC
function startOfDay(date = new Date(), tz) {
  const { y, m, d } = localParts(date, tz);
  return new Date(Date.UTC(y, m, d) - offsetOf(tz) * HOUR);
}

function startOfMonth(date = new Date(), tz) {
  const { y, m } = localParts(date, tz);
  return new Date(Date.UTC(y, m, 1) - offsetOf(tz) * HOUR);
}

function startOfNextMonth(date = new Date(), tz) {
  const { y, m } = localParts(date, tz);
  return new Date(Date.UTC(y, m + 1, 1) - offsetOf(tz) * HOUR);
}

function addDays(date, n) {
  return new Date(date.getTime() + n * 24 * HOUR);
}

// "2026-10-24" (tanggal lokal) -> awal hari itu
function parseLocalDate(str, tz) {
  const [y, m, d] = str.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d) - offsetOf(tz) * HOUR);
}

// Date -> "YYYY-MM-DD" menurut tanggal lokal usaha
function dayKey(date, tz) {
  return new Date(date.getTime() + offsetOf(tz) * HOUR).toISOString().slice(0, 10);
}

module.exports = {
  DEFAULT_TIMEZONE,
  TZ_OFFSET_HOURS,
  normalizeTimezone,
  startOfDay,
  startOfMonth,
  startOfNextMonth,
  addDays,
  parseLocalDate,
  dayKey,
};