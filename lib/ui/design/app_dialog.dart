// FAZ 5 / A1b (i): ortak diyalog şablonu (başlık şeridi + içerik + eylem satırı).
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/icon_orb.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/ui_helpers.dart';

/// Diyalog başlık şeridi: düz ikon rozeti ([IconOrb], 44 dp squircle; sade stil) + başlık + alt başlık.
///
/// [AppDialog] bunu `AlertDialog.title` olarak kullanır; `Dialog` tabanlı özel diyaloglar (cihaz
/// sahiplenme, QR modalı) doğrudan içeriklerinin başına koyar. Kendi kenar boşluğunu taşır
/// (24 / 24 / 24 / 12): çağıran ayrıca dolgu vermez.
///
/// Taşma: başlık ve alt başlık en çok 3 satır (+ elips); ikon karosu sabit 44 dp, başlık kalan genişliği
/// alır. Erişilebilirlik: başlık `Semantics(header)`. Üst öğe sınırlı genişlikte olmalıdır.
class AppDialogHeader extends StatelessWidget {
  const AppDialogHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.tone = AppTone.primary,
  });

  final String title;
  final String? subtitle;

  /// null ise ikon karosu çizilmez.
  final IconData? icon;

  final AppTone tone;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final subtitle = this.subtitle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.xl,
        AppSpace.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            IconOrb(
              icon: icon!,
              tone: tone,
              size: 44,
              shape: IconOrbShape.squircle,
            ),
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: th.titleLarge,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpace.xs),
                    child: Text(
                      subtitle,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: th.bodySmall,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ortak diyalog şablonu. Bir `AlertDialog` DÖNDÜRÜR (`find.byType(AlertDialog)` bulucuları aynı
/// kalır): başlık = [AppDialogHeader], içerik = sabit genişlikli (`dialogWidthForScreen`; AlertDialog
/// `IntrinsicWidth` kullandığı için genişlik SABİT olmalı) [child], eylem satırı =
/// `AlertDialog.actions`.
///
/// Eylem sırası: [İptal/Vazgeç = TextButton] sonra [birincil = FilledButton/ElevatedButton; yıkıcı =
/// danger stilli]. Eylem düğmeleri yerleşik tipte kalır (tema stilini alır). Dar ekranda/büyük yazıda
/// eylemler `OverflowBar` ile alt alta dizilir. [actions] boşsa eylem alanı hiç eklenmez.
///
/// Kaydırma: başlık + içerik BİRLİKTE kaydırılır (`AlertDialog.scrollable`), eylem satırı sabit
/// kalır. Başlığı sabitleyip yalnız içeriği kaydırmak yatayda ve klavye açıkken (özellikle büyük
/// yazıyla) başlık + eylemler için bile yer bırakmadığından taşırdı; bu düzen her boyutta taşmaz ve
/// klavye açıkken alanı forma bırakır. İçeriğe sabit yükseklik/`Expanded` vermeyin (sınırsız
/// yükseklik alır).
///
/// Taşma: başlık/alt başlık en çok 3 satır; yatay kenar boşluğu 16. Ham `Colors.red/grey/green`
/// yerine `InlineNotice`/palet kullanın. Hareket azaltma: yerleşik diyalog geçişi (~150 ms) olduğu
/// gibi kalır.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.icon,
    this.tone = AppTone.primary,
    this.actions = const <Widget>[],
    this.draggable = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final AppTone tone;

  /// Diyalog içeriği (başlıkla birlikte kaydırılan alana konur; sabit yükseklik vermeyin).
  final Widget child;

  /// Eylem düğmeleri (sıra: iptal, birincil).
  final List<Widget> actions;

  /// Başlıktan taşınabilen pencere; konum ekran ve klavye sınırlarında kalır.
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final hasActions = actions.isNotEmpty;
    Widget surface(Alignment? alignment, Widget Function(Widget) wrapHeader) =>
        AlertDialog(
          alignment: alignment,
          scrollable: true,
          titlePadding: EdgeInsets.zero,
          title: wrapHeader(
            AppDialogHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              tone: tone,
            ),
          ),
          contentPadding: EdgeInsets.fromLTRB(
            AppSpace.xl,
            0,
            AppSpace.xl,
            hasActions ? AppSpace.md : AppSpace.xl,
          ),
          content: SizedBox(width: dialogWidthForScreen(context), child: child),
          actionsPadding: const EdgeInsets.fromLTRB(
            AppSpace.lg,
            0,
            AppSpace.lg,
            AppSpace.lg,
          ),
          actions: hasActions ? actions : null,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.xl,
          ),
        );
    return draggable
        ? _MovableDialog(enabled: true, builder: surface)
        : surface(null, (header) => header);
  }
}

typedef _DialogBuilder =
    Widget Function(Alignment? alignment, Widget Function(Widget) wrapHeader);

class _MovableDialog extends StatefulWidget {
  const _MovableDialog({required this.enabled, required this.builder});
  final bool enabled;
  final _DialogBuilder builder;

  @override
  State<_MovableDialog> createState() => _MovableDialogState();
}

class _MovableDialogState extends State<_MovableDialog> {
  Alignment _alignment = Alignment.center;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => widget.builder(
      widget.enabled ? _alignment : null,
      (header) => !widget.enabled
          ? header
          : Builder(
              builder: (headerContext) => MouseRegion(
                cursor: SystemMouseCursors.move,
                child: GestureDetector(
                  key: const ValueKey<String>('dialog_drag_handle'),
                  behavior: HitTestBehavior.opaque,
                  onPanUpdate: (details) {
                    // Material, AlertDialog içindeki gerçek pencere yüzeyidir. Dış
                    // Dialog render kutusu tüm ekranı kapsadığı için onu ölçmeyiz.
                    Size? surface;
                    headerContext.visitAncestorElements((element) {
                      if (element.widget is Material) {
                        final render = element.findRenderObject();
                        if (render is RenderBox && render.hasSize) {
                          surface = render.size;
                        }
                        return false;
                      }
                      return true;
                    });
                    final size = surface;
                    if (size == null) return;
                    final insets = MediaQuery.viewInsetsOf(context);
                    final freeWidth =
                        constraints.maxWidth -
                        insets.horizontal -
                        AppSpace.lg * 2 -
                        size.width;
                    final freeHeight =
                        constraints.maxHeight -
                        insets.vertical -
                        AppSpace.xl * 2 -
                        size.height;
                    setState(() {
                      _alignment = Alignment(
                        freeWidth > 1
                            ? (_alignment.x + details.delta.dx * 2 / freeWidth)
                                  .clamp(-1.0, 1.0)
                            : 0,
                        freeHeight > 1
                            ? (_alignment.y + details.delta.dy * 2 / freeHeight)
                                  .clamp(-1.0, 1.0)
                            : 0,
                      );
                    });
                  },
                  child: header,
                ),
              ),
            ),
    ),
  );
}
