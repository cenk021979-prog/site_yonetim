import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

/// Geçiş Kontrol (`door_control`) modülü kullanıcının bağlı olduğu TÜM sitelerde kapalıyken Panel'de
/// kapı kartları yerine gösterilen bilgi kartı.
///
/// [onOpenModules] verilirse (site yöneticisi, süper kullanıcı) "Modüller Ekranını Aç" düğmesi
/// gösterilir; sakin ve diğer rollerde yalnız bilgi vardır (modülü site yöneticisi açar).
///
/// [compact] true ise kapı dışı bölümleri olan ekranların (bireysel ana ekran) en üstünde durmak
/// üzere tek satırlık kısa bir bilgi kutusu çizilir.
class DoorControlDisabledCard extends StatelessWidget {
  const DoorControlDisabledCard({
    super.key,
    this.onOpenModules,
    this.compact = false,
  });

  final VoidCallback? onOpenModules;
  final bool compact;

  /// Başlık (sözleşmedeki metin).
  static const String title = 'Geçiş Kontrol modülü kapalı';

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return const InlineNotice(
        tone: AppTone.warning,
        icon: Icons.lock_outline_rounded,
        message:
            'Geçiş Kontrol modülü kapalı: telefondan kapı açma, QR ve misafir geçişi şu an kapalı.',
      );
    }
    final canManage = onOpenModules != null;
    final p = context.palette;

    return WorkspaceSplitShell(
      left: WorkspacePaneCard(
        icon: Icons.door_sliding_outlined,
        title: 'Geçiş Kontrol Durumu',
        subtitle: 'Kapı açma, QR ve misafir geçiş özellikleri.',
        tone: AppTone.warning,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: const [
                StatusChip(
                  label: 'Modül Devre Dışı',
                  tone: AppTone.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpace.md),
            Text(
              'Kapsanan Özellikler:',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: p.text,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            _ScopeItem(
              icon: Icons.touch_app_rounded,
              label: 'Mobil ve uzaktan kapı/bariyer açma',
              color: p.textSecondary,
            ),
            const SizedBox(height: AppSpace.xs),
            _ScopeItem(
              icon: Icons.qr_code_2_rounded,
              label: 'Dinamik QR kod ve misafir geçiş linkleri',
              color: p.textSecondary,
            ),
            const SizedBox(height: AppSpace.xs),
            _ScopeItem(
              icon: Icons.bluetooth_connected_rounded,
              label: 'BLE yakınlık tetikleme ve erişim kayıtları',
              color: p.textSecondary,
            ),
          ],
        ),
      ),
      right: WorkspacePaneCard(
        icon: Icons.lock_outline_rounded,
        title: 'Modül Erişimi & İşlem',
        subtitle: canManage
            ? 'Yönetici olarak modülü modüller ekranından açabilirsiniz.'
            : 'Site yöneticisi modülü etkinleştirdiğinde kartlar görünür.',
        tone: AppTone.warning,
        child: EmptyCard(
          icon: Icons.lock_outline_rounded,
          tone: AppTone.warning,
          title: title,
          message: canManage
              ? 'Telefondan kapı açma, QR ve misafir geçişi bu sitede şu an kapalı. '
                    'Modüller ekranından yeniden açabilirsiniz.'
              : 'Telefondan kapı açma, QR ve misafir geçişi şu an kapalı. '
                    'Site yöneticisi Modüller ekranından açabilir.',
          child: canManage
              ? PrimaryActionButton(
                  label: 'Modüller Ekranını Aç',
                  icon: Icons.extension_rounded,
                  variant: AppButtonVariant.tonal,
                  tone: AppTone.warning,
                  onPressed: onOpenModules,
                )
              : null,
        ),
      ),
    );
  }
}

class _ScopeItem extends StatelessWidget {
  const _ScopeItem({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 12.5, color: color),
          ),
        ),
      ],
    );
  }
}
