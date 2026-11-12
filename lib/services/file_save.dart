import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;

typedef SaveFileBytes =
    Future<Uri?> Function({
      required String fileName,
      required Uint8List bytes,
      required String mimeType,
    });

/// Download/save is separate from explicit sharing. On the web the default
/// FilePicker mode starts a Blob download (without Web Share or a popup).
bool get platformUsesFileSave =>
    kIsWeb ||
    switch (defaultTargetPlatform) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };

Future<Uri?> saveFileBytes({
  required String fileName,
  required Uint8List bytes,
  required String mimeType,
}) => FilePicker.saveFile(fileName: fileName, bytes: bytes, mimeType: mimeType);
