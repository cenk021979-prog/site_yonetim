// IndexedDB is origin-local, never uploaded without the reading's explicit confirmation.
// A successful request is not enough: wait for the transaction to commit.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('indexedDB')
external _Factory get _factory;
extension type _Factory(JSObject _) implements JSObject {
  external _OpenRequest open(String name, int version);
}
extension type _Request(JSObject _) implements JSObject {
  external JSAny? get result;
  external set onsuccess(JSFunction callback);
  external set onerror(JSFunction callback);
}
extension type _OpenRequest(JSObject _) implements JSObject {
  external _Database get result;
  external set onupgradeneeded(JSFunction callback);
  external set onsuccess(JSFunction callback);
  external set onerror(JSFunction callback);
  external set onblocked(JSFunction callback);
}
extension type _Database(JSObject _) implements JSObject {
  external _Store createObjectStore(String name);
  external _Transaction transaction(String name, String mode);
  external void close();
}
extension type _Transaction(JSObject _) implements JSObject {
  external _Store objectStore(String name);
  external set oncomplete(JSFunction callback);
  external set onerror(JSFunction callback);
  external set onabort(JSFunction callback);
}
extension type _Store(JSObject _) implements JSObject {
  external _Request put(JSAny value, JSAny key);
  external _Request get(JSAny key);
  external _Request delete(JSAny key);
  external _Request getAllKeys();
}

Future<_Database> _open() {
  final ready = Completer<_Database>();
  final request = _factory.open('site_meter_photos_v1', 1);
  void fail() {
    if (!ready.isCompleted) ready.completeError(StateError('Fotoğraf cihazda saklanamadı. Tarayıcı depolamasını kontrol edin.'));
  }
  request.onupgradeneeded = (() => request.result.createObjectStore('photos')).toJS;
  request.onsuccess = (() {
    if (ready.isCompleted) { request.result.close(); } else { ready.complete(request.result); }
  }).toJS;
  request.onerror = fail.toJS;
  request.onblocked = fail.toJS;
  return ready.future;
}

Future<JSAny?> _run(String mode, _Request Function(_Store store) action) async {
  final db = await _open();
  try {
    final done = Completer<JSAny?>();
    final transaction = db.transaction('photos', mode);
    JSAny? value;
    void fail() {
      if (!done.isCompleted) done.completeError(StateError('Fotoğraf deposu işlemi tamamlanamadı.'));
    }
    transaction.oncomplete = (() { if (!done.isCompleted) done.complete(value); }).toJS;
    transaction.onerror = fail.toJS;
    transaction.onabort = fail.toJS;
    final request = action(transaction.objectStore('photos'));
    request.onsuccess = (() { value = request.result; }).toJS;
    request.onerror = fail.toJS;
    return await done.future;
  } finally {
    db.close();
  }
}

Future<void> putMeterPhoto(String key, Uint8List bytes) async {
  await _run('readwrite', (store) => store.put(bytes.toJS, key.toJS));
}
Future<Uint8List?> getMeterPhoto(String key) async {
  final raw = await _run('readonly', (store) => store.get(key.toJS));
  return raw == null ? null : (raw as JSUint8Array).toDart;
}
Future<void> deleteMeterPhoto(String key) async {
  await _run('readwrite', (store) => store.delete(key.toJS));
}
Future<List<String>> meterPhotoKeys(String prefix) async {
  final raw = await _run('readonly', (store) => store.getAllKeys());
  if (raw == null) return const [];
  return (raw as JSArray<JSString>).toDart.map((key) => key.toDart).where((key) => key.startsWith(prefix)).toList();
}
