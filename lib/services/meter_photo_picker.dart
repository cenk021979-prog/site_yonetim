import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef MeterPhotoFile = ({String name, String? path, Uint8List bytes});
typedef MeterPhotoPicker = Future<MeterPhotoFile?> Function();

/// Read only a user-selected image. No camera or directory permissions are requested.
Future<MeterPhotoFile?> pickMeterPhoto() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
  );
  if (file == null) return null;
  return readMeterPhotoFile(file);
}

/// Unknown picker lengths use a bounded stream; never decode an oversized file.
Future<MeterPhotoFile> readMeterPhotoFile(PlatformFile file) async {
  final length = await file.length();
  const max = 20 * 1024 * 1024;
  if (length != null && (length <= 0 || length > max)) {
    throw StateError('Fotoğraf en çok 20 MB olabilir.');
  }
  final buffer = BytesBuilder(copy: false);
  var size = 0;
  await for (final chunk in file.readAsByteStream()) {
    size += chunk.length;
    if (size > max) throw StateError('Fotoğraf en çok 20 MB olabilir.');
    buffer.add(chunk);
  }
  final bytes = buffer.takeBytes();
  if (bytes.isEmpty) throw StateError('Fotoğraf boş.');
  return (name: file.name, path: file.path, bytes: bytes);
}
