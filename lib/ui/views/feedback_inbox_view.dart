// "Gelen Geri Bildirimler" (docs/PLATFORM_GERI_BILDIRIM.md): site yöneticisi KENDİ sitesinin, platform sahibi (süper kullanıcı) tüm geri bildirimleri okur.
//
// Her kayıt: gönderen adı ve rolü, zaman, gönderildiği EKRAN (ad + rota), metin ve ek dosyalar (dokununca görüntülenir). Liste imleçli sayfalanır
// ([CursorLoader]); yenileme sürerken eski liste kalır, hata varsa "kayıt yok" yerine hata + "Tekrar Dene" görünür. Bu ekran salt okunurdur; sunucu yetkisiz
// çağrıyı 403 ile reddeder (yalnız menüye girişin görünürlüğü değil, yetki sunucudadır). Metin ve dosya adı günlüğe yazılmaz.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/config/app_config.dart';
import 'package:site_kapi_kontrol/models/document_models.dart'
    show formatDocumentSize;
import 'package:site_kapi_kontrol/models/feedback_models.dart';
import 'package:site_kapi_kontrol/services/feedback_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/cursor_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/dialog_guard.dart';
import 'package:site_kapi_kontrol/ui/helpers/feedback_reference.dart';
import 'package:site_kapi_kontrol/ui/helpers/istanbul_time.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/feedback_links.dart';

class FeedbackInboxPage extends StatefulWidget {
  const FeedbackInboxPage({super.key, required this.service, this.siteCode, this.mine = false});

  final FeedbackService service;
  final bool mine;

  /// Dolu: o sitenin geri bildirimleri (site yöneticisi, `/manager/sites/:siteCode/feedback`). null: platform sahibinin tüm kayıtları (`/admin/feedback`).
  final int? siteCode;

  /// Sayfa başına kayıt.
  static const int pageSize = 30;

  static Future<void> open(
    BuildContext context, {
    required FeedbackService service,
    int? siteCode,
    bool mine = false,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FeedbackInboxPage(service: service, siteCode: siteCode, mine: mine),
      ),
    );
  }

  @override
  State<FeedbackInboxPage> createState() => _FeedbackInboxPageState();
}

class _FeedbackInboxPageState extends State<FeedbackInboxPage> {
  late final CursorLoader<FeedbackRecord>
  _loader = CursorLoader<FeedbackRecord>(
    fetch: _fetch,
    keyOf: (record) => record.id,
    notify: () {
      if (mounted) setState(() {});
    },
    isAlive: () => mounted,
    errorFallback:
        'Geri bildirimler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
  );

