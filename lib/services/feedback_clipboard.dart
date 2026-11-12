// Yalnız açık geri bildirim formunun kullanıcı başlatımlı yapıştırması okunur.
import 'dart:typed_data';

import 'feedback_clipboard_native.dart'
    if (dart.library.js_interop) 'feedback_clipboard_web.dart'
    as platform;

typedef FeedbackClipboardImage = ({String name, Uint8List bytes});

abstract class FeedbackClipboard {
  factory FeedbackClipboard({
    required bool Function() enabled,
    required void Function(Future<List<FeedbackClipboardImage>>) onPaste,
  }) => platform.createFeedbackClipboard(enabled: enabled, onPaste: onPaste);

  /// Native keyboard/menu paste. Web uses the actual browser paste event.
  Future<List<FeedbackClipboardImage>> readImages();
  bool get usesBrowserPaste;
  void dispose();
}
