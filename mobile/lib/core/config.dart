/// Base URL of the Tehzeeb POS API (including `/api`), injected at build time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5050/api
/// Default targets the Android emulator's alias for the host machine's backend.
/// Production builds must pass the HTTPS VPS URL.
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5050/api',
  );
}
