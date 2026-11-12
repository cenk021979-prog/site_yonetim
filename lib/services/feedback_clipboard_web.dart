// Browser paste is user initiated; no background clipboard read or permission prompt.
import 'dart:js_interop';

import 'feedback_clipboard.dart';

@JS('document')
external _PasteDocument get _document;

extension type _PasteDocument(JSObject _) implements JSObject {
  external void addEventListener(
    String type,
    JSFunction listener,
    bool capture,
  );
  external void removeEventListener(
    String type,
    JSFunction listener,
    bool capture,
  );
}

extension type _PasteEvent(JSObject _) implements JSObject {
  external _PasteData? get clipboardData;
  external void preventDefault();
}

extension type _PasteData(JSObject _) implements JSObject {
  external _PasteFiles get files;
}

extension type _PasteFiles(JSObject _) implements JSObject {
  external int get length;
  external _PasteFile? item(int index);
}

extension type _PasteFile(JSObject _) implements JSObject {
  external String get type;
  external String get name;
  external int get size;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

FeedbackClipboard createFeedbackClipboard({
  required bool Function() enabled,
  required void Function(Future<List<FeedbackClipboardImage>>) onPaste,
}) => _WebFeedbackClipboard(enabled, onPaste);

class _WebFeedbackClipboard implements FeedbackClipboard {
  _WebFeedbackClipboard(this.enabled, this.onPaste) {
    _listener = ((_PasteEvent event) {
      if (!enabled()) return;
      final files = event.clipboardData?.files;
      if (files == null) return;
      final images = <_PasteFile>[];
      // Read at most five descriptors: the form accepts four and explains overflow.
      for (var i = 0; i < files.length && images.length < 5; i++) {
        final file = files.item(i);
        if (file != null && file.type.startsWith('image/')) images.add(file);
      }
      if (images.isEmpty) return; // Text paste stays entirely with Flutter.
      event.preventDefault();
      onPaste(_read(images));
    }).toJS;
    _document.addEventListener('paste', _listener, true);
  }

  final bool Function() enabled;
  final void Function(Future<List<FeedbackClipboardImage>>) onPaste;
  late final JSFunction _listener;

  Future<List<FeedbackClipboardImage>> _read(List<_PasteFile> images) async {
    final result = <FeedbackClipboardImage>[];
    for (final file in images) {
      if (file.size > 50 * 1024 * 1024) {
        throw StateError('CLIPBOARD_IMAGE_TOO_LARGE');
      }
      final buffer = await file.arrayBuffer().toDart;
      result.add((
        name: file.name.isEmpty ? 'ekran-goruntusu.png' : file.name,
        bytes: buffer.toDart.asUint8List(),
      ));
    }
    return result;
  }

  @override
  bool get usesBrowserPaste => true;

  @override
  Future<List<FeedbackClipboardImage>> readImages() async => const [];

  @override
  void dispose() => _document.removeEventListener('paste', _listener, true);
}
