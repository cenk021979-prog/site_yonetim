// İndirilen belgeyi platforma göre kaydeder; açık paylaşım isteği ayrıca korunur.
//
// Belge zaten geçici klasöre akışla yazılmıştır ([TempFileDocumentSink]); burada yalnız paylaşım ve temizlik
// yapılır. Mobil paylaşımda silme zamanı ertelenir: Android'de alıcı uygulama dosyayı hâlâ
// okurken silmek yüklemeyi / eki bozar; iOS'ta paylaşım yaprağı kapanınca alıcı kopyayı almıştır.
// Süreç öldürülürse zamanlayıcı çalışmaz: bir sonraki paylaşımda ve hesap silinince (önek, bkz.
// document_download.dart) eski klasörler süpürülür.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform, visibleForTesting;
import 'package:share_plus/share_plus.dart';
import 'package:site_kapi_kontrol/models/document_upload_models.dart'
    show kDocumentAbsoluteMaxBytes;
import 'package:site_kapi_kontrol/services/document_download.dart';
import 'package:site_kapi_kontrol/services/file_save.dart';
import 'package:site_kapi_kontrol/services/local_cache_purge.dart';

/// Paylaşım sonucu (arayüz için sadeleştirilmiş).
enum DocumentShareOutcome {
  /// Kullanıcı bir paylaşım / kaydetme / aç eylemi seçti.
  shared,

  /// Kullanıcı paylaşım menüsünü kapattı.
  dismissed,

  /// Platform sonucu bildirmiyor (Android'in çoğu sürümü): menü açıldı, sonuç bilinmiyor.
  unknown,
}

/// A browser can confirm download initiation, not that a user saved the file.
enum DocumentDeliveryOutcome {
  saved,
  downloadStarted,
  shared,
  cancelled,
  unknown,
}

class DocumentFileSharer {
  DocumentFileSharer({
    Future<ShareResult> Function(ShareParams params)? shareFn,
    Duration? cleanupDelay,
    Duration staleAfter = const Duration(minutes: 10),
    bool sweepStaleOnShare = true,
    Future<void> Function()? purgeSharedCaches,
    SaveFileBytes? saveFn,
    bool? useSaveDialog,
    bool? isWeb,
    Future<Uint8List> Function(DownloadedDocument document)? readBytes,
  }) : _share = shareFn ?? SharePlus.instance.share,
       _cleanupDelay = cleanupDelay ?? _defaultCleanupDelay(),
       _staleAfter = staleAfter,
       _sweepStaleOnShare = sweepStaleOnShare,
       _purgeSharedCaches =
           purgeSharedCaches ??
           (() => purgeLocalSharedCaches(pickerCache: false)),
       _save = saveFn ?? saveFileBytes,
       _useSaveDialog = useSaveDialog ?? platformUsesFileSave,
       _isWeb = isWeb ?? kIsWeb,
       _readBytes = readBytes ?? _documentBytes;

  /// Zamanlanmış (gecikmeli) silmeler: klasör yolu -> zamanlayıcı.
  static final Map<String, Timer> _timers = <String, Timer>{};

  /// Testler için: bekleyen gecikmeli silme sayısı.
  @visibleForTesting
  static int get pendingCleanupCount => _timers.length;

  final Future<ShareResult> Function(ShareParams params) _share;
  final SaveFileBytes _save;
  final bool _useSaveDialog;
  final bool _isWeb;
  final Future<Uint8List> Function(DownloadedDocument document) _readBytes;
  final Duration _cleanupDelay;
  final Duration _staleAfter;

  /// Her paylaşımda önceki oturumlardan kalan eski klasörler süpürülür (testlerde gerçek dosya sistemine
  /// çıkmamak için kapatılabilir).
  final bool _sweepStaleOnShare;

