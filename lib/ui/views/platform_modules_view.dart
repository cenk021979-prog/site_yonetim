import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/styles/app_colors.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';

/// Platform geneli modül yönetimi (Katman 1 Master Anahtarı).
/// Yalnızca Süper Kullanıcı tarafından görülebilir ve yönetilebilir.
/// [showOnlyActive] true ise yalnız Devreye Alınan (Aktif) modülleri gösterir,
/// false ise Pasif Modülleri gösterir, null ise tümünü gösterir.
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
            ? '${module.name} platform genelinde AKTİF edildi.'
            : '${module.name} platform genelinde PASİFE alındı.',
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

  String get _pageTitle {
    if (widget.showOnlyActive == true) {
      return 'Devreye Alınmış Modüller';
    } else if (widget.showOnlyActive == false) {
      return 'Devreye Alınmamış Modüller';
    }
    return 'Platform Modül Havuzu (Global)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : loadData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadData,
        child: ListView(
          padding: const EdgeInsets.all(AppSpace.md),
          children: [
            _buildInfoCard(),
            const SizedBox(height: AppSpace.md),
            if (_loading && _modules == null)
              const ListSkeleton(rows: 5)
            else if (_error != null && _modules == null)
              InlineNotice(
                message: _error!,
                onRetry: loadData,
              )
            else if (_modules != null)
              ..._buildModuleCards(),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final title = widget.showOnlyActive == true
        ? 'Devreye Alınmış Modüller'
        : widget.showOnlyActive == false
            ? 'Devreye Alınmamış Modüller'
            : 'Katman 1: Platform Master Anahtarları';

    final desc = widget.showOnlyActive == true
        ? 'Tasarımı devam etse de kullanıcıların hizmetine sunulmuş modüllerdir.\n\n'
            '• Temel Modüller: Site oluşturan herkese tanımlanan modüllerdir (her sitede otomatik aktif olur).\n'
            '• Ek Modüller: Kullanıcının sitesine ihtiyaç duyması halinde Süper User\'dan talep ederek açabileceği modüllerdir.\n\n'
            'Bir modülü kapatmak için anahtarı kapatabilirsiniz; anında Devreye Alınmamış Modüller altına taşınır.'
        : widget.showOnlyActive == false
            ? 'Tasarımına başlanmış veya devam eden, henüz kullanıcıların hizmetine sunulmamış modüllerdir.\n\n'
                '• Yalnızca Süper Kullanıcı görebilir; diğer hiçbir kullanıcı, yönetici veya rolde kesinlikle görünmez.\n'
                '• Menülerde, vitrinde ve modül talep listesinde yer almaz.\n\n'
                'Geliştirmesi biten modülü aktif ettiğinizde: Temel modülse herkesin sitesinde otomatik aktif olur; Ek modülse site yöneticileri talep edebilir.'
            : 'Burada pasife alınan modüller, Süper Kullanıcı dışındaki hiçbir kullanıcı ve rolde görünmez; menülerde ve talep listesinde yer almaz.\n\n'
                '• Aktif Temel Modül: Tüm sitelerde otomatik tanımlanır.\n'
                '• Aktif Ek Modül: Site yöneticileri tarafından talep edilebilir.';

    return AppCard(
      padding: const EdgeInsets.all(AppSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                widget.showOnlyActive == true
                    ? Icons.check_circle_outline
                    : widget.showOnlyActive == false
                        ? Icons.pause_circle_outline
                        : Icons.shield_outlined,
                color: widget.showOnlyActive == false ? AppColors.warning : AppColors.primary,
                size: 22,
              ),
              const SizedBox(width: AppSpace.sm),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            desc,
            style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildModuleCards() {
    var list = _modules ?? <PlatformModule>[];
    if (widget.showOnlyActive == true) {
      list = list.where((m) => m.isPlatformActive).toList();
    } else if (widget.showOnlyActive == false) {
      list = list.where((m) => !m.isPlatformActive).toList();
    }

    if (list.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.xl),
            child: Text(
              widget.showOnlyActive == true
                  ? 'Devreye alınmış aktif modül bulunmuyor.'
                  : widget.showOnlyActive == false
                      ? 'Pasife alınmış modül bulunmuyor.'
                      : 'Katalogda modül bulunamadı.',
            ),
          ),
        ),
      ];
    }

    return list.map((m) {
      final isBusy = _busyCodes.contains(m.code);
      final isActive = m.isPlatformActive;

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpace.sm),
        child: AppCard(
          padding: const EdgeInsets.all(AppSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          m.code,
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Switch(
                    value: isActive,
                    onChanged: isBusy ? null : (val) => _toggleModule(m, val),
                  ),
                ],
              ),
              if (m.description.trim().isNotEmpty) ...[
                const SizedBox(height: AppSpace.xs),
                Text(
                  m.description,
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ],
              const SizedBox(height: AppSpace.sm),
              Wrap(
                spacing: AppSpace.xs,
                runSpacing: AppSpace.xs,
                children: [
                  StatusChip(
                    label: isActive ? 'Devreye Alınmış' : 'Devreye Alınmamış',
                    tone: isActive ? AppTone.success : AppTone.neutral,
                    icon: isActive ? Icons.check_circle_outline : Icons.block,
                  ),
                  if (m.core)
                    const StatusChip(
                      label: 'Temel Modül (Herkese)',
                      tone: AppTone.info,
                      icon: Icons.star_border,
                    )
                  else
                    const StatusChip(
                      label: 'Ek Modül (Talep Edilebilir)',
                      tone: AppTone.neutral,
                      icon: Icons.tune,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList(growable: false);
  }
}
