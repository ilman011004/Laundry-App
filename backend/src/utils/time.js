// Zona waktu usaha: WIB = 7, WITA = 8, WIT = 9
const TZ_OFFSET_HOURS = 7;
const HOUR = 3600 * 1000;

function localParts(date) {
  const s = new Date(date.getTime() + TZ_OFFSET_HOURS * HOUR);
  return { y: s.getUTCFullYear(), m: s.getUTCMonth(), d: s.getUTCDate() };
}

// Awal hari (00:00 waktu lokal) sebagai objek Date UTC
function startOfDay(date = new Date()) {
  const { y, m, d } = localParts(date);
  return new Date(Date.UTC(y, m, d) - TZ_OFFSET_HOURS * HOUR);
}

function startOfMonth(date = new Date()) {
  const { y, m } = localParts(date);
  return new Date(Date.UTC(y, m, 1) - TZ_OFFSET_HOURS * HOUR);
}

function startOfNextMonth(date = new Date()) {
  const { y, m } = localParts(date);
  return new Date(Date.UTC(y, m + 1, 1) - TZ_OFFSET_HOURS * HOUR);
}

function addDays(date, n) {
  return new Date(date.getTime() + n * 24 * HOUR);
}

// "2026-10-24" (tanggal lokal) -> awal hari itu
function parseLocalDate(str) {
  const [y, m, d] = str.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d) - TZ_OFFSET_HOURS * HOUR);
}

// Date -> "YYYY-MM-DD" menurut tanggal lokal
function dayKey(date) {
  return new Date(date.getTime() + TZ_OFFSET_HOURS * HOUR).toISOString().slice(0, 10);
}

module.exports = {
  TZ_OFFSET_HOURS,
  startOfDay,
  startOfMonth,
  startOfNextMonth,
  addDays,
  parseLocalDate,
  dayKey,
};