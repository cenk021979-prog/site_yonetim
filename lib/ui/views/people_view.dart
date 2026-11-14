import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart' show BulkExportFilters, ImportKind;
import 'package:site_kapi_kontrol/models/platform_module.dart' show MySiteModules;
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart' show BulkService;
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/dialogs/apartment_admin_dialogs.dart';
import 'package:site_kapi_kontrol/ui/design/action_bar.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_apartments_tab.dart';
import 'package:site_kapi_kontrol/ui/views/people_persons_tab.dart';
import 'package:site_kapi_kontrol/ui/views/people_team_tab.dart';
import 'package:site_kapi_kontrol/ui/views/people_vehicles_tab.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sources.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/people_section_navigation.dart';

/// "Kişiler" ekranı (çekirdek `people` modülü): varsayılan kişi listesi,
/// doğrudan Daireler/Kadro erişimi ve İşlemler menüsünde genel araç kayıtları.
///
/// - [manageSites] true (site yöneticisi yönetici modunda / süper kullanıcı): yönettiği (ya da tüm)
///   onaylı siteler listelenir ve yazma yetkisi vardır.
/// - [readOnlySites]: kurul üyesi olunan siteler (`GET /app/my-modules` rolü `board_member`); bu
///   sitelerde HİÇBİR yazma düğmesi çizilmez. Yönetilen bir site de listede varsa yazma yetkisi korunur.
///
/// Sekmeler tembel kurulur ve görünmediklerinde bile durumlarını korur. Bir sekmede yapılan değişiklik
/// diğer sekmeleri "bayat" işaretler; o sekmeye geçilince veri yeniden çekilir. Site değişince tüm sekme
/// durumları atılır (eski sitenin yanıtı yeni sitenin ekranına yazılamaz). Veriyi kendisi çeker;
/// [PeopleViewState.reload] sayfa kabuğunun aşağı çekip yenilemesinden de çağrılır.
class PeopleView extends StatefulWidget {
  const PeopleView({
    super.key,
    required this.authService,
    this.manageSites = true,
    this.readOnlySites = const <PeopleSite>[],
    this.onDataChanged,
    this.initialSiteCode,
    this.initialTab,
  });

  final AuthService authService;
  final bool manageSites;
  final List<PeopleSite> readOnlySites;
  final VoidCallback? onDataChanged;

  /// Kurulum sihirbazı gibi dış giriş noktalarından açılan site (listede yoksa ilk site seçilir).
  final int? initialSiteCode;

  /// Açılışta seçili sekme (0 Kişiler, 1 Daireler, 2 Araçlar, 3 Kadro); aralık dışıysa ilk sekme.
  final int? initialTab;

  @override
  State<PeopleView> createState() => PeopleViewState();
}

class PeopleViewState extends State<PeopleView> {
  static const _tabs = ['Kişiler', 'Daireler', 'Araçlar', 'Kadro'];

  List<PeopleSite> _sites = const <PeopleSite>[];
  int? _siteCode;
  bool _loadingSites = false;
  bool _sitesLoadedOnce = false;
  String? _sitesError;
  int _sitesToken = 0;

  int _tab = 0;
  final Set<int> _visited = <int>{0};
  final Set<int> _dirty = <int>{};

  // Dış giriş noktasından (kurulum sihirbazı) istenen sekme: ilk site seçiminde bir kez uygulanır.
  int? _pendingTab;