  /// Gecikmeli silme süresi dolunca eklenti (share_plus) önbelleğini de siler: share_plus Android'de dosya yolunu
  /// `<önbellek>/share_plus` altına İKİNCİ kez kopyalar ve bu klasörü yalnız sonraki paylaşımın başında temizler;
  /// belge (sözleşme: T.C. / IBAN olabilir) orada kalmasın. Picker önbelleğine DOKUNMAZ (yükleme sürüyor olabilir).
  final Future<void> Function() _purgeSharedCaches;

  static Duration _defaultCleanupDelay() {
    // iOS: paylaşım yaprağı alıcı kopyayı aldıktan sonra kapanır; hemen silinebilir.
    if (defaultTargetPlatform == TargetPlatform.iOS) return Duration.zero;
    return const Duration(minutes: 2);
  }

  static Future<Uint8List> _documentBytes(DownloadedDocument document) async {
    final bytes = document.bytes;
    if (bytes != null) return bytes;
    final path = document.path;
    if (path == null) throw StateError('İndirilen dosya bulunamadı.');
    final file = File(path);
    if (await file.length() != document.sizeBytes) {
      throw StateError('İndirilen dosya tamamlanmadı. Yeniden indirin.');
    }
    final builder = BytesBuilder(copy: false);
    var count = 0;
    await for (final chunk in file.openRead()) {
      count += chunk.length;
      if (count > document.sizeBytes) {
        throw StateError('İndirilen dosyanın boyutu değişti. Yeniden indirin.');
      }
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  /// The app's Download action: desktop/web save, mobile share. Explicit
  /// [share] remains available and keeps its existing mobile cleanup contract.
  /// A cancelled native save never opens a share sheet or retries the download.
  Future<DocumentDeliveryOutcome> deliver(
    DownloadedDocument document, {
    Rect? sharePositionOrigin,
    bool Function()? canDeliver,
  }) async {
    bool allowed() => canDeliver?.call() ?? true;
    if (!_useSaveDialog) {
      if (!allowed()) {
        await scheduleDelete(document);
        return DocumentDeliveryOutcome.cancelled;
      }
      return switch (await share(
        document,
        sharePositionOrigin: sharePositionOrigin,
        canShare: canDeliver,
      )) {
        DocumentShareOutcome.shared => DocumentDeliveryOutcome.shared,
        DocumentShareOutcome.dismissed => DocumentDeliveryOutcome.cancelled,
        DocumentShareOutcome.unknown => DocumentDeliveryOutcome.unknown,
      };
    }
    var temporaryCopyCleaned = false;
    try {
      if (!allowed()) return DocumentDeliveryOutcome.cancelled;
      if (document.sizeBytes < 0 ||
          document.sizeBytes > kDocumentAbsoluteMaxBytes + 1024 * 1024) {
        throw StateError('Dosya kaydetme sınırını aşıyor.');
      }
      final bytes = await _readBytes(document);
      if (!allowed()) return DocumentDeliveryOutcome.cancelled;
      if (bytes.length != document.sizeBytes) {
        throw StateError('İndirilen dosya tamamlanmadı. Yeniden indirin.');
      }
      // FilePicker requires bytes. The bounded copy is ready, so release our
      // private cache BEFORE Save As. Cleanup after the dialog must never touch
      // a location the user has just chosen, even if it reuses the same path.
      await TempFileDocumentSink.deleteDirectory(document.directoryPath);
      temporaryCopyCleaned = true;
      if (!allowed()) return DocumentDeliveryOutcome.cancelled;
      final result = await _save(
        fileName: safeDocumentFileName(document.fileName),
        bytes: bytes,
        mimeType: document.mimeType,
      );
      if (_isWeb) return DocumentDeliveryOutcome.downloadStarted;
      return result == null
          ? DocumentDeliveryOutcome.cancelled
          : DocumentDeliveryOutcome.saved;
    } finally {
      if (!temporaryCopyCleaned) {
        await TempFileDocumentSink.deleteDirectory(document.directoryPath);
      }
    }
  }

  /// Önceki oturumlardan kalan `kisisel_veri_belge_*` klasörlerini siler (en iyi çaba, hata fırlatmaz).
  /// [includeLive] true: bu süreçte kullanılanlar ve bekleyen zamanlayıcılar da (hesap silme).
  static Future<void> sweepAll({
    Duration staleAfter = Duration.zero,
    Directory? root,
    bool includeLive = false,
  }) async {
    if (kIsWeb) return;
    if (includeLive) {
      final known = <String>{
        ...TempFileDocumentSink.livePaths,
        ..._timers.keys,
      };
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
      for (final path in known) {
        await TempFileDocumentSink.deleteDirectory(path);
      }
    }
    try {
      final limit = DateTime.now().subtract(staleAfter);
      await for (final entity in (root ?? Directory.systemTemp).list(
        followLinks: false,
      )) {
        if (entity is! Directory) continue;
        final name =
            entity.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull ?? '';
        if (!name.startsWith(TempFileDocumentSink.dirPrefix) ||
            TempFileDocumentSink.livePaths.contains(entity.path)) {
          continue;
        }
        try {
          if (staleAfter == Duration.zero ||
              (await entity.stat()).modified.isBefore(limit)) {
            await entity.delete(recursive: true);
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  /// [document]'i paylaşım menüsüyle sunar. iPad / masaüstünde açılır pencerenin bağlanacağı yer
  /// [sharePositionOrigin]'dir (düğmenin ekran dikdörtgeni). Paylaşım bitince (ya da hata verince) geçici
  /// klasör silinmek üzere zamanlanır.
  Future<DocumentShareOutcome> share(
    DownloadedDocument document, {
    Rect? sharePositionOrigin,
    bool Function()? canShare,
  }) async {
    try {
      await _sweepStale();
      if (!(canShare?.call() ?? true)) return DocumentShareOutcome.dismissed;
      final path = document.path;
      final file = path != null
          ? XFile(path, mimeType: document.mimeType, name: document.fileName)
          : XFile.fromData(
              document.bytes!,
              mimeType: document.mimeType,
              name: document.fileName,
            );
      final result = await _share(
        ShareParams(
          files: <XFile>[file],
          fileNameOverrides: <String>[document.fileName],
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
      switch (result.status) {
        case ShareResultStatus.success:
          return DocumentShareOutcome.shared;
        case ShareResultStatus.dismissed:
          return DocumentShareOutcome.dismissed;
        case ShareResultStatus.unavailable:
          return DocumentShareOutcome.unknown;
      }
    } finally {
      await scheduleDelete(document);
    }
  }

  /// Belgenin geçici klasörünü siler (gecikme sıfırsa BEKLER; değilse zamanlar). Paylaşmadan vazgeçilen
  /// (iptal / hata) indirmeler için de çağrılır.
  Future<void> scheduleDelete(DownloadedDocument document) async {
    final dir = document.directoryPath;
    if (dir == null) return;
    if (_cleanupDelay == Duration.zero) {
      await TempFileDocumentSink.deleteDirectory(dir);
    } else {
      _timers[dir]?.cancel();
      _timers[dir] = Timer(_cleanupDelay, () {
        _timers.remove(dir);
        unawaited(_expire(dir));
      });
    }
  }

  /// Süresi dolan geçici klasörü siler; BAŞKA bekleyen silme (yani süren başka bir paylaşım) yoksa share_plus
  /// önbelleğini de temizler (ikinci bir paylaşımın kopyasını alıcı okurken silmemek için). Hata fırlatmaz.
  Future<void> _expire(String dir) async {
    await TempFileDocumentSink.deleteDirectory(dir);
    if (_timers.isNotEmpty) return;
    try {
      await _purgeSharedCaches();
    } catch (_) {
      // En iyi çaba.
    }
  }

  Future<void> _sweepStale() async {
    if (_sweepStaleOnShare) await sweepAll(staleAfter: _staleAfter);
  }
}
