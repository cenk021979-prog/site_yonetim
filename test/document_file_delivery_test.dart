import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show debugDefaultTargetPlatformOverride, TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/document_file_share.dart';

void main() {
  final payload = Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0, 0xff]);
  DownloadedDocument memory({String name = 'fiyat.pdf', int? size}) =>
      DownloadedDocument(
        fileName: name,
        mimeType: 'application/pdf',
        sizeBytes: size ?? payload.length,
        bytes: payload,
      );

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'Windows Download uses Save As and never invokes the broken share target',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      var saves = 0;
      final delivery = DocumentFileSharer(
        shareFn: (_) async => throw StateError('Windows share unavailable'),
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          saves++;
          expect(fileName, 'fiyat.pdf');
          expect(mimeType, 'application/pdf');
          expect(bytes, orderedEquals(payload));
          return Uri.file('C:/Downloads/fiyat.pdf');
        },
      );
      expect(
        await delivery.deliver(memory(name: '../../fiyat.pdf')),
        DocumentDeliveryOutcome.saved,
      );
      expect(saves, 1);
    },
  );

  test(
    'cancelled desktop Save As never falls back to share or a second save',
    () async {
      var saves = 0;
      var shares = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        isWeb: false,
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          saves++;
          return null;
        },
        shareFn: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      expect(
        await delivery.deliver(memory()),
        DocumentDeliveryOutcome.cancelled,
      );
      expect(saves, 1);
      expect(shares, 0);
    },
  );

  test(
    'web null means Blob download started, not confirmed saved or cancelled',
    () async {
      var saves = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        isWeb: true,
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          saves++;
          return null;
        },
        shareFn: (_) async => throw StateError('Web Share must not be called'),
      );
      expect(
        await delivery.deliver(memory()),
        DocumentDeliveryOutcome.downloadStarted,
      );
      expect(saves, 1);
    },
  );

  test(
    'save error propagates, without duplicate fallback download/share',
    () async {
      var saves = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          saves++;
          throw StateError('Disk full');
        },
        shareFn: (_) async => throw StateError('No share fallback'),
      );
      await expectLater(delivery.deliver(memory()), throwsStateError);
      expect(saves, 1);
    },
  );

  test('account change during file read prevents opening Save As', () async {
    final reading = Completer<Uint8List>();
    var allowed = true;
    var saves = 0;
    final delivery = DocumentFileSharer(
      useSaveDialog: true,
      readBytes: (_) => reading.future,
      saveFn: ({required fileName, required bytes, required mimeType}) async {
        saves++;
        return Uri.file('/saved');
      },
    );
    final result = delivery.deliver(memory(), canDeliver: () => allowed);
    allowed = false;
    reading.complete(payload);
    expect(await result, DocumentDeliveryOutcome.cancelled);
    expect(saves, 0);
  });

  test(
    'stale scope before delivery does not read or expose the file',
    () async {
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        readBytes: (_) async => throw StateError('No read'),
        saveFn:
            ({required fileName, required bytes, required mimeType}) async =>
                throw StateError('No save'),
      );
      expect(
        await delivery.deliver(memory(), canDeliver: () => false),
        DocumentDeliveryOutcome.cancelled,
      );
    },
  );

  test('truncated document is never passed to the save plugin', () async {
    final delivery = DocumentFileSharer(
      useSaveDialog: true,
      saveFn: ({required fileName, required bytes, required mimeType}) async =>
          throw ArgumentError('Must not save'),
    );
    await expectLater(
      delivery.deliver(memory(size: payload.length + 1)),
      throwsStateError,
    );
  });

  test('oversized metadata is rejected before any file read', () async {
    var reads = 0;
    final delivery = DocumentFileSharer(
      useSaveDialog: true,
      readBytes: (_) async {
        reads++;
        return payload;
      },
    );
    await expectLater(
      delivery.deliver(memory(size: 27 * 1024 * 1024)),
      throwsStateError,
    );
    expect(reads, 0);
  });

  test('changed native temporary file length never reaches Save As', () async {
    final root = await Directory.systemTemp.createTemp('document_length_test_');
    try {
      final sink = await TempFileDocumentSink.open(
        fileName: 'a.pdf',
        mimeType: 'application/pdf',
        root: root,
      );
      await sink.add(payload);
      final doc = await sink.finish();
      await File(doc.path!).writeAsBytes([...payload, 42]);
      var saves = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          saves++;
          return Uri.file('/saved');
        },
      );
      await expectLater(delivery.deliver(doc), throwsStateError);
      expect(saves, 0);
      expect(Directory(doc.directoryPath!).existsSync(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'mobile account change while cache preparation awaits prevents sharing',
    () async {
      var allowed = true;
      var shares = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: false,
        sweepStaleOnShare: false,
        shareFn: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.success);
        },
      );
      final pending = delivery.deliver(memory(), canDeliver: () => allowed);
      allowed = false;
      expect(await pending, DocumentDeliveryOutcome.cancelled);
      expect(shares, 0);
    },
  );

  test('saved native document removes only its owned temporary copy', () async {
    final root = await Directory.systemTemp.createTemp(
      'document_delivery_test_',
    );
    try {
      final sink = await TempFileDocumentSink.open(
        fileName: 'resim.png',
        mimeType: 'image/png',
        root: root,
      );
      await sink.add(payload);
      final downloaded = await sink.finish();
      final destination = File('${root.path}/user-selected.png');
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        isWeb: false,
        saveFn: ({required fileName, required bytes, required mimeType}) async {
          expect(mimeType, 'image/png');
          expect(fileName, 'resim.png');
          await destination.writeAsBytes(bytes);
          return destination.uri;
        },
      );
      expect(await delivery.deliver(downloaded), DocumentDeliveryOutcome.saved);
      expect(await destination.readAsBytes(), orderedEquals(payload));
      expect(Directory(downloaded.directoryPath!).existsSync(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('mobile delivery retains share result and byte/name contract', () async {
    final delivery = DocumentFileSharer(
      useSaveDialog: false,
      sweepStaleOnShare: false,
      shareFn: (params) async {
        expect(params.fileNameOverrides, ['fiyat.pdf']);
        expect(
          await params.files!.single.readAsBytes(),
          orderedEquals(payload),
        );
        return const ShareResult('', ShareResultStatus.unavailable);
      },
      saveFn: ({required fileName, required bytes, required mimeType}) async =>
          throw StateError('No native save'),
    );
    expect(await delivery.deliver(memory()), DocumentDeliveryOutcome.unknown);
  });

  test(
    'explicit sharing still shares even on desktop save platforms',
    () async {
      var shares = 0;
      final delivery = DocumentFileSharer(
        useSaveDialog: true,
        sweepStaleOnShare: false,
        shareFn: (_) async {
          shares++;
          return const ShareResult('', ShareResultStatus.dismissed);
        },
        saveFn:
            ({required fileName, required bytes, required mimeType}) async =>
                throw StateError('No save'),
      );
      expect(await delivery.share(memory()), DocumentShareOutcome.dismissed);
      expect(shares, 1);
    },
  );
}
