import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/super_user_dashboard_data.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

/// Süper Kullanıcı Yönetim ve Saha Sağlık Paneli (Cockpit).
///
/// Modül listesinden bağımsız olarak, platform genelindeki mülk hacmini (siteler, daireler, kullanıcılar),
/// donanım/IoT saha durumunu (online/offline ESP32 cihazlar, kapılar, modeller, geçişler), onay bekleyen
/// kritik işleri ve sunucu teknik nabzını gerçek zamanlı tek bir ekranda sunar.
class SuperUserDashboardView extends StatefulWidget {
  const SuperUserDashboardView({
    super.key,
    required this.authService,
    this.onNavigate,
  });

  final AuthService authService;
  final void Function(SirketMenuItem item)? onNavigate;

  @override
  State<SuperUserDashboardView> createState() => SuperUserDashboardViewState();
}

class SuperUserDashboardViewState extends State<SuperUserDashboardView> {
  SuperUserDashboardData? _data;
  bool _loading = false;
  String? _error;
  DateTime? _lastRefreshedAt;

  @visibleForTesting
  void setDataForTesting(SuperUserDashboardData data) {
    setState(() {
      _data = data;
      _loading = false;
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(loadData());
  }

  Future<void> loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final res = await widget.authService.getSuperUserDashboardSummary();
      if (!mounted) return;
      setState(() {
        _data = SuperUserDashboardData.fromJson(res);
        _loading = false;
        _error = null;
        _lastRefreshedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Panel verileri alınamadı: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(p),
          const SizedBox(height: 18),
          if (_loading && _data == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null && _data == null)
            _buildErrorCard(p)
          else ...[
            _buildAttentionSection(p),
            const SizedBox(height: 22),
            _buildPlatformVolumeSection(p),
            const SizedBox(height: 22),
            _buildIotHealthSection(p),
            const SizedBox(height: 22),
            _buildSystemPulseSection(p),
            const SizedBox(height: 22),
            _buildQuickActionsSection(p),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(AppPalette p) {
    final primaryColor = AppTone.primary.ink(p);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primaryColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor.withValues(alpha: 0.25)),
          ),
          child: Icon(Icons.dashboard_rounded, color: primaryColor, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sistem ve Platform Genel Bakışı',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: p.text,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                _lastRefreshedAt == null
                  ? 'Canlı saha ve yönetim kokpiti'
                  : 'Son güncelleme: ${_formatTime(_lastRefreshedAt!)}',
                style: TextStyle(
                  fontSize: 12,
                  color: p.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Yenile',
          onPressed: _loading ? null : () => unawaited(loadData()),
          icon: _loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.refresh_rounded, color: p.textSecondary),
        ),
      ],
    );
  }

  Widget _buildErrorCard(AppPalette p) {
    return AppCard(
      tone: AppTone.danger,
      child: Column(
        children: [
          Icon(Icons.error_outline_rounded, color: p.statusCrit, size: 36),
          const SizedBox(height: 10),
          Text(
            _error ?? 'Hata oluştu.',
            style: TextStyle(color: p.text, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),
          ElevatedButton.icon(
            onPressed: () => unawaited(loadData()),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tekrar Dene'),
          ),
        ],
      ),
    );
  }

  // --- 1. En Üst Bant: Eylem Bekleyen İşler ---
  Widget _buildAttentionSection(AppPalette p) {
    final att = _data?.attention ?? const SuperUserAttentionData();

    if (!att.hasPendingActions) {
      return AppCard(
        tone: AppTone.success,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: p.statusOk, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Bekleyen onay veya kritik arıza bulunmuyor. Platform kararlı çalışıyor.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: p.text),
              ),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxChipWidth = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('DİKKAT VE EYLEM BEKLEYEN İŞLER', p),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (att.pendingSiteApplications > 0)
                  _buildAttentionChip(
                    p: p,
                    icon: Icons.domain_add_rounded,
                    title: '${att.pendingSiteApplications} Site Kurulum Başvurusu',
                    subtitle: 'Onay bekliyor',
                    tone: AppTone.warning,
                    maxWidth: maxChipWidth,
                    onTap: () => widget.onNavigate?.call(SirketMenuItem.siteBasvurulari),
                  ),
                if (att.pendingModuleRequests > 0)
                  _buildAttentionChip(
                    p: p,
                    icon: Icons.extension_rounded,
                    title: '${att.pendingModuleRequests} Ek Modül Talebi',
                    subtitle: 'Yönetici talebi var',
                    tone: AppTone.primary,
                    maxWidth: maxChipWidth,
                    onTap: () => widget.onNavigate?.call(SirketMenuItem.modulTalepleri),
                  ),
                if (att.unresolvedClientErrors > 0)
                  _buildAttentionChip(
                    p: p,
                    icon: Icons.bug_report_rounded,
                    title: '${att.unresolvedClientErrors} İstemci Hatası',
                    subtitle: 'Son 24 saatte kaydedildi',
                    tone: AppTone.danger,
                    maxWidth: maxChipWidth,
                    onTap: () => widget.onNavigate?.call(SirketMenuItem.istemciHatalari),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildAttentionChip({
    required AppPalette p,
    required IconData icon,
    required String title,
    required String subtitle,
    required AppTone tone,
    required double maxWidth,
    required VoidCallback onTap,
  }) {
    final color = tone.ink(p);
    final bg = tone.tint(p);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: p.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right_rounded, color: color, size: 18),
          ],
        ),
      ),
    );
  }

  // --- 2. Platform ve Mülk Büyüklüğü ---
  Widget _buildPlatformVolumeSection(AppPalette p) {
    final pl = _data?.platform ?? const SuperUserPlatformData();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('PLATFORM VE MÜLK BÜYÜKLÜĞÜ', p),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 650;
            return isNarrow
                ? Column(
                    children: [
                      _buildMetricCard(
                        p: p,
                        icon: Icons.apartment_rounded,
                        accentColor: const Color(0xFF2563EB),
                        title: 'Sitelerimiz',
                        mainNumber: '${pl.totalSites}',
                        mainUnit: 'Site',
                        badges: [
                          '${pl.activeSites} Aktif',
                          if (pl.passiveSites > 0) '${pl.passiveSites} Pasif',
                        ],
                        onTap: () => widget.onNavigate?.call(SirketMenuItem.siteler),
                      ),
                      const SizedBox(height: 10),
                      _buildMetricCard(
                        p: p,
                        icon: Icons.meeting_room_rounded,
                        accentColor: const Color(0xFF7C3AED),
                        title: 'Daireler',
                        mainNumber: '${pl.totalApartments}',
                        mainUnit: 'Daire',
                        badges: [
                          '${pl.occupiedApartments} Dolu',
                          '${pl.emptyApartments} Boş',
                          '%${pl.occupancyPercentage} Doluluk',
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildMetricCard(
                        p: p,
                        icon: Icons.people_alt_rounded,
                        accentColor: const Color(0xFF059669),
                        title: 'Kullanıcı Hesapları',
                        mainNumber: '${pl.totalUsers}',
                        mainUnit: 'Hesap',
                        badges: [
                          '${pl.apartmentUsers} Sakin',
                          '${pl.siteManagers} Yönetici',
                          '${pl.superUsers} Süper',
                        ],
                        onTap: () => widget.onNavigate?.call(SirketMenuItem.kullaniciYonetimi),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.apartment_rounded,
                          accentColor: const Color(0xFF2563EB),
                          title: 'Sitelerimiz',
                          mainNumber: '${pl.totalSites}',
                          mainUnit: 'Site',
                          badges: [
                            '${pl.activeSites} Aktif',
                            if (pl.passiveSites > 0) '${pl.passiveSites} Pasif',
                          ],
                          onTap: () => widget.onNavigate?.call(SirketMenuItem.siteler),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.meeting_room_rounded,
                          accentColor: const Color(0xFF7C3AED),
                          title: 'Daireler',
                          mainNumber: '${pl.totalApartments}',
                          mainUnit: 'Daire',
                          badges: [
                            '${pl.occupiedApartments} Dolu',
                            '${pl.emptyApartments} Boş',
                            '%${pl.occupancyPercentage} Doluluk',
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.people_alt_rounded,
                          accentColor: const Color(0xFF059669),
                          title: 'Kullanıcı Hesapları',
                          mainNumber: '${pl.totalUsers}',
                          mainUnit: 'Hesap',
                          badges: [
                            '${pl.apartmentUsers} Sakin',
                            '${pl.siteManagers} Yönetici',
                            '${pl.superUsers} Süper',
                          ],
                          onTap: () => widget.onNavigate?.call(SirketMenuItem.kullaniciYonetimi),
                        ),
                      ),
                    ],
                  );
          },
        ),
      ],
    );
  }

  // --- 3. Donanım & IoT Saha Sağlığı ---
  Widget _buildIotHealthSection(AppPalette p) {
    final iot = _data?.iot ?? const SuperUserIotData();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('DONANIM VE IOT SAHA SAĞLIĞI', p),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 650;
            return isNarrow
                ? Column(
                    children: [
                      _buildMetricCard(
                        p: p,
                        icon: Icons.sensors_rounded,
                        accentColor: const Color(0xFF10B981),
                        title: 'Canlı Cihaz Durumu',
                        mainNumber: '${iot.onlineDevices}',
                        mainUnit: '/ ${iot.totalDevices} Cihaz',
                        badges: [
                          '${iot.onlineDevices} Online',
                          if (iot.offlineDevices > 0) '${iot.offlineDevices} Offline',
                        ],
                        onTap: () => widget.onNavigate?.call(SirketMenuItem.kayitliCihazlar),
                      ),
                      const SizedBox(height: 10),
                      _buildMetricCard(
                        p: p,
                        icon: Icons.memory_rounded,
                        accentColor: const Color(0xFFD97706),
                        title: 'Donanım Mimarisi',
                        mainNumber: '${iot.totalDevices}',
                        mainUnit: 'Kart',
                        badges: [
                          '${iot.esp32C3Count} ESP32-C3',
                          '${iot.esp32WroomCount} ESP32-WROOM',
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildMetricCard(
                        p: p,
                        icon: Icons.door_sliding_rounded,
                        accentColor: const Color(0xFF0284C7),
                        title: 'Kapı ve Geçiş Trafiği',
                        mainNumber: '${iot.todayDoorPasses}',
                        mainUnit: 'Geçiş Bugün',
                        badges: [
                          '${iot.activeDoors} Aktif Kapı',
                          'Toplam ${iot.totalDoors} Kapı',
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.sensors_rounded,
                          accentColor: const Color(0xFF10B981),
                          title: 'Canlı Cihaz Durumu',
                          mainNumber: '${iot.onlineDevices}',
                          mainUnit: '/ ${iot.totalDevices} Cihaz',
                          badges: [
                            '${iot.onlineDevices} Online',
                            if (iot.offlineDevices > 0) '${iot.offlineDevices} Offline',
                          ],
                          onTap: () => widget.onNavigate?.call(SirketMenuItem.kayitliCihazlar),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.memory_rounded,
                          accentColor: const Color(0xFFD97706),
                          title: 'Donanım Mimarisi',
                          mainNumber: '${iot.totalDevices}',
                          mainUnit: 'Kart',
                          badges: [
                            '${iot.esp32C3Count} ESP32-C3',
                            '${iot.esp32WroomCount} ESP32-WROOM',
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildMetricCard(
                          p: p,
                          icon: Icons.door_sliding_rounded,
                          accentColor: const Color(0xFF0284C7),
                          title: 'Kapı ve Geçiş Trafiği',
                          mainNumber: '${iot.todayDoorPasses}',
                          mainUnit: 'Geçiş Bugün',
                          badges: [
                            '${iot.activeDoors} Aktif Kapı',
                            'Toplam ${iot.totalDoors} Kapı',
                          ],
                        ),
                      ),
                    ],
                  );
          },
        ),
      ],
    );
  }

  // --- 4. Altyapı ve Sunucu Canlılık Göstergesi ---
  Widget _buildSystemPulseSection(AppPalette p) {
    final sys = _data?.system ?? const SuperUserSystemData();
    final primaryColor = AppTone.primary.ink(p);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionTitle('ALTYAPI VE SUNUCU NABZI', p),
        const SizedBox(height: 10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final maxItemWidth = isNarrow ? constraints.maxWidth : (constraints.maxWidth - 20) / 2;
              return Wrap(
                spacing: 20,
                runSpacing: 12,
                alignment: isNarrow ? WrapAlignment.start : WrapAlignment.spaceBetween,
                children: [
                  _buildPulseIndicator(
                    p: p,
                    title: 'PostgreSQL Veritabanı',
                    statusText: 'Bağlı ve Canlı',
                    isOk: sys.database == 'connected',
                    maxWidth: maxItemWidth,
                  ),
                  _buildPulseIndicator(
                    p: p,
                    title: 'MQTT Broker Haberleşmesi',
                    statusText: sys.mqtt.connected ? 'Canlı ve Dinliyor' : 'Bağlantı Kesik',
                    isOk: sys.mqtt.connected,
                    maxWidth: maxItemWidth,
                  ),
                  _buildPulseItem(
                    p: p,
                    title: 'Sunucu Çalışma Süresi',
                    value: sys.uptimeFormatted,
                    icon: Icons.timer_outlined,
                    color: primaryColor,
                    maxWidth: maxItemWidth,
                  ),
                  _buildPulseItem(
                    p: p,
                    title: 'Platform Sürümü',
                    value: 'v${sys.version}',
                    icon: Icons.verified_outlined,
                    color: primaryColor,
                    maxWidth: maxItemWidth,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPulseIndicator({
    required AppPalette p,
    required String title,
    required String statusText,
    required bool isOk,
    required double maxWidth,
  }) {
    final dotColor = isOk ? p.statusOk : p.statusCrit;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: dotColor.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                Text(
                  statusText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPulseItem({
    required AppPalette p,
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required double maxWidth,
  }) {
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: p.textSecondary),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- 5. Hızlı Eylemler (Kısayollar) ---
  Widget _buildQuickActionsSection(AppPalette p) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionTitle('HIZLI İŞLEMLER VE KISAYOLLAR', p),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildActionPill(
                  p: p,
                  icon: Icons.qr_code_scanner_rounded,
                  label: 'Yeni Cihaz Kaydet',
                  maxWidth: maxWidth,
                  onTap: () => widget.onNavigate?.call(SirketMenuItem.kayitliCihazlar),
                ),
                _buildActionPill(
                  p: p,
                  icon: Icons.domain_verification_rounded,
                  label: 'Site Başvuruları',
                  maxWidth: maxWidth,
                  onTap: () => widget.onNavigate?.call(SirketMenuItem.siteBasvurulari),
                ),
                _buildActionPill(
                  p: p,
                  icon: Icons.extension_rounded,
                  label: 'Modül Geliştirme',
                  maxWidth: maxWidth,
                  onTap: () => widget.onNavigate?.call(SirketMenuItem.modulGelistirme),
                ),
                _buildActionPill(
                  p: p,
                  icon: Icons.bluetooth_searching_rounded,
                  label: 'Bluetooth ile Wi-Fi Kur',
                  maxWidth: maxWidth,
                  onTap: () => widget.onNavigate?.call(SirketMenuItem.bluetoothWifiKur),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildActionPill({
    required AppPalette p,
    required IconData icon,
    required String label,
    required double maxWidth,
    required VoidCallback onTap,
  }) {
    final primaryColor = AppTone.primary.ink(p);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: BoxConstraints(maxWidth: maxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: primaryColor, size: 18),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: p.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required AppPalette p,
    required IconData icon,
    required Color accentColor,
    required String title,
    required String mainNumber,
    required String mainUnit,
    required List<String> badges,
    VoidCallback? onTap,
  }) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: p.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onTap != null)
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: p.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  mainNumber,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: p.text,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  mainUnit,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: badges.map((badge) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: p.surfaceMuted,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: p.textSecondary,
                  ),
                ),
              );
            }).toList(growable: false),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, AppPalette p) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: p.textSecondary,
        letterSpacing: 0.6,
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