  // Site değişince yenilenir: eski sitenin sekme durumları (ve uçuştaki yanıtları) atılır.
  GlobalKey<PeoplePersonsTabState> _personsKey = GlobalKey<PeoplePersonsTabState>();
  GlobalKey<PeopleApartmentsTabState> _apartmentsKey =
      GlobalKey<PeopleApartmentsTabState>();
  GlobalKey<PeopleVehiclesTabState> _vehiclesKey = GlobalKey<PeopleVehiclesTabState>();
  GlobalKey<PeopleTeamTabState> _teamKey = GlobalKey<PeopleTeamTabState>();

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    _pendingTab = tab != null && tab >= 0 && tab < _tabs.length ? tab : null;
    unawaited(reload());
  }

  @override
  void didUpdateWidget(PeopleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.manageSites != widget.manageSites ||
        !listEquals(oldWidget.readOnlySites, widget.readOnlySites)) {
      unawaited(reload());
    }
  }

  @override
  void dispose() {
    ++_sitesToken;
    super.dispose();
  }

  PeopleSite? get _site {
    final code = _siteCode;
    if (code == null) return null;
    for (final site in _sites) {
      if (site.code == code) return site;
    }
    return null;
  }

  /// Siteleri ve görünen sekmenin verisini yeniden çeker (mevcut ekran yenileme sürerken korunur).
  Future<void> reload() async {
    if (!mounted) return;
    final token = ++_sitesToken;
    setState(() {
      _loadingSites = true;
      _sitesError = null;
    });
    try {
      final merged = <PeopleSite>[];
      if (widget.manageSites) {
        // Süper kullanıcıda site sayısı 100'ü aşabilir: onaylı siteler sayfa sayfa toplanır (üst sınır 50
        // sayfa), seçici ilk 100 siteyle sınırlı kalmaz.
        var pageNo = 1;
        var fetched = 0;
        while (true) {
          final page = await widget.authService.listSites(
            page: pageNo,
            pageSize: 100,
            approvalStatus: 'approved',
          );
          for (final site in page.sites) {
            if (site.isApproved && !merged.any((m) => m.code == site.id)) {
              merged.add(PeopleSite(
                code: site.id,
                name: site.name,
                canWrite: true,
                terms: site.managementTerms,
              ));
            }
          }
          fetched += page.sites.length;
          if (page.sites.isEmpty || fetched >= page.total || pageNo >= 50) break;
          if (!mounted || token != _sitesToken) return;
          pageNo++;
        }
      }
      // F9: kurul üyesi siteleri (salt okunur) terimlerini son `my-modules` yanıtından alır; yanıt yoksa ya da
      // eski sunucuda alan yoksa varsayılan terimler (Daire / Sakin / ...).
      final cachedSites = widget.authService.cachedMyModules?.sites ?? const <MySiteModules>[];
      for (final site in widget.readOnlySites) {
        if (!merged.any((m) => m.code == site.code)) {
          var terms = site.terms;
          if (terms.isDefault) {
            for (final cached in cachedSites) {
              if (cached.siteCode == site.code) {
                terms = cached.managementTerms;
                break;
              }
            }
          }
          merged.add(PeopleSite(code: site.code, name: site.name, terms: terms));
        }
      }
      if (!mounted || token != _sitesToken) return;
      final keep = _siteCode != null && merged.any((s) => s.code == _siteCode);
      final wanted = widget.initialSiteCode;
      final preferred = !keep && wanted != null && merged.any((s) => s.code == wanted);
      final next = keep ? _siteCode : (preferred ? wanted : (merged.isEmpty ? null : merged.first.code));
      final siteChanged = next != _siteCode;
      final previous = _site;
      setState(() {
        _sites = merged;
        _loadingSites = false;
        _sitesLoadedOnce = true;
        if (siteChanged) _resetTabs(next);
      });
      // Aynı site: ekrandaki sekme yeniden çekilir, diğerleri bayatlar. Yetki değiştiyse (ör. kurul
      // üyeliği yönetime döndü) sekme durumu atılır.
      final current = _site;
      if (!siteChanged && current != null) {
        if (previous != null && previous.canWrite != current.canWrite) {
          setState(() => _resetTabs(current.code));
        } else {
          _reloadVisibleTab();
          _markOthersDirty(_tab);
        }
      }
    } catch (e) {
      if (!mounted || token != _sitesToken) return;
      setState(() {
        _loadingSites = false;
        _sitesError = crmMessageOf(
          e,
          'Siteler yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.',
        );
      });
    }
  }

  void _resetTabs(int? siteCode) {
    _siteCode = siteCode;
    _tab = _pendingTab ?? 0;
    _pendingTab = null;
    _visited
      ..clear()
      ..add(_tab);
    _dirty.clear();
    _personsKey = GlobalKey<PeoplePersonsTabState>();
    _apartmentsKey = GlobalKey<PeopleApartmentsTabState>();
    _vehiclesKey = GlobalKey<PeopleVehiclesTabState>();
    _teamKey = GlobalKey<PeopleTeamTabState>();
  }

  void _reloadVisibleTab() {
    switch (_tab) {
      case 0:
        unawaited(_personsKey.currentState?.reload() ?? Future<void>.value());
      case 1:
        unawaited(_apartmentsKey.currentState?.reload() ?? Future<void>.value());
      case 2:
        unawaited(_vehiclesKey.currentState?.reload() ?? Future<void>.value());
      case 3:
        unawaited(_teamKey.currentState?.reload() ?? Future<void>.value());
    }
  }

  void _markOthersDirty(int source) {
    for (final index in _visited) {
      if (index != source) _dirty.add(index);
    }
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    final stale = _dirty.remove(index);
    setState(() {
      _tab = index;
      _visited.add(index);
    });
    if (stale) {
      // Sekme zaten kurulu: veriyi çerçeveden sonra yeniden çeker.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _tab == index) _reloadVisibleTab();
      });
    }
  }

  void _selectSite(int code) {
    if (code == _siteCode) return;
    setState(() => _resetTabs(code));
  }

  /// «Toplu Yükle» sihirbazını açar (Platform Faz 2b). Kayıtlar değiştiyse görünen sekme yeniden çekilir, diğerleri
  /// bayatlar; «Kişilere git» ilgili sekmeye geçirir.
  Future<void> _openBulkImport(PeopleScope scope, {ImportKind? kind}) async {
    final outcome = await BulkImportView.open(context, scope: scope, initialKind: kind);
    if (!mounted || outcome == null || scope.siteCode != _siteCode) return;
    if (outcome.changed) {
      _markOthersDirty(_tab);
      _reloadVisibleTab();
      widget.onDataChanged?.call();
    }
    final tab = outcome.goToTab;
    if (tab != null && tab != _tab) _selectTab(tab);
  }

  /// Tek dosyada tüm kişi, daire, araç ve kadro kayıtları.
  Future<void> _openBulkExport(PeopleScope scope) {
    return ExportSheet.show(
      context,
      combineSources: true,
      sources: buildCrmExportSources(
        service: BulkService(authService: widget.authService),
        combined: true,
        siteCode: scope.siteCode,
        persons: () => _personsKey.currentState?.exportFilters ?? const BulkExportFilters(),
        apartments: () => _apartmentsKey.currentState?.exportFilters ?? const BulkExportFilters(),
        vehicles: () => _vehiclesKey.currentState?.exportFilters ?? const BulkExportFilters(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final site = _site;
    final Widget content;
    if (site == null) {
      if (_loadingSites || (!_sitesLoadedOnce && _sitesError == null)) {
        content = const ListSkeleton(rows: 2);
      } else if (_sitesError != null) {
        content = InlineNotice(message: _sitesError!, onRetry: reload);
      } else {
        content = const EmptyCard(
          icon: Icons.apartment_rounded,
          title: 'Kayıtlı site bulunamadı.',
          message: 'Kişi ve daire kayıtları, bir siteye bağlı olduğunuzda burada görünür.',
        );
      }
    } else {
      content = _buildSite(context, site);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PageHeaderCard(
          title: 'Kişiler',
          help: 'Sitenizdeki kişileri, dairelerin malik ve kiracı bilgilerini ve araçları buradan yönetin.',
        ),
        const SizedBox(height: AppSpace.md),
        content,
      ],
    );
  }

  Widget _buildSite(BuildContext context, PeopleSite site) {
    final scope = PeopleScope(
      authService: widget.authService,
      siteCode: site.code,
      siteName: site.name,
      canWrite: site.canWrite,
      terms: site.terms,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final mq = MediaQuery.maybeOf(context);
        final isLandscape = mq?.orientation == Orientation.landscape ||
            (mq != null && mq.size.width > mq.size.height);
        // Geniş ekranda (Windows/Web/Tablet >= 720) veya telefon/tablet yatay modunda (landscape >= 500)
        // iki kart yan yana (master-detail) yerleşir; dikey mobil modda alt alta akar.
        final isWide =
            constraints.maxWidth >= 720 || (isLandscape && constraints.maxWidth >= 500);
        final leftPane = _buildMasterPane(context, site, scope, isWide: isWide);
        final rightPane = _buildDetailPane(context, site, scope, isWide: isWide);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_sitesError != null) ...[
              InlineNotice(message: _sitesError!, onRetry: reload),
              const SizedBox(height: AppSpace.md),
            ],
            if (isWide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: constraints.maxWidth >= 900 ? 5 : 1,
                    child: leftPane,
                  ),
                  const SizedBox(width: AppSpace.md),
                  Expanded(
                    flex: constraints.maxWidth >= 900 ? 6 : 1,
                    child: rightPane,
                  ),
                ],
              )
            else ...[
              leftPane,
              const SizedBox(height: AppSpace.lg),
              rightPane,
            ],
          ],
        );
      },
    );
  }

  /// Sol Blok (Master): Site Seçimi, Toplu İşlemler ve Bölüm Menüleri
  Widget _buildMasterPane(
    BuildContext context,
    PeopleSite site,
    PeopleScope scope, {
    required bool isWide,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final th = theme.textTheme;
    final p = context.palette;

    final containerBorderColor = isDark
        ? Colors.redAccent.shade100.withValues(alpha: 0.6)
        : Colors.redAccent.shade700;

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
          // Sol Blok Başlığı
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
                  Icons.people_alt_rounded,
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
                      'Sakinler & Kadro',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Text(
                      'Site sakinleri, daire kayıtları, araçlar ve yönetim kadrosu.',
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
                onPressed: reload,
                icon: const Icon(Icons.refresh),
                tooltip: 'Tümünü Yenile',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),

          // Site seçici veya etiketi
          if (_sites.length > 1)
            AppCard(
              child: DropdownButtonFormField<int>(
                key: ValueKey<String>('people_site_${site.code}_${_sites.length}'),
                isExpanded: true,
                initialValue: site.code,
                dropdownColor: p.surface,
                style: th.bodyMedium?.copyWith(color: p.text),
                decoration: const InputDecoration(
                  labelText: 'Site',
                  prefixIcon: Icon(Icons.apartment_rounded),
                ),
                items: [
                  for (final s in _sites)
                    DropdownMenuItem<int>(
                      value: s.code,
                      child: Text(
                        '${s.label} (${s.code})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) _selectSite(value);
                },
              ),
            )
          else
            Wrap(
              spacing: AppSpace.sm,
              runSpacing: AppSpace.xs,
              children: [InfoChip(site.label)],
            ),

          if (!site.canWrite) ...[
            const SizedBox(height: AppSpace.md),
            const InlineNotice(
              tone: AppTone.info,
              icon: Icons.visibility_rounded,
              message:
                  'Yönetim kurulu üyesi olarak kayıtları yalnızca görüntüleyebilirsiniz.',
            ),
          ],

          if (site.canWrite) ...[
            const SizedBox(height: AppSpace.md),
            Text(
              'Toplu İşlemler',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: AppSpace.xs),
            AppActionBar(
              actions: [
                AppBarAction(
                  actionKey: const ValueKey<String>('people_bulk_import'),
                  label: 'Toplu Yükle',
                  icon: Icons.upload_file_rounded,
                  primary: true,
                  onPressed: () => unawaited(_openBulkImport(scope)),
                ),
                AppBarAction(
                  actionKey: const ValueKey<String>('people_bulk_export'),
                  label: 'Dışa Aktar',
                  icon: Icons.download_rounded,
                  onPressed: () => unawaited(_openBulkExport(scope)),
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpace.md),
          Text(
            'Bölümler',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          PeopleSectionNavigation(
            selected: _tab,
            unitPlural: site.terms.unitPlural,
            onSelected: _selectTab,
            onSafetyRequests: site.canWrite && _tab == 3
                ? () => unawaited(_openSafetyRequests(site))
                : null,
          ),
        ],
      ),
    );
  }

  /// Sağ Blok (Detail): Menülere göre değişen dinamik içerik alanı
  Widget _buildDetailPane(
    BuildContext context,
    PeopleSite site,
    PeopleScope scope, {
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

    final IconData currentTabIcon;
    final String currentTabName;
    final String tabSubtitle;

    switch (_tab) {
      case 0:
        currentTabIcon = Icons.people_alt_rounded;
        currentTabName = 'Kişiler';
        tabSubtitle = 'Daire sakinleri, mülk sahipleri ve iletişim kayıtları.';
        break;
      case 1:
        currentTabIcon = Icons.apartment_rounded;
        currentTabName = site.terms.unitPlural;
        tabSubtitle = '${site.terms.unitPlural} ve ikamet edenlerin listesi.';
        break;
      case 2:
        currentTabIcon = Icons.directions_car_rounded;
        currentTabName = 'Araçlar';
        tabSubtitle = 'Siteye kayıtlı araç plakaları ve yetkileri.';
        break;
      case 3:
      default:
        currentTabIcon = Icons.badge_rounded;
        currentTabName = 'Yönetim Kadrosu';
        tabSubtitle = 'Yönetici, kurul üyeleri ve personel kayıtları.';
        break;
    }

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
          // Sağ Blok Başlığı
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  currentTabIcon,
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
                      currentTabName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.red.shade900,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      tabSubtitle,
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
              IconButton(
                onPressed: _reloadVisibleTab,
                icon: const Icon(Icons.refresh),
                tooltip: 'Sekmeyi Yenile',
              ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          const Divider(height: 1),
          const SizedBox(height: AppSpace.md),

          // Kurulu sekmeler durumunu korur; görünmeyenin animasyonları (iskelet) durur.
          for (var i = 0; i < _tabs.length; i++)
            if (_visited.contains(i))
              Offstage(
                offstage: _tab != i,
                child: ExcludeFocus(
                  excluding: _tab != i,
                  child: TickerMode(
                    enabled: _tab == i,
                    child: _buildTab(i, scope, site.code),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Future<void> _openSafetyRequests(PeopleSite site) async {
    await SafetyRequestsDialog.show(
      context,
      service: ApartmentManagementService(authService: widget.authService),
      siteCode: site.code,
      siteName: site.label,
    );
    if (!mounted || site.code != _siteCode) return;
    _reloadVisibleTab();
    _markOthersDirty(_tab);
    widget.onDataChanged?.call();
  }

  Widget _buildTab(int index, PeopleScope scope, int siteCode) {
    void changed() {
      _markOthersDirty(index);
      widget.onDataChanged?.call();
    }
    switch (index) {
      case 0:
        return PeoplePersonsTab(
          key: _personsKey,
          scope: scope,
          onDataChanged: changed,
          onImportRequested: scope.canWrite
              ? () => unawaited(_openBulkImport(scope, kind: ImportKind.allInOne))
              : null,
        );
      case 1:
        return PeopleApartmentsTab(
          key: _apartmentsKey,
          scope: scope,
          onDataChanged: changed,
          onImportRequested: scope.canWrite
              ? () => unawaited(_openBulkImport(scope, kind: ImportKind.allInOne))
              : null,
        );
      case 2:
        return PeopleVehiclesTab(
          key: _vehiclesKey,
          scope: scope,
          onDataChanged: changed,
          onImportRequested: scope.canWrite
              ? () => unawaited(_openBulkImport(scope, kind: ImportKind.vehicles))
              : null,
        );
      default:
        return PeopleTeamTab(
          key: _teamKey,
          scope: scope,
          onDataChanged: changed,
        );
    }
  }
}
