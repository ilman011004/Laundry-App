class AppConfig {
  /// Emulator Android: http://10.0.2.2:3000
  /// HP lewat USB: jalankan dengan --dart-define=API_BASE_URL=http://localhost:3000
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:3000',
  );

  /// Zona waktu usaha (WIB = 7, WITA = 8, WIT = 9).
  /// Samakan dengan TZ_OFFSET_HOURS di backend (src/utils/time.js).
  static const int tzOffsetHours = 7;
}