import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Tüm modüller ve ekranlar için standart iki kartlı (Master-Detail) düzen kabuğu.
///
/// - Geniş ekranlarda (`>= breakpoint`) ve telefon/tablet yatay (`landscape`) modunda
///   sol kontrol/özet kartı ile sağ detay/liste kartını yatayda tam genişliğe yayarak yan yana (`Row`) yerleştirir.
/// - Dikey (`portrait`) dar ekranlarda üstte kontrol/özet kartı, altta detay/liste kartı olacak şekilde (`Column`) istifler.
class WorkspaceSplitShell extends StatelessWidget {
  const WorkspaceSplitShell({
    super.key,
    this.header,
    required this.left,
    required this.right,
    this.footer,
    this.leftFlex = 5,
    this.rightFlex = 7,
    this.breakpoint = 720,
    this.spacing = AppSpace.lg,
  });

  final Widget? header;
  final Widget left;
  final Widget right;
  final Widget? footer;
  final int leftFlex;
  final int rightFlex;
  final double breakpoint;
  final double spacing;

  /// Ekran genişliği veya yatay yönelim iki sütunlu yerleşime uygun mu?
  static bool isSplitWide(
    BuildContext context,
    double maxWidth, {
    double breakpoint = 720,
  }) {
    final mq = MediaQuery.maybeOf(context);
    final isLandscape = mq?.orientation == Orientation.landscape ||
        (mq != null && mq.size.width > mq.size.height);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    return maxWidth >= breakpoint ||
        (isLandscape && maxWidth >= 500 && (maxWidth / textScale) >= 360);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = isSplitWide(
          context,
          constraints.maxWidth,
          breakpoint: breakpoint,
        );
        final effectiveLeftFlex = constraints.maxWidth >= 700 ? leftFlex : 1;
        final effectiveRightFlex = constraints.maxWidth >= 700 ? rightFlex : 1;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[
              header!,
              const SizedBox(height: AppSpace.md),
            ],
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: effectiveLeftFlex, child: left),
                  SizedBox(width: spacing),
                  Expanded(flex: effectiveRightFlex, child: right),
                ],
              )
            else ...[
              left,
              SizedBox(height: spacing),
              right,
            ],
            if (footer != null) ...[
              const SizedBox(height: AppSpace.lg),
              footer!,
            ],
          ],
        );
      },
    );
  }
}

/// İki kartlı çalışma alanında sol (kontrol/özet) veya sağ (detay/liste) bölmesini saran
/// kurumsal çerçeveli kart bileşeni.
///
/// Mevcut ekran/tasarım testlerindeki iç içe `AppCard` ve `IconOrb` sayısı kurallarını
/// bozmamak için doğrudan `Container` + `BoxDecoration` kullanır.
class WorkspacePaneCard extends StatelessWidget {
  const WorkspacePaneCard({
    super.key,
    this.cardKey,
    this.icon,
    this.title,
    this.subtitle,
    this.trailing,
    this.onRefresh,
    this.refreshTooltip = 'Yenile',
    this.refreshIcon = Icons.refresh_rounded,
    this.tone = AppTone.primary,
    this.padding = const EdgeInsets.all(AppSpace.md),
    this.showShadow = false,
    required this.child,
  });

  final Key? cardKey;
  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onRefresh;
  final String refreshTooltip;
  final IconData refreshIcon;
  final AppTone tone;
  final EdgeInsetsGeometry padding;
  final bool showShadow;
  final Widget child;

  /// Kurumsal tema ile uyumlu kart dış çerçevesi ve yüzey stili.
  static BoxDecoration paneDecoration(
    BuildContext context, {
    AppTone tone = AppTone.primary,
    double radius = 18,
    bool showShadow = false,
  }) {
    final p = context.palette;
    final bg = p.isDark ? const Color(0xFF162032) : p.surface;
    final borderColor = Color.alphaBlend(
      tone.hue.withValues(alpha: p.isDark ? 0.34 : 0.24),
      p.border,
    );
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: borderColor, width: 1.5),
      boxShadow: showShadow
          ? [
              BoxShadow(
                color: (p.isDark ? Colors.black : const Color(0xFF0F172A))
                    .withValues(alpha: p.isDark ? 0.26 : 0.045),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
    );
  }

  /// Panel üst başlık satırı.
  static Widget buildPaneHeader(
    BuildContext context, {
    IconData? icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onRefresh,
    String refreshTooltip = 'Yenile',
    IconData refreshIcon = Icons.refresh_rounded,
    AppTone tone = AppTone.primary,
  }) {
    final p = context.palette;
    final scale = MediaQuery.textScalerOf(context).scale(1.0);
    final showBadge = icon != null && scale < 1.75;
    final iconInk = tone.ink(p);
    final iconBg = Color.alphaBlend(
      tone.hue.withValues(alpha: p.isDark ? 0.20 : 0.11),
      p.surface,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showBadge) ...[
          ExcludeSemantics(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: tone.hue.withValues(alpha: p.isDark ? 0.35 : 0.22),
                ),
              ),
              child: Icon(icon, color: iconInk, size: 19),
            ),
          ),
          const SizedBox(width: AppSpace.sm),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15.5,
                  height: 1.25,
                  letterSpacing: -0.2,
                  color: p.text,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: p.textSecondary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpace.xs),
          Flexible(flex: 0, child: trailing),
        ],
        if (onRefresh != null)
          IconButton(
            onPressed: onRefresh,
            icon: Icon(refreshIcon, color: p.textSecondary),
            tooltip: refreshTooltip,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final dividerColor = Color.alphaBlend(
      tone.hue.withValues(alpha: p.isDark ? 0.22 : 0.12),
      p.border,
    );

    return Container(
      key: cardKey,
      decoration: paneDecoration(context, tone: tone, showShadow: showShadow),
      padding: padding,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (title != null) ...[
              buildPaneHeader(
                context,
                icon: icon,
                title: title!,
                subtitle: subtitle,
                trailing: trailing,
                onRefresh: onRefresh,
                refreshTooltip: refreshTooltip,
                refreshIcon: refreshIcon,
                tone: tone,
              ),
              const SizedBox(height: AppSpace.md),
              Container(height: 1, color: dividerColor),
              const SizedBox(height: AppSpace.md),
            ],
            child,
          ],
        ),
      ),
    );
  }
}
