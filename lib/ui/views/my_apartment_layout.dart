import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

/// Daire ayrıntılarını geniş ekranda yan yana tutar. Büyük yazıda ve dar
/// pencerede eski okuma sırasına döner; sabit yükseklik veya metin kesme yoktur.
class ApartmentDetailsLayout extends StatelessWidget {
  const ApartmentDetailsLayout({super.key, required this.primary, required this.secondary, required this.stacked});

  final List<Widget> primary;
  final List<Widget> secondary;
  final List<Widget> stacked;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (constraints.maxWidth < 840 * scale.clamp(1, 2)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: stacked);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: primary)),
        const SizedBox(width: AppSpace.xl),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: secondary)),
      ],
    );
  });
}
