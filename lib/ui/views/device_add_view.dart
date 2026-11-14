import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/device_action_tile.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

class DeviceAddView extends StatelessWidget {
  const DeviceAddView({
    super.key,
    required this.onOpenQrRegistration,
    required this.onOpenManualRegistration,
    this.title,
    this.qrTitle,
    this.qrDescription,
    this.qrButtonLabel,
    this.manualTitle,
    this.manualDescription,
    this.manualButtonLabel,
  });

  final VoidCallback onOpenQrRegistration;
  final VoidCallback onOpenManualRegistration;
  final String? title;
  final String? qrTitle;
  final String? qrDescription;
  final String? qrButtonLabel;
  final String? manualTitle;
  final String? manualDescription;
  final String? manualButtonLabel;

  @override
  Widget build(BuildContext context) {
    final qrTile = WorkspacePaneCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      tone: AppTone.primary,
      child: DeviceActionTile(
        icon: Icons.qr_code_scanner_outlined,
        title: qrTitle ?? 'QR ile Şirket Veritabanına Kaydet',
        description: qrDescription ??
            'Cihaz üzerindeki QR kodu okutur, Unique ID alanını otomatik doldurur ve şirket kayıt formunu açar.',
        buttonLabel: qrButtonLabel ?? 'QR Oku',
        onPressed: onOpenQrRegistration,
      ),
    );
    final manualTile = WorkspacePaneCard(
      padding: const EdgeInsets.all(AppSpace.sm),
      tone: AppTone.primary,
      child: DeviceActionTile(
        icon: Icons.edit_note_outlined,
        title: manualTitle ?? 'Unique ID ile Şirket Veritabanına Kaydet',
        description: manualDescription ??
            'QR okunamıyorsa veya masaüstü sürümde çalışıyorsanız cihaz Unique ID bilgisini elle girerek şirket hesabına kayıt yapar.',
        buttonLabel: manualButtonLabel ?? 'Unique ID Gir',
        onPressed: onOpenManualRegistration,
      ),
    );

    return WorkspaceSplitShell(
      // Hero başlık kartı (AppCard seviye 2) + cilalı rozet; başlık SectionHeader (anlamsal başlık).
      header: SizedBox(
        width: double.infinity,
        child: PageHeaderCard(
          title: title ?? 'Şirket Veritabanına Cihaz Kaydet',
          icon: Icons.memory_rounded,
        ),
      ),
      left: qrTile,
      right: manualTile,
    );
  }
}
