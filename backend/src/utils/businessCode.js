const crypto = require('crypto');

// Tanpa huruf dan angka yang mirip (0, O, 1, I) supaya mudah dibaca dan diketik
const ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

function generateBusinessCode(length = 6) {
  const bytes = crypto.randomBytes(length);
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join('');
}

module.exports = { generateBusinessCode };