import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/interface_mode.dart';
import 'package:site_kapi_kontrol/services/interface_mode_service.dart';

class _Store implements InterfaceModeStore {
  final reads = <int, Completer<String?>>{};
  final writes = <(int, String)>[];
  Completer<void>? writeGate;
  bool failWrites = false;
  @override
  Future<String?> read(int accountId) => (reads[accountId] ??= Completer<String?>()).future;
  @override
  Future<void> write(int accountId, String mode) async {
    writes.add((accountId, mode));
    await writeGate?.future;
    if (failWrites) throw StateError('store unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('default classic; account preferences persist independently', () async {
    SharedPreferences.setMockInitialValues({'app_easy_view': true});
    final service = InterfaceModeService();
    addTearDown(service.dispose);
    expect(service.mode, InterfaceMode.classic);
    await service.setAccount(1);
    await service.setMode(InterfaceMode.simple);
    await service.setAccount(2);
    expect(service.mode, InterfaceMode.classic);
    await service.setAccount(1);
    expect(service.mode, InterfaceMode.simple);
    await service.setMode(InterfaceMode.classic);
    final restarted = InterfaceModeService();
    addTearDown(restarted.dispose);
    await restarted.setAccount(1);
    expect(restarted.mode, InterfaceMode.classic);
    expect((await SharedPreferences.getInstance()).getString(DeviceInterfaceModeStore.key(2)), isNull);
    expect((await SharedPreferences.getInstance()).getBool('app_easy_view'), isTrue, reason: 'accessibility preference is independent from Classic/Sade');
  });
  test('late account A read never changes account B', () async {
    final store = _Store();
    final service = InterfaceModeService(store: store);
    addTearDown(service.dispose);
    final a = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    final b = service.setAccount(2);
    await Future<void>.delayed(Duration.zero);
    store.reads[2]!.complete('classic');
    await b;
    store.reads[1]!.complete('simple');
    await a;
    expect(service.accountId, 2);
    expect(service.mode, InterfaceMode.classic);
  });
  test('explicit choice wins while preference read is pending', () async {
    final store = _Store();
    final service = InterfaceModeService(store: store);
    addTearDown(service.dispose);
    final load = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    await service.setMode(InterfaceMode.simple);
    store.reads[1]!.complete('classic');
    await load;
    expect(service.mode, InterfaceMode.simple);
  });
  test('queued writes retain original account and latest same-account choice', () async {
    final store = _Store()..writeGate = Completer<void>();
    final service = InterfaceModeService(store: store);
    addTearDown(service.dispose);
    final a = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    store.reads[1]!.complete(null);
    await a;
    final first = service.setMode(InterfaceMode.simple);
    final second = service.setMode(InterfaceMode.classic);
    final b = service.setAccount(2);
    await Future<void>.delayed(Duration.zero);
    expect(store.reads[2], isNull, reason: 'wait for the captured pending writes');
    store.writeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    store.reads[2]!.complete(null);
    await b;
    final third = service.setMode(InterfaceMode.simple);
    await Future.wait([first, second, third]);
    expect(store.writes, [(1, 'simple'), (1, 'classic'), (2, 'simple')]);
    expect(service.accountId, 2);
    expect(service.mode, InterfaceMode.simple);
  });
  test('returning to A waits for its pending save before reading A again', () async {
    final store = _Store();
    final service = InterfaceModeService(store: store);
    addTearDown(service.dispose);
    final initial = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    store.reads[1]!.complete('classic');
    await initial;
    store.reads.remove(1);
    store.writeGate = Completer<void>();
    final save = service.setMode(InterfaceMode.simple);
    final b = service.setAccount(2);
    final a = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    expect(store.reads[1], isNull, reason: 'reading old Classic before the save would lose the visible choice');
    store.writeGate!.complete();
    await Future<void>.delayed(Duration.zero);
    store.reads[1]!.complete(store.writes.last.$2);
    await Future.wait([save, b, a]);
    expect(service.accountId, 1);
    expect(service.mode, InterfaceMode.simple);
  });
  test('dispose and logout invalidate outstanding load', () async {
    final store = _Store();
    final service = InterfaceModeService(store: store);
    final a = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    await service.setAccount(null);
    service.dispose();
    store.reads[1]!.complete('simple');
    await a;
    expect(service.mode, InterfaceMode.classic);
  });
  test('failed persistence is disclosed only for the current account', () async {
    final store = _Store()..failWrites = true;
    final service = InterfaceModeService(store: store);
    addTearDown(service.dispose);
    final a = service.setAccount(1);
    await Future<void>.delayed(Duration.zero);
    store.reads[1]!.complete(null);
    await a;
    await service.setMode(InterfaceMode.simple);
    expect(service.mode, InterfaceMode.simple);
    expect(service.persistenceFailed, isTrue);
    final b = service.setAccount(2);
    await Future<void>.delayed(Duration.zero);
    store.reads[2]!.complete(null);
    await b;
    expect(service.persistenceFailed, isFalse);
    expect(service.mode, InterfaceMode.classic);
  });
}
