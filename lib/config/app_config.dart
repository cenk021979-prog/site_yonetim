const String _defaultApiBaseUrl = 'https://api.gudeteknoloji.com.tr';

class AppConfig {
  AppConfig._();

  static const String appName = 'Site ve Toplu Yaşam Yönetim Sistemi';
  static const String appVersion = '1.0.0';
  static const int buildNumber = 1;

  /// Geçici sayfa bağlantıları; mevcut kalıcı geri bildirim menüsü korunur.
  static const bool temporaryFeedbackLinks = bool.fromEnvironment(
    'TEMP_FEEDBACK_LINKS',
    defaultValue: true,
  );

  /// Can be overridden at build-time via `--dart-define=API_BASE_URL=https://...`
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _defaultApiBaseUrl,
  );

  static String get versionDisplay => 'v$appVersion (Build $buildNumber)';
}

/// Backwards compatibility top-level alias
const String apiBaseUrl = AppConfig.baseUrl;
