import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kullanıcının tema tercihi: aydınlık (varsayılan) / karanlık / sistem.
///
/// - Varsayılan [ThemeMode.light]: tercih hiç yapılmadıysa uygulama ilk açılışta aydınlık temada açılır.
/// - Tercih cihazda (SharedPreferences, [storageKey]) saklanır; bozuk/bilinmeyen değer aydınlık temaya döner.
/// - Depolama hatası uygulamayı bozmaz: tercih bellekte geçerli kalır, yalnız kalıcı olmaz.
class ThemeService extends ChangeNotifier {
  ThemeService();

  /// SharedPreferences anahtarı (değerler: `light`, `dark`; yok/başka = aydınlık).
  static const String storageKey = 'app_theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  /// Kayıtlı tercihi okur (uygulama açılışında bir kez). Değişiklik varsa dinleyicileri bilgilendirir.
  Future<void> load() async {
    ThemeMode loaded = ThemeMode.light;
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = _parse(prefs.getString(storageKey));
    } catch (_) {
      // Depolama okunamadı: aydınlık tema.
    }
    if (loaded != _mode) {
      _mode = loaded;
      notifyListeners();
    }
  }

  /// Tercihi ayarlar ve saklar. Aynı değer yeniden bildirilmez.
  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) {
      return;
    }
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, _serialize(mode));
    } catch (_) {
      // Kalıcılık en iyi çabadır; tercih bu oturum için geçerli.
    }
  }

  /// Düğme davranışı: [effective] ekranda GÖRÜNEN temadır (sistem modunda da). Koyuysa aydınlığa, aksi
  /// hâlde karanlığa geçilir; böylece düğme her zaman görünenin tersini seçer.
  Future<void> toggle(Brightness effective) {
    return setMode(effective == Brightness.dark ? ThemeMode.light : ThemeMode.dark);
  }

  static ThemeMode _parse(String? raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      default:
        return ThemeMode.light;
    }
  }

  static String _serialize(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }
}