  Future<CursorPage<FeedbackRecord>> _fetch(int? cursor) async {
    final siteCode = widget.siteCode;
    final page = widget.mine
        ? await widget.service.listMine(cursor: cursor, limit: FeedbackInboxPage.pageSize)
        : siteCode == null
        ? await widget.service.listAll(
            cursor: cursor,
            limit: FeedbackInboxPage.pageSize,
          )
        : await widget.service.listForSite(
            siteCode,
            cursor: cursor,
            limit: FeedbackInboxPage.pageSize,
          );
    return (items: page.items, next: page.nextCursor);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loader.reload());
  }

  @override
  void dispose() {
    _loader.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = _loader;
    final Widget body;
    if (l.items.isEmpty) {
      if (l.loading || (l.error == null && !l.loadedOnce)) {
        body = const ListSkeleton(rows: 3);
      } else if (l.error != null) {
        body = InlineNotice(message: l.error!, onRetry: _loader.reload);
      } else {
        body = EmptyCard(
          icon: Icons.rate_review_outlined,
          title: widget.mine ? 'Henüz geri bildirim göndermediniz.' : 'Henüz geri bildirim yok.',
          message:
              widget.mine ? 'Gönderdiğiniz notlar ve ekleri burada görünür.' : 'Kullanıcıların her ekrandan gönderdiği görüş ve öneriler burada listelenir.',
          tone: AppTone.info,
        );
      }
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (l.error != null) ...[
            InlineNotice(message: l.error!, onRetry: _loader.reload),
            const SizedBox(height: AppSpace.md),
          ],
          for (final record in l.items)
            Padding(
              padding: EdgeInsets.only(bottom: widget.mine ? AppSpace.sm : AppSpace.md),
              child: _FeedbackCard(
                key: ValueKey<String>('feedback_item_${record.id}'),
                record: record,
                service: widget.service,
                siteCode: widget.siteCode,
                showSite: widget.siteCode == null,
                mine: widget.mine,
              ),
            ),
          if (l.moreError != null) ...[
            InlineNotice(message: l.moreError!, onRetry: _loader.loadMore),
            const SizedBox(height: AppSpace.md),
          ],
          if (l.hasMore)
            Align(
              alignment: Alignment.center,
              child: PrimaryActionButton(
                key: const ValueKey<String>('feedback_inbox_more'),
                label: 'Daha fazla yükle',
                icon: Icons.expand_more_rounded,
                variant: AppButtonVariant.tonal,
                expand: false,
                loading: l.loadingMore,
                onPressed: (l.loadingMore || l.loading)
                    ? null
                    : _loader.loadMore,
              ),
            ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.mine ? 'Gönderdiğim geri bildirimler' : 'Gelen Geri Bildirimler'),
        actions: [
          IconButton(
            key: const ValueKey<String>('feedback_inbox_refresh'),
            tooltip: 'Yenile',
            onPressed: l.loading ? null : _loader.reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loader.reload,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(AppSpace.lg),
                children: [body],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    super.key,
    required this.record,
    required this.service,
    required this.siteCode,
    required this.showSite,
    this.mine = false,
  });

  final FeedbackRecord record;
  final FeedbackService service;
  final int? siteCode;
  final bool showSite;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final site = showSite
        ? (record.siteName ??
              (record.siteCode == null
                  ? 'Siteye bağlı değil'
                  : 'Site ${record.siteCode}'))
        : null;
    final meta = <String>[
      if (record.appVersion != null) 'Sürüm ${record.appVersion}',
      if (record.platform != null) record.platform!,
    ].join(' · ');
    final details = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                record.userName,
                style: th.titleSmall?.copyWith(color: p.text),
              ),
              InfoChip(record.roleLabel),
              if (mine) const InfoChip('Alındı'),
            ],
          ),
          const SizedBox(height: 2),
          Text(formatIstanbulDateTime(record.createdAt), style: th.bodySmall),
          const SizedBox(height: AppSpace.sm),
          Text.rich(
            key: ValueKey<String>('feedback_item_screen_${record.id}'),
            TextSpan(
              children: [
                TextSpan(text: 'Ekran: ', style: th.bodySmall),
                TextSpan(
                  text: record.screenName,
                  style: th.bodySmall?.copyWith(
                    color: p.text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: '  (${record.screenRoute})',
                  style: th.bodySmall,
                ),
              ],
            ),
          ),
          if (site != null) Text('Site: $site', style: th.bodySmall),
          if (meta.isNotEmpty) Text(meta, style: th.bodySmall),
          const SizedBox(height: AppSpace.sm),
          SelectableText(
            record.message,
            style: th.bodyMedium?.copyWith(color: p.text),
          ),
          if (AppConfig.temporaryFeedbackLinks) ...[
            const SizedBox(height: AppSpace.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FeedbackCopyButton(
                key: ValueKey<String>('feedback_item_${record.id}_copy_review'),
                value: feedbackReviewNote(record),
                label: 'İnceleme notunu kopyala',
              ),
            ),
          ],
          if (record.attachments.isNotEmpty) ...[
            const SizedBox(height: AppSpace.md),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                for (var i = 0; i < record.attachments.length; i++)
                  OutlinedButton.icon(
                    key: ValueKey<String>('feedback_item_${record.id}_file_$i'),
                    onPressed: () => unawaited(
                      _FeedbackImageDialog.show(
                        context,
                        service: service,
                        siteCode: siteCode,
                        attachment: record.attachments[i],
                        mine: mine,
                      ),
                    ),
                    icon: const Icon(Icons.image_outlined, size: 18),
                    label: Text(
                      'Dosya ${i + 1} (${formatDocumentSize(record.attachments[i].sizeBytes)})',
                    ),
                  ),
              ],
            ),
          ],
        ],
      );
    return AppCard(padding: mine ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : const EdgeInsets.all(AppSpace.lg), child: mine ? ExpansionTile(
      key: ValueKey('my_feedback_expand_${record.id}'),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 12),
      title: Text('${record.screenName} · #${record.id}', style: th.titleMedium),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(record.message, maxLines: 1, overflow: TextOverflow.ellipsis, style: th.bodyMedium),
        const SizedBox(height: 4),
        Text('${formatIstanbulDateTime(record.createdAt)} · Alındı', style: th.bodySmall),
      ]),
      children: [details],
    ) : details);
  }
}

/// Ek görüntüsü: belirteçli indirme, yakınlaştırılabilir önizleme; hata "Tekrar Dene" ile.
class _FeedbackImageDialog extends StatefulWidget {
  const _FeedbackImageDialog({
    required this.service,
    required this.siteCode,
    required this.attachment,
    this.mine = false,
  });

  final FeedbackService service;
  final int? siteCode;
  final FeedbackAttachment attachment;
  final bool mine;

  static Future<void> show(
    BuildContext context, {
    required FeedbackService service,
    required int? siteCode,
    required FeedbackAttachment attachment,
    bool mine = false,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _FeedbackImageDialog(
        service: service,
        siteCode: siteCode,
        attachment: attachment,
        mine: mine,
      ),
    );
  }

  @override
  State<_FeedbackImageDialog> createState() => _FeedbackImageDialogState();
}

class _FeedbackImageDialogState extends State<_FeedbackImageDialog> {
  Uint8List? _bytes;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = widget.mine ? await widget.service.downloadMine(
        feedbackId: widget.attachment.feedbackId,
        attachmentId: widget.attachment.id,
      ) : await widget.service.download(
        siteCode: widget.siteCode,
        feedbackId: widget.attachment.feedbackId,
        attachmentId: widget.attachment.id,
      );
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(
          e,
          'Dosya açılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _bytes;
    final Widget child;
    if (_loading) {
      child = const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null || bytes == null) {
      child = InlineNotice(
        message: _error ?? 'Dosya açılamadı.',
        onRetry: _load,
      );
    } else {
      child = ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: InteractiveViewer(
          maxScale: 5,
          child: Image.memory(
            bytes,
            key: const ValueKey<String>('feedback_image'),
            fit: BoxFit.contain,
            // Çözme belleği sınırlı kalsın: sunucu 12.000 piksel kenara kadar kabul eder.
            cacheWidth: 1600,
            semanticLabel: 'Geri bildirim eki',
            errorBuilder: (context, error, stack) =>
                const InlineNotice(message: 'Dosya görüntülenemedi.'),
          ),
        ),
      );
    }
    return AppDialog(
      title: 'Ek Dosya',
      subtitle: formatDocumentSize(widget.attachment.sizeBytes),
      icon: Icons.image_outlined,
      actions: [
        TextButton(
          key: const ValueKey<String>('feedback_image_close'),
          onPressed: () => popIfCurrent(context),
          child: const Text('Kapat'),
        ),
      ],
      child: child,
    );
  }
}
