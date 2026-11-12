import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'feedback_clipboard.dart';

FeedbackClipboard createFeedbackClipboard({
  required bool Function() enabled,
  required void Function(Future<List<FeedbackClipboardImage>>) onPaste,
}) => _NativeFeedbackClipboard();

class _NativeFeedbackClipboard implements FeedbackClipboard {
  static const _channel = MethodChannel('site_kapi_kontrol/window');

  @override
  bool get usesBrowserPaste => false;

  @override
  Future<List<FeedbackClipboardImage>> readImages() async {
    if (defaultTargetPlatform != TargetPlatform.windows) return const [];
    final bytes = await _channel.invokeMethod<Uint8List>('readClipboardImage');
    if (bytes == null || bytes.isEmpty) return const [];
    return [(name: 'ekran-goruntusu.png', bytes: bytes)];
  }

  @override
  void dispose() {}
}
