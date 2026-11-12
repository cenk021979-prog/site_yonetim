import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/interface_mode.dart';

abstract class InterfaceModeStore {
  Future<String?> read(int accountId);
  Future<void> write(int accountId, String mode);
}

class DeviceInterfaceModeStore implements InterfaceModeStore {
  static String key(int accountId) => 'app_interface_mode_account_$accountId';
  @override
  Future<String?> read(int accountId) async => (await SharedPreferences.getInstance()).getString(key(accountId));
  @override
  Future<void> write(int accountId, String mode) async {
    final saved = await (await SharedPreferences.getInstance()).setString(key(accountId), mode);
    if (!saved) throw StateError('Preference was not stored');
  }
}

/// Presentation only. Each account has a separate preference on this device.
class InterfaceModeService extends ChangeNotifier {
  InterfaceModeService({InterfaceModeStore? store}) : _store = store ?? DeviceInterfaceModeStore();
  final InterfaceModeStore _store;
  int? _accountId;
  int _generation = 0;
  bool _disposed = false;
  bool _persistenceFailed = false;
  InterfaceMode _mode = InterfaceMode.classic;
  Future<void> _writes = Future<void>.value();
  InterfaceMode get mode => _mode;
  int? get accountId => _accountId;
  bool get persistenceFailed => _persistenceFailed;

  Future<void> setAccount(int? accountId) async {
    if (_accountId == accountId) return;
    _accountId = accountId;
    final generation = ++_generation;
    _mode = InterfaceMode.classic;
    _persistenceFailed = false;
    notifyListeners();
    if (accountId == null) return;
    try {
      // Re-entering an account must observe its still-pending earlier save.
      await _writes;
      if (_disposed || generation != _generation) return;
      final stored = await _store.read(accountId);
      if (_disposed || generation != _generation) return;
      _mode = stored == 'simple' ? InterfaceMode.simple : InterfaceMode.classic;
      notifyListeners();
    } catch (_) {
      // Storage failure leaves this account in the safe default.
    }
  }

  Future<void> setMode(InterfaceMode mode) async {
    final accountId = _accountId;
    if (_disposed || accountId == null) return;
    final generation = ++_generation; // A user's choice wins over an older pending load.
    _mode = mode;
    _persistenceFailed = false;
    notifyListeners();
    // Capture the account and serialize writes; a late write cannot target the
    // next account or overwrite a newer choice for the same account.
    _writes = _writes.then((_) async {
      try {
        await _store.write(accountId, mode.name);
      } catch (_) {
        if (!_disposed && _accountId == accountId && _generation == generation) {
          _persistenceFailed = true;
          notifyListeners();
        }
      }
    });
    await _writes;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    super.dispose();
  }
}
