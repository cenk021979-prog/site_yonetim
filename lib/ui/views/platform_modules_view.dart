import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Platform geneli modül yönetimi (Katman 1 Master Anahtarı).
/// Yalnızca Süper Kullanıcı tarafından görülebilir ve yönetilebilir.
/// Siteler ekranı (`SitesView`) ile birebir uyumlu simetrik iki büyük bloklu master-detail mimarisindedir:
/// - Sol Blok: Modül Listesi (filtre çipleri: Tümü, Devrede, Devre Dışı, Temel, Ek)
/// - Sağ Blok: Seçili Modül Detayı, Kapsamı, Açıklaması ve Platform Durumu Anahtarı
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

  String _filter = 'all'; // 'all', 'active', 'inactive', 'core', 'optional'
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    if (widget.showOnlyActive == true) {
      _filter = 'active';
    } else if (widget.showOnlyActive == false) {
      _filter = 'inactive';
    }
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
        if (_selectedCode == null || !list.any((m) => m.code == _selectedCode)) {
          _selectedCode = list.isNotEmpty ? list.first.code : null;
        }
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
          _buildMainLayout(modules),
      ],
    );
  }

  Widget _buildMainLayout(List<PlatformModule> modules) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final leftPane = _buildModuleListPane(context, modules, isWide: isWide);
        final rightPane = _buildModuleDetailsPane(context, modules, isWide: isWide);

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 5,
                child: leftPane,
              ),
              const SizedBox(width: AppSpace.md),
              Expanded(
                flex: 6,
                child: rightPane,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            leftPane,
            const SizedBox(height: AppSpace.lg),
            rightPane,
          ],
        );
      },
    );
  }

  /// Sol Blok: Siteler ekranı gibi çerçeveli Modül Listesi
  Widget _buildModuleListPane(
    BuildContext context,
    List<PlatformModule> modules, {
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerBorderColor = isDark
        ? Colors.redAccent.shade100.withValues(alpha: 0.6)
        : Colors.redAccent.shade700;

    final containerBg = isDark
        ? const Color(0xFF1E232A)
        : const Color(0xFFFAFAFC);

    final activeCount = modules.where((m) => m.isPlatformActive).length;
    final inactiveCount = modules.where((m) => !m.isPlatformActive).length;
    final coreCount = modules.where((m) => m.core).length;
    final optionalCount = modules.where((m) => !m.core).length;

    final filtered = _applyFilter(modules, _filter);

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
          // Ana Başlık
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Modül Listesi (${modules.length} Modül)',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Sistemdeki tüm platform modülleri ve durumları.',
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
              IconButton(
                onPressed: _loading ? null : loadData,
                icon: const Icon(Icons.refresh),
                tooltip: 'Listeyi Yenile',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.sm),

          // Filtre Çipleri
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: [
              _buildFilterChip('all', 'Tümü (${modules.length})', isDark, modules),
              _buildFilterChip('active', 'Devrede ($activeCount)', isDark, modules,
                  color: AppColors.success),
              _buildFilterChip('inactive', 'Devre Dışı ($inactiveCount)', isDark, modules,
                  color: AppColors.error),
              _buildFilterChip('core', 'Temel ($coreCount)', isDark, modules,
                  color: AppColors.primary),
              _buildFilterChip('optional', 'Ek ($optionalCount)', isDark, modules,
                  color: Colors.orange.shade700),
            ],
          ),
          const SizedBox(height: AppSpace.md),

          // Alt Grup: Kayıtlı Modüller
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Kayıtlı Modüller',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${filtered.length} Adet',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.blue.shade200 : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            'Detaylarını ve ayarlarını sağda incelemek için bir modül seçin.',
            style: TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.md),

          if (filtered.isEmpty)
            const EmptyCard(
              icon: Icons.widgets_outlined,
              title: 'Bu filtreye uygun modül bulunamadı.',
            )
          else
            for (var i = 0; i < filtered.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i < filtered.length - 1 ? AppSpace.sm : 0,
                ),
                child: StaggeredEntry(
                  index: i,
                  child: _buildModuleListCard(context, filtered[i], isDark),
                ),
              ),
        ],
      ),
    );
  }

  List<PlatformModule> _applyFilter(List<PlatformModule> modules, String filter) {
    if (filter == 'active') {
      return modules.where((m) => m.isPlatformActive).toList();
    } else if (filter == 'inactive') {
      return modules.where((m) => !m.isPlatformActive).toList();
    } else if (filter == 'core') {
      return modules.where((m) => m.core).toList();
    } else if (filter == 'optional') {
      return modules.where((m) => !m.core).toList();
    }
    return modules;
  }

  Widget _buildFilterChip(
    String key,
    String label,
    bool isDark,
    List<PlatformModule> modules, {
    Color? color,
  }) {
    final isSelected = _filter == key;
    final themeColor = color ?? AppColors.primary;

    return InkWell(
      key: ValueKey('filter_chip_$key'),
      onTap: () {
        setState(() {
          _filter = key;
          final updatedFiltered = _applyFilter(modules, key);
          if (!updatedFiltered.any((m) => m.code == _selectedCode)) {
            _selectedCode = updatedFiltered.isNotEmpty ? updatedFiltered.first.code : null;
          }
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? themeColor.withValues(alpha: isDark ? 0.3 : 0.15)
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? themeColor
                : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected
                ? (isDark ? Colors.white : themeColor)
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  /// Sol listedeki modül kartı: Tıklandığında sağ paneli açar + switch ile anında açılıp kapanabilir
  Widget _buildModuleListCard(
    BuildContext context,
    PlatformModule module,
    bool isDark,
  ) {
    final isSelected = _selectedCode == module.code;
    final isBusy = _busyCodes.contains(module.code);
    final isActive = module.isPlatformActive;
    final icon = _getModuleIcon(module.code);

    final cardBg = isSelected
        ? (isDark ? const Color(0xFF222C3A) : const Color(0xFFEFF6FF))
        : (isDark ? const Color(0xFF282F3A) : Colors.white);

    final cardBorderColor = isSelected
        ? (isDark ? Colors.blueAccent : AppColors.primary)
        : (isDark ? Colors.white12 : const Color(0xFFE2E8F0));

    return InkWell(
      key: ValueKey('module_card_${module.code}'),
      onTap: () {
        setState(() {
          _selectedCode = module.code;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cardBorderColor,
            width: isSelected ? 1.8 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.sm, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // İkon Kutusu
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isActive ? AppColors.success : AppColors.primary)
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isActive ? AppColors.success : AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpace.sm),

            // Modül Bilgileri
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        module.code,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textMuted,
                        ),
                      ),
                      // Temel / Ek Modül Rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: module.core
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          module.core ? 'Temel' : 'Ek Modül',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: module.core
                                ? (isDark ? Colors.blue.shade200 : AppColors.primary)
                                : Colors.orange.shade700,
                          ),
                        ),
                      ),
                      // Durum Rozeti
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.success.withValues(alpha: 0.12)
                              : (isDark ? Colors.white10 : Colors.black12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isActive ? 'Devrede' : 'Devre Dışı',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: isActive
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: AppSpace.xs),

            // Hızlı Switch
            if (isBusy)
              const SizedBox(
                width: 24,
                height: 24,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Transform.scale(
                scale: 0.8,
                child: Switch(
                  value: isActive,
                  activeThumbColor: AppColors.success,
                  onChanged: (val) => _toggleModule(module, val),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Sağ Blok: Seçili modülün detayları, kapsamı, açıklaması ve platform durumu
  Widget _buildModuleDetailsPane(
    BuildContext context,
    List<PlatformModule> modules, {
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final containerBorderColor = isDark
        ? Colors.redAccent.shade100.withValues(alpha: 0.6)
        : Colors.redAccent.shade700;

    final containerBg = isDark
        ? const Color(0xFF1E232A)
        : const Color(0xFFFAFAFC);

    final selected = modules.where((m) => m.code == _selectedCode).firstOrNull;

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
          // Ana Başlık
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected != null
                          ? '${selected.name} Yönetimi'
                          : 'Modül Ayarları & Yönetimi',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      selected != null
                          ? 'Modülün platform durumu, kullanım kapsamı ve ayarları.'
                          : 'İşlem yapmak için soldaki listeden bir modül seçin.',
                      style: const TextStyle(
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

          if (selected == null)
            const EmptyCard(
              icon: Icons.widgets_outlined,
              title: 'İşlem yapmak için soldaki listeden bir modül seçin.',
            )
          else ...[
            // Alt Grup 1: Genel Bilgiler
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Genel Bilgiler',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Modül Kodu: ${selected.code}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.blue.shade200 : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Modülün temel kimliği, açıklaması ve platform durumu.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            _buildModuleHeroCard(context, selected, isDark),

            const SizedBox(height: AppSpace.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpace.md),

            // Alt Grup 2: Dağıtım ve Yetkilendirme Kuralı
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Dağıtım ve Yetkilendirme',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (selected.core ? AppColors.primary : Colors.orange)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    selected.core ? 'Otomatik Dağıtım' : 'Talep Usulü',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected.core
                          ? (isDark ? Colors.blue.shade200 : AppColors.primary)
                          : Colors.orange.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Bu modülün sitelere ve kullanıcılara nasıl sunulduğu.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            _buildModuleRulesCard(context, selected, isDark),

            const SizedBox(height: AppSpace.lg),
            const Divider(height: 1),
            const SizedBox(height: AppSpace.md),

            // Alt Grup 3: Sistem & Veritabanı Bakımı
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  'Sistem Bakımı',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Veritabanı',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.blue.shade200 : AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Modül veritabanı optimizasyonu ve artık kayıt temizliği.',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
            const SizedBox(height: AppSpace.sm),
            _buildMaintenanceCard(context, isDark),
          ],
        ],
      ),
    );
  }

  /// Seçili modülün durum ve anahtar kartı
  Widget _buildModuleHeroCard(
    BuildContext context,
    PlatformModule module,
    bool isDark,
  ) {
    final th = Theme.of(context).textTheme;
    final isActive = module.isPlatformActive;
    final isBusy = _busyCodes.contains(module.code);
    final icon = _getModuleIcon(module.code);

    return AppCard(
      level: 2,
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(
                icon: icon,
                tone: isActive ? AppTone.success : AppTone.primary,
                size: 48,
                gap: AppSpace.md,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      module.name,
                      style: th.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: AppSpace.sm,
                      runSpacing: AppSpace.xs,
                      children: [
                        StatusChip(
                          label: module.core ? 'Temel Modül (Core)' : 'Ek Modül (Seçmeli)',
                          tone: module.core ? AppTone.info : AppTone.warning,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpace.xs),
                    Text(
                      'Sistem Tanımı: ${module.code}',
                      style: th.bodySmall?.copyWith(color: AppColors.textMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Text(
            module.description.isNotEmpty
                ? module.description
                : 'Bu modül için sisteme girilmiş detaylı bir açıklama metni bulunmuyor.',
            style: th.bodyMedium?.copyWith(
              height: 1.35,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),

          // Durum ve Eylem Satırı
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            runSpacing: AppSpace.sm,
            spacing: AppSpace.md,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.success : AppColors.textMuted,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Text(
                    isActive
                        ? 'Platform Genelinde Devrede'
                        : 'Platform Genelinde Devre Dışı',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isActive ? AppColors.success : AppColors.textMuted,
                    ),
                  ),
                ],
              ),
              ElevatedButton(
                onPressed: isBusy
                    ? null
                    : () => _toggleModule(module, !isActive),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isActive ? AppColors.error : AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpace.md,
                    vertical: AppSpace.sm,
                  ),
                  minimumSize: const Size(0, 42),
                ),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (isBusy)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      Icon(
                        isActive
                            ? Icons.pause_circle_outline_rounded
                            : Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                    Text(
                      isActive ? 'Modülü Pasife Al' : 'Modülü Devreye Al',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Dağıtım ve yetki kuralları kartı
  Widget _buildModuleRulesCard(
    BuildContext context,
    PlatformModule module,
    bool isDark,
  ) {
    final th = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                module.core
                    ? Icons.auto_awesome_rounded
                    : Icons.assignment_turned_in_rounded,
                color: module.core ? AppColors.primary : Colors.orange.shade700,
                size: 20,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  module.core
                      ? 'Temel Modül Kuralı (Otomatik Dağıtım):'
                      : 'Ek Modül Kuralı (Talep Usulü):',
                  style: th.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            module.core
                ? 'Bu modül platform genelinde devreye alındığında, sistemde kayıtlı tüm mevcut sitelerde ve sonradan kurulacak yeni sitelerde otomatik olarak aktif olur. Site yöneticisinin ayrıca başvuru yapması gerekmez.'
                : 'Bu modül platform genelinde devreye alındığında, site yöneticileri "Modüller" ekranı üzerinden siteleri için talep gönderebilir. Süper kullanıcının onayı ile siteye tanımlanır.',
            style: th.bodySmall?.copyWith(
              color: AppColors.textMuted,
              height: 1.35,
            ),
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.sm),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(
                'Erişebilen Roller:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
              _buildRoleBadge('Süper Kullanıcı', AppColors.primary, isDark),
              _buildRoleBadge('Site Yöneticisi', AppColors.success, isDark),
              if (module.code == 'people' ||
                  module.code == 'finance' ||
                  module.code == 'announcements' ||
                  module.code == 'door_control' ||
                  module.code == 'survey' ||
                  module.code == 'drive_storage' ||
                  module.code == 'neighbor_board' ||
                  module.code == 'reservation')
                _buildRoleBadge('Daire Sakini', Colors.purple, isDark),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String label, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  /// Veritabanı temizleme bakım kartı
  Widget _buildMaintenanceCard(BuildContext context, bool isDark) {
    final th = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Veritabanı Bakımı ve İlişki Temizliği',
            style: th.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Kullanılmayan modül ilişkilerini ve silinmiş talep kayıtlarını temizler; veritabanını optimize eder.',
            style: th.bodySmall?.copyWith(color: AppColors.textMuted),
          ),
          const SizedBox(height: AppSpace.md),
          ElevatedButton(
            onPressed: _loading ? null : cleanupDatabase,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              minimumSize: const Size(0, 40),
            ),
            child: const Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: [
                Icon(Icons.cleaning_services_rounded, size: 16),
                Text('Veritabanını Temizle (VACUUM)'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
