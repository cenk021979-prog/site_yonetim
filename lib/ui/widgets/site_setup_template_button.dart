import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart'
    show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/services/site_setup_template.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Başvuru ve kurulum aynı, kişisel veri içermeyen boş XLSX dosyasını sunar.
class SiteSetupTemplateButton extends StatefulWidget {
  const SiteSetupTemplateButton({
    super.key,
    this.enabled = true,
    this.delivery,
  });

  final bool enabled;
  final BulkFileDelivery? delivery;

  @override
  State<SiteSetupTemplateButton> createState() =>
      _SiteSetupTemplateButtonState();
}

class _SiteSetupTemplateButtonState extends State<SiteSetupTemplateButton> {
  bool _busy = false;
  String? _error;
  bool _delivered = false;

  Future<void> _download(BuildContext buttonContext) async {
    if (_busy || !widget.enabled) return;
    final render = buttonContext.findRenderObject();
    final origin = render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset.zero) & render.size
        : null;
    setState(() {
      _busy = true;
      _error = null;
      _delivered = false;
    });
    try {
      final outcome = await (widget.delivery ?? BulkFileSharer()).deliver(
        buildBlankSiteSetupTemplate(),
        sharePositionOrigin: origin,
        subject: 'Site kurulum boş Excel şablonu',
      );
      if (mounted) {
        setState(() => _delivered = outcome == ExportShareOutcome.shared);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error =
              'Şablon hazırlanamadı veya kaydedilemedi. Tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Builder(
        builder: (buttonContext) => PrimaryActionButton(
          key: const ValueKey<String>('site_setup_blank_template'),
          label: _busy ? 'Şablon hazırlanıyor…' : 'Boş Excel şablonunu indir',
          icon: Icons.file_download_outlined,
          variant: AppButtonVariant.outline,
          onPressed: widget.enabled && !_busy
              ? () => unawaited(_download(buttonContext))
              : null,
        ),
      ),
      const SizedBox(height: AppSpace.xs),
      Text(
        'Blok, daire, sakin adı, telefon ve isteğe bağlı araç plakalarını doldurun. Dosyayı site onaylandıktan sonra Kişiler > Toplu Yükle > Hepsi bir arada bölümünden yükleyin.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      if (_error != null) ...[
        const SizedBox(height: AppSpace.xs),
        InlineNotice(message: _error!),
      ],
      if (_delivered) ...[
        const SizedBox(height: AppSpace.xs),
        const InlineNotice(
          tone: AppTone.success,
          message:
              'Şablon hazır. Doldurduğunuz dosyayı yüklemeden önce kayıtları kontrol edin.',
        ),
      ],
    ],
  );
}
