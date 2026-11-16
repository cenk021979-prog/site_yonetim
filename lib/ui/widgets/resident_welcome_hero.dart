import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/individual_door_card.dart';

/// Daire kullanıcısının günlük işlerine odaklanan, veri çekmeyen karşılama alanı.
class ResidentWelcomeHero extends StatelessWidget {
  const ResidentWelcomeHero({
    super.key,
    required this.fullName,
    required this.homeLabel,
    required this.apartmentCount,
    required this.doorCount,
    required this.onlineDoorCount,
    required this.pendingRequestCount,
    required this.primaryDoor,
    required this.isOpening,
    required this.onOpenDoor,
    required this.onShowQr,
    required this.onGuestPass,
  });

  final String fullName;
  final String homeLabel;
  final int apartmentCount;
  final int doorCount;
  final int onlineDoorCount;
  final int pendingRequestCount;
  final DoorRecord? primaryDoor;
  final bool isOpening;
  final VoidCallback? onOpenDoor;
  final VoidCallback? onShowQr;
  final VoidCallback? onGuestPass;

  String get _firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? 'Komşumuz' : parts.first;
  }

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 6) return 'İyi geceler';
    if (hour < 12) return 'Günaydın';
    if (hour < 18) return 'İyi günler';
    return 'İyi akşamlar';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    final door = primaryDoor;
    final doorModel = door == null
        ? null
        : IndividualDoorCardModel.of(door, isOpening: isOpening);
    final largeText = MediaQuery.textScalerOf(context).scale(16) >= 21;

    return Semantics(
      container: true,
      label: 'Daire kullanıcısı karşılama alanı',
      child: Container(
        key: const ValueKey('resident_welcome_hero'),
        decoration: BoxDecoration(
          color: p.critical,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: p.criticalBorder),
          boxShadow: p.shadow(2),
        ),
        padding: const EdgeInsets.all(AppSpace.xl),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 680 || largeText;
            final intro = _WelcomeIntro(
              greeting: '$_greeting, $_firstName',
              homeLabel: homeLabel,
              apartmentCount: apartmentCount,
              doorCount: doorCount,
              onlineDoorCount: onlineDoorCount,
              pendingRequestCount: pendingRequestCount,
              foreground: p.onCritical,
              textTheme: th,
            );
            final keyPanel = _DoorKeyPanel(
              door: door,
              model: doorModel,
              foreground: p.onCritical,
              surface: p.surface,
              surfaceText: p.text,
              statusOk: p.statusOk,
              statusCrit: p.statusCrit,
              onOpenDoor: onOpenDoor,
              onShowQr: onShowQr,
              onGuestPass: onGuestPass,
            );

            if (stacked) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  intro,
                  const SizedBox(height: AppSpace.xl),
                  keyPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: intro),
                const SizedBox(width: AppSpace.xl),
                Expanded(flex: 5, child: keyPanel),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WelcomeIntro extends StatelessWidget {
  const _WelcomeIntro({
    required this.greeting,
    required this.homeLabel,
    required this.apartmentCount,
    required this.doorCount,
    required this.onlineDoorCount,
    required this.pendingRequestCount,
    required this.foreground,
    required this.textTheme,
  });

  final String greeting;
  final String homeLabel;
  final int apartmentCount;
  final int doorCount;
  final int onlineDoorCount;
  final int pendingRequestCount;
  final Color foreground;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    final stats = <({IconData icon, String label})>[
      (icon: Icons.home_rounded, label: '$apartmentCount daire'),
      (icon: Icons.door_front_door_rounded, label: '$doorCount kapı'),
      (icon: Icons.wifi_rounded, label: '$onlineDoorCount çevrimiçi'),
      if (pendingRequestCount > 0)
        (icon: Icons.schedule_rounded, label: '$pendingRequestCount bekleyen'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: foreground.withValues(alpha: 0.24)),
          ),
          child: Icon(Icons.key_rounded, color: foreground),
        ),
        const SizedBox(height: AppSpace.lg),
        Text(
          greeting,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.headlineSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: AppSpace.xs),
        Text(
          homeLabel.isEmpty ? 'Evinize hoş geldiniz' : homeLabel,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodyLarge?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
        const SizedBox(height: AppSpace.lg),
        Wrap(
          spacing: AppSpace.sm,
          runSpacing: AppSpace.sm,
          children: [
            for (final stat in stats)
              _HeroStat(icon: stat.icon, label: stat.label, color: foreground),
          ],
        ),
      ],
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      border: Border.all(color: color.withValues(alpha: 0.2)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DoorKeyPanel extends StatelessWidget {
  const _DoorKeyPanel({
    required this.door,
    required this.model,
    required this.foreground,
    required this.surface,
    required this.surfaceText,
    required this.statusOk,
    required this.statusCrit,
    required this.onOpenDoor,
    required this.onShowQr,
    required this.onGuestPass,
  });

  final DoorRecord? door;
  final IndividualDoorCardModel? model;
  final Color foreground;
  final Color surface;
  final Color surfaceText;
  final Color statusOk;
  final Color statusCrit;
  final VoidCallback? onOpenDoor;
  final VoidCallback? onShowQr;
  final VoidCallback? onGuestPass;

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final m = model;
    final statusColor = m?.isOnline == true ? statusOk : statusCrit;
    final canOpen = m?.openKind != IndividualDoorOpenKind.none;

    return Container(
      padding: const EdgeInsets.all(AppSpace.lg),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: foreground.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HIZLI ERİŞİM',
                style: th.labelSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                door == null
                    ? 'Kapı erişimi bekleniyor'
                    : 'Hızlı erişim · ${door!.doorName}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: th.titleMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: AppSpace.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          m?.deviceStatusLabel ?? 'Bekliyor',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: th.labelSmall?.copyWith(
                            color: foreground,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.lg),
          if (canOpen)
            SizedBox(
              height: 58,
              child: FilledButton.icon(
                key: const ValueKey('resident_primary_door_action'),
                onPressed: m!.isOpening ? null : onOpenDoor,
                style: FilledButton.styleFrom(
                  backgroundColor: surface,
                  foregroundColor: surfaceText,
                  disabledBackgroundColor: surface.withValues(alpha: 0.65),
                  disabledForegroundColor: surfaceText.withValues(alpha: 0.65),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                icon: Icon(
                  m.isOpening ? Icons.sync_rounded : Icons.lock_open_rounded,
                ),
                label: Text(
                  m.isOpening ? 'AÇILIYOR' : m.openLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            )
          else
            Text(
              door == null
                  ? 'Yöneticiniz kapı yetkisi verdiğinde burada görünecek.'
                  : 'Bu kapı QR ile geçiş için yapılandırılmış.',
              style: th.bodyMedium?.copyWith(color: foreground, height: 1.4),
            ),
          if (m?.showShowQr == true || m?.showGuestPass == true) ...[
            const SizedBox(height: AppSpace.sm),
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.sm,
              children: [
                if (m?.showShowQr == true)
                  _HeroSecondaryAction(
                    label: 'QR Göster',
                    icon: Icons.qr_code_rounded,
                    color: foreground,
                    onPressed: onShowQr,
                  ),
                if (m?.showGuestPass == true)
                  _HeroSecondaryAction(
                    label: 'Misafir Geçişi',
                    icon: Icons.person_add_alt_1_rounded,
                    color: foreground,
                    onPressed: onGuestPass,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroSecondaryAction extends StatelessWidget {
  const _HeroSecondaryAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: onPressed,
    style: OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.34)),
      minimumSize: const Size(0, 44),
    ),
    icon: Icon(icon, size: 18),
    label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
  );
}
