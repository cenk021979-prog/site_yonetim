import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';

/// Katılım başvurularının kapatılma (dismiss/consumed) durumunu yerel hafızada ([SharedPreferences]) saklar.
/// Bir başvuru onaylandığında veya reddedildiğinde sakin "Anladım" diyerek kartı kapattığında bir daha ekranda gösterilmez.
class JoinRequestTracker {
  static const String prefsKey = 'consumed_join_request_ids';
  static final Set<int> _memoryConsumed = <int>{};
  static bool _loaded = false;
  static Future<void>? _loadingFuture;

  static void ensureLoaded([void Function()? onUpdated]) {
    if (_loaded) return;
    _loadingFuture ??= _loadFromPrefs().then((changed) {
      if (changed && onUpdated != null) onUpdated();
    });
  }

  static Future<bool> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(prefsKey) ?? <String>[];
      final ids = list.map(int.tryParse).whereType<int>().toSet();
      final before = _memoryConsumed.length;
      _memoryConsumed.addAll(ids);
      _loaded = true;
      return _memoryConsumed.length != before;
    } catch (_) {
      _loaded = true;
      return false;
    }
  }

  static Future<Set<int>> loadConsumed() async {
    ensureLoaded();
    return _memoryConsumed;
  }

  static bool isConsumed(int id) {
    return _memoryConsumed.contains(id);
  }

  static Future<void> consume(int id) async {
    _memoryConsumed.add(id);
    unawaited(_persist());
  }

  static Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        prefsKey,
        _memoryConsumed.map((e) => e.toString()).toList(),
      );
    } catch (_) {}
  }

  static List<JoinRequestRecord> filterVisible(List<JoinRequestRecord> list) {
    if (_memoryConsumed.isEmpty) return list;
    return list.where((r) => !_memoryConsumed.contains(r.id)).toList();
  }
}
