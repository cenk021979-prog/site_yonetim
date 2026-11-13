import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart' show InlineNotice;
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Platform geneli modül yönetimi (Katman 1 Master Anahtarı).
/// Yalnızca Süper Kullanıcı tarafından görülebilir ve yönetilebilir.
/// Görseldeki ikili modern panel mimarisine göre gruplandırılmıştır:
/// 1. Devreye Alınan Modüller (Temel ve Ek modüller)
/// 2. Devreye Alınmayan Modüller (Temel ve Ek modüller)
/// Her modülün altında anında "Devreye al / Devreden çıkar" switch butonu yer alır.
class PlatformModulesView extends StatefulWidget {
  const PlatformModulesView({
    super.key,
    required this.authService,
    this.showOnlyActive,
    this.onChanged,
  });

  final AuthService authService;
  final bool? showOnlyActive;
  final VoidCallback? onChanged;

  @override
  State<PlatformModulesView> createState() => PlatformModulesViewState();
}

class PlatformModulesViewState extends State<PlatformModulesView> {
  List<PlatformModule>? _modules;
  bool _loading = false;
  String? _error;
  final Set<String> _busyCodes = <String>{};

  @override
  void initState() {
    super.initState();
    unawaited(loadData());
  }

  Future<void> loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await widget.authService.getPlatformModules();
      if (!mounted) return;
      setState(() {
        _modules = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e is ApiException ? e.message : 'Platform modülleri yüklenemedi.';
        _loading = false;
      });
    }
  }

  Future<void> _toggleModule(PlatformModule module, bool isActive) async {
    final code = module.code;
    if (_busyCodes.contains(code)) return;

    setState(() => _busyCodes.add(code));
    try {
      await widget.authService.setPlatformModuleActive(code, isActive);
      if (!mounted) return;
      AppSnack.show(
        context,
        isActive
            ? '${module.name} DEVREYE ALINDI (Platform genelinde aktif).'
            : '${module.name} DEVREDEN ÇIKARILDI (Pasife alındı).',
        kind: AppSnackKind.success,
      );
      widget.onChanged?.call();
      await loadData();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Modül durumu güncellenemedi.';
      AppSnack.show(context, msg, kind: AppSnackKind.error);
    } finally {
      if (mounted) {
        setState(() => _busyCodes.remove(code));
      }
    }
  }

  Future<void> cleanupDatabase() async {
    setState(() => _loading = true);
    try {
      final res = await widget.authService.cleanupPlatformModules();
      if (!mounted) return;
      final sm = res['deletedSiteModulesCount'] ?? 0;
      final mr = res['deletedModuleRequestsCount'] ?? 0;
      final vac = res['vacuumExecuted'] == true ? ' ve VACUUM yapıldı.' : '.';
      AppSnack.show(
        context,
        'Veritabanı temizlendi: $sm site modülü, $mr talep silindi$vac',
        kind: AppSnackKind.success,
      );
      widget.onChanged?.call();
      await loadData();
    } catch (e) {
      if (!mounted) return;
      final msg = e is ApiException ? e.message : 'Veritabanı temizlenemedi.';
      AppSnack.show(context, msg, kind: AppSnackKind.error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  IconData _getModuleIcon(String code) {
    switch (code) {
      case 'people':
        return Icons.people_alt_rounded;
      case 'door_control':
        return Icons.door_sliding_rounded;
      case 'plate_recognition':
        return Icons.camera_alt_rounded;
      case 'finance':
        return Icons.account_balance_wallet_rounded;
      case 'announcements':
        return Icons.campaign_rounded;
      case 'directory':
        return Icons.contact_phone_rounded;
      case 'drive_storage':
        return Icons.folder_shared_rounded;
      case 'reservation':
        return Icons.event_seat_rounded;
      case 'work_tracking':
        return Icons.build_circle_rounded;
      case 'metering':
        return Icons.speed_rounded;
      case 'online_payment':
        return Icons.credit_card_rounded;
      case 'survey':
        return Icons.poll_rounded;
      case 'visitor_log':
        return Icons.badge_rounded;
      case 'card_access':
        return Icons.badge_outlined;
      case 'contracts':
        return Icons.handshake_rounded;
      case 'decision_book':
        return Icons.menu_book_rounded;
      case 'budget':
        return Icons.calculate_rounded;
      case 'neighbor_board':
        return Icons.dashboard_customize_rounded;
      case 'annual_report':
        return Icons.assessment_rounded;
      case 'hgs_access':
        return Icons.directions_car_rounded;
      case 'equipment':
        return Icons.inventory_2_rounded;
      default:
        return Icons.extension_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final modules = _modules ?? <PlatformModule>[];
    final deployedList = modules.where((m) => m.isPlatformActive).toList();
    final undeployedList = modules.where((m) => !m.isPlatformActive).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_loading && _modules == null)
          const ListSkeleton(rows: 5)
        else if (_error != null && _modules == null)
          InlineNotice(
            message: _error!,
            onRetry: loadData,
          )
        else if (_modules != null)
          _buildMainContent(deployedList, undeployedList),
      ],
    );
  }

  Widget _buildMainContent(List<PlatformModule> deployedList, List<PlatformModule> undeployedList) {
    if (widget.showOnlyActive == true) {
      return _buildSectionContainer(
        title: 'Devreye Alınan Modüller',
        subtitle: 'Kullanıcıların ve sitelerin hizmetine sunulmuş modüller.',
        modules: deployedList,
        isDeployed: true,
      );
    }

    if (widget.showOnlyActive == false) {
      return _buildSectionContainer(
        title: 'Devreye Alınmayan Modüller',
        subtitle: 'Tasarımı devam eden, kullanıcılara ve menülere kapalı modüller.',
        modules: undeployedList,
        isDeployed: false,
      );
    }

    // Görseldeki gibi iki büyük blok (Yan yana veya genişliğe göre alt alta)
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 960;
        final leftBox = _buildSectionContainer(
          title: 'Devreye Alınan Modüller',
          subtitle: 'Hizmete sunulmuş modüller.',
          modules: deployedList,
          isDeployed: true,
        );
        final rightBox = _buildSectionContainer(
          title: 'Devreye Alınmayan Modüller',
          subtitle: 'Tasarımı devam eden pasif modüller.',
          modules: undeployedList,
          isDeployed: false,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: leftBox),
              const SizedBox(width: AppSpace.md),
              Expanded(child: rightBox),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leftBox,
            const SizedBox(height: AppSpace.lg),
            rightBox,
          ],
        );
      },
    );
  }

  /// Görseldeki büyük kırmızı çerçeveli modül grubu kutusu
  Widget _buildSectionContainer({
    required String title,
    required String subtitle,
    required List<PlatformModule> modules,
    required bool isDeployed,
  }) {
    final temelModules = modules.where((m) => m.core).toList();
    final ekModules = modules.where((m) => !m.core).toList();

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Görseldeki kırmızı çerçeveli modern hat
    final containerBorderColor = isDeployed
        ? (isDark ? Colors.redAccent.shade100.withValues(alpha: 0.6) : Colors.redAccent.shade700)
        : (isDark ? Colors.redAccent.shade100.withValues(alpha: 0.6) : Colors.redAccent.shade700);

    final containerBg = isDark
        ? const Color(0xFF1E232A)
        : const Color(0xFFFAFAFC);

    return Container(
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: containerBorderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Ana Başlık: Devreye alınan modüller .... Adet
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDeployed
                      ? AppColors.success.withValues(alpha: 0.15)
                      : AppColors.error.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDeployed ? Icons.verified_rounded : Icons.pause_circle_filled_rounded,
                  color: isDeployed ? AppColors.success : AppColors.error,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$title (${modules.length} Adet)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),

          // Alt Grup 1: Temel Modüller
          _buildSubGroup(
            subTitle: 'Temel Modüller',
            infoText: isDeployed
                ? 'Site oluşturan her sitede otomatik aktif olur.'
                : 'Tasarımı devam eden temel modüller (Aktif edilince tüm sitelere otomatik açılır).',
            modules: temelModules,
            isDeployed: isDeployed,
            badgeColor: AppColors.primary,
          ),

          const SizedBox(height: AppSpace.lg),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),

          // Alt Grup 2: Ek Modüller
          _buildSubGroup(
            subTitle: 'Ek Modüller',
            infoText: isDeployed
                ? 'İhtiyaç halinde yöneticilerin talep edebileceği modüller.'
                : 'Tasarımı devam eden ek modüller (Aktif edilince yöneticiler talep edebilir).',
            modules: ekModules,
            isDeployed: isDeployed,
            badgeColor: Colors.orange.shade700,
          ),
        ],
      ),
    );
  }

  Widget _buildSubGroup({
    required String subTitle,
    required String infoText,
    required List<PlatformModule> modules,
    required bool isDeployed,
    required Color badgeColor,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final cardWidth = availableWidth < 480 ? availableWidth : 230.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  subTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${modules.length} Adet',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              infoText,
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.sm),

            if (modules.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Bu grupta modül bulunmuyor.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              )
            else
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                children: modules.map((m) => _buildModuleCard(m, cardWidth)).toList(),
              ),
          ],
        );
      },
    );
  }

  /// Görseldeki modül kutusu: Altında switch button ile birlikte
  Widget _buildModuleCard(PlatformModule module, double cardWidth) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBusy = _busyCodes.contains(module.code);
    final isActive = module.isPlatformActive;

    final icon = _getModuleIcon(module.code);

    // Kırmızı/yeşil tonlu modern kart sınırları
    final cardBorderColor = isActive
        ? (isDark ? Colors.teal.shade700 : Colors.teal.shade300)
        : (isDark ? Colors.grey.shade700 : Colors.grey.shade300);

    final cardBg = isDark
        ? const Color(0xFF282F3A)
        : Colors.white;

    final footerBg = isDark
        ? const Color(0xFF202630)
        : const Color(0xFFF7F8FA);

    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Üst Kısım: İkon + Modül Başlığı + Tür Rozeti
          Padding(
            padding: const EdgeInsets.all(AppSpace.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (isActive ? AppColors.success : AppColors.primary)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        color: isActive ? AppColors.success : AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            module.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              height: 1.2,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            module.code,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: AppColors.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Açıklama metni
                Text(
                  module.description.isNotEmpty
                      ? module.description
                      : 'Modül açıklaması bulunmuyor.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          const SizedBox(height: 4),

          // ALT KISIM: Switch Button ve Durum Bildirimi
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: footerBg,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    isActive ? 'Devrede' : 'Devre Dışı',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: isActive ? AppColors.success : AppColors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isBusy)
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Transform.scale(
                    scale: 0.85,
                    child: Switch(
                      value: isActive,
                      activeThumbColor: AppColors.success,
                      onChanged: (val) => _toggleModule(module, val),
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
