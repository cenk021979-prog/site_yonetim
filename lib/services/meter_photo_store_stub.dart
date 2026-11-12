import 'dart:typed_data';

Future<void> putMeterPhoto(String key, Uint8List bytes) =>
    Future<void>.error(UnsupportedError('Tarayıcı deposu kullanılamıyor.'));
Future<Uint8List?> getMeterPhoto(String key) async => null;
Future<void> deleteMeterPhoto(String key) async {}
Future<List<String>> meterPhotoKeys(String prefix) async => const [];
