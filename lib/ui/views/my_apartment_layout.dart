import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

/// Daire ayrıntılarını geniş ekranda ve yatay tablet/telefonda iki bölme kartta yan yana,
/// dikey/dar ekranda alt alta yerleştirir.
class ApartmentDetailsLayout extends StatelessWidget {
  const ApartmentDetailsLayout({
    super.key,
    this.header,
    required this.primary,
    required this.secondary,
    required this.stacked,
  });

  final Widget? header;
  final List<Widget> primary;
  final List<Widget> secondary;
  final List<Widget> stacked;

  @override
  Widget build(BuildContext context) {
    return WorkspaceSplitShell(
      header: header,
      left: WorkspacePaneCard(
        icon: Icons.home_work_outlined,
        title: 'Daire ve Sakinler',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: primary,
        ),
      ),
      right: WorkspacePaneCard(
        icon: Icons.directions_car_outlined,
        title: 'Araçlar ve Talepler',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: secondary,
        ),
      ),
    );
  }
}
