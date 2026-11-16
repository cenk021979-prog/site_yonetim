import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/device_page.dart';
import 'package:site_kapi_kontrol/models/device_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/status_chip.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/company_device_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

class CompanyDevicesView extends StatelessWidget {
  const CompanyDevicesView({
    super.key,
    required this.pageData,
    required this.devices,
    required this.isSuperUser,
    this.authService,
    required this.isLoading,
    required this.isBroadcastingOta,
    required this.onBroadcastOta,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onEditDevice,
    required this.onAssignDeviceToDoor,
    required this.onDeleteDevice,
    this.onDownloadFirmwareReportPdf,
    this.onRegisterNewDevice,
    this.onToggleDefect,
    this.onReleaseOwnership,
    this.onOpenQrRegistration,
    this.onOpenManualRegistration,
  });

  final DevicePage? pageData;
  final List<DeviceRecord> devices;
  final bool isSuperUser;
  final AuthService? authService;
  final bool isLoading;
  final bool isBroadcastingOta;
  final VoidCallback onBroadcastOta;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final ValueChanged<DeviceRecord> onEditDevice;
  final ValueChanged<DeviceRecord> onAssignDeviceToDoor;
  final ValueChanged<DeviceRecord> onDeleteDevice;
  final VoidCallback? onDownloadFirmwareReportPdf;
  final VoidCallback? onRegisterNewDevice;
  final ValueChanged<DeviceRecord>? onToggleDefect;
  final ValueChanged<DeviceRecord>? onReleaseOwnership;
  final VoidCallback? onOpenQrRegistration;
  final VoidCallback? onOpenManualRegistration;

  void _showDeviceAddChoiceSheet(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpace.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: AppSpace.md),
                  decoration: BoxDecoration(
                    color: p.textMuted.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                children: [
                  Icon(Icons.memory_rounded, color: AppTone.primary.ink(p), size: 24),
                  const SizedBox(width: AppSpace.sm),
                  Text(
                    'Şirket Cihazı Kaydet',
                    style: th.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                'Yeni kartı envantere eklemek için bir yöntem seçin:',
                style: th.bodySmall?.copyWith(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpace.md),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: p.border),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTone.primary.tint(p),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.qr_code_scanner_rounded, color: AppTone.primary.ink(p)),
                ),
                title: const Text('Karekod (QR) ile Kaydet', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Cihaz üzerindeki QR kodu kamerayla okutur ve Unique ID bilgisini otomatik doldurur.'),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenQrRegistration?.call();
                },
              ),
              const SizedBox(height: AppSpace.sm),
              ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(color: p.border),
                ),
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTone.info.tint(p),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Icon(Icons.edit_note_rounded, color: AppTone.info.ink(p)),
                ),
                title: const Text('Unique ID ile Elle Kaydet', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Cihazın 12 haneli Unique ID bilgisini klavyeden elle girerek doğrudan kayıt açar.'),
                onTap: () {
                  Navigator.pop(ctx);
                  onOpenManualRegistration?.call();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card(DeviceRecord device, int index) {
    return StaggeredEntry(
      index: index,
      child: CompanyDeviceCard(
        device: device,
        isSuperUser: isSuperUser,
        authService: authService,
        onEdit: () => onEditDevice(device),
        onAssignToDoor: () => onAssignDeviceToDoor(device),
        onDelete: () => onDeleteDevice(device),
        onToggleDefect: onToggleDefect != null
            ? () => onToggleDefect!(device)
            : null,
        onReleaseOwnership: onReleaseOwnership != null
            ? () => onReleaseOwnership!(device)
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unassignedDevices = devices
        .where((d) => d.assignedDoorId == null || d.assignedDoorId == 0)
        .toList();
    final assignedDevices = devices
        .where((d) => d.assignedDoorId != null && d.assignedDoorId != 0)
        .toList();
    // İlk yükleme (liste boş) iskelet gösterir; yenilemede mevcut liste kalır, üstte ince çubuk döner.
    final initialLoading = isLoading && devices.isEmpty;
    final refreshing = isLoading && devices.isNotEmpty;
    final page = pageData;
    final p = context.palette;
    final th = Theme.of(context).textTheme;
    var cardIndex = 0;

    return WorkspaceSplitShell(
      leftFlex: 4,
      rightFlex: 8,
      left: WorkspacePaneCard(
        icon: Icons.tune_rounded,
        title: 'Envanter Özeti & İşlemler',
        subtitle: 'Cihaz dağılımı ve toplu işlemler.',
        tone: AppTone.primary,
        onRefresh: isSuperUser ? null : (isLoading ? null : onRefresh),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              page == null
                  ? 'Kayıtlı cihazlar listeleniyor.'
                  : 'Toplam ${page.total} cihaz (${unassignedDevices.length} atama bekliyor, ${assignedDevices.length} kapıya atanmış).',
              style: th.bodyMedium?.copyWith(color: p.text, fontWeight: FontWeight.w600),
            ),
            if (isSuperUser) ...[
              const SizedBox(height: AppSpace.md),
              Wrap(
                spacing: AppSpace.sm,
                runSpacing: AppSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (onOpenQrRegistration != null || onOpenManualRegistration != null)
                    ElevatedButton.icon(
                      onPressed: () => _showDeviceAddChoiceSheet(context),
                      icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                      label: const Text('Yeni Cihaz Kaydet'),
                    ),
                  ElevatedButton.icon(
                    onPressed: isBroadcastingOta ||
                            isLoading ||
                            (pageData?.total ?? 0) == 0
                        ? null
                        : onBroadcastOta,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(
                      isBroadcastingOta
                          ? 'Gönderiliyor...'
                          : 'Tümüne OTA Kontrolü',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: (pageData?.total ?? 0) == 0
                        ? null
                        : onDownloadFirmwareReportPdf,
                    style: tonalActionStyle(context),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Sürüm Raporu (PDF)'),
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: isLoading ? null : onRefresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ],
            if (!isSuperUser && onRegisterNewDevice != null && devices.isNotEmpty) ...[
              const SizedBox(height: AppSpace.md),
              ElevatedButton.icon(
                onPressed: onRegisterNewDevice,
                icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
                label: const Text('Yeni Cihaz Kaydet (Kutu QR / Seri No)'),
              ),
            ],
          ],
        ),
      ),
      right: WorkspacePaneCard(
        icon: Icons.memory_rounded,
        title: 'Kayıtlı Cihazlar',
        subtitle: 'Atama bekleyen ve kapılara atanmış cihazlar.',
        tone: AppTone.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (refreshing)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpace.md),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: const LinearProgressIndicator(minHeight: 3),
                ),
              ),
            if (initialLoading)
              const ListSkeleton()
            else if (devices.isEmpty)
              EmptyCard(
                icon: Icons.devices_other_rounded,
                title: 'Şirket hesabına kayıtlı cihaz bulunamadı.',
                message: isSuperUser
                    ? ((onOpenQrRegistration != null || onOpenManualRegistration != null)
                        ? 'Yeni bir cihaz eklemek için aşağıdaki butonu kullanabilirsiniz.'
                        : 'Yeni cihaz eklemek için sol menüdeki "Şirket Cihazı Kaydet" bölümünü kullanabilirsiniz.')
                    : null,
                child: (isSuperUser && (onOpenQrRegistration != null || onOpenManualRegistration != null))
                    ? ElevatedButton.icon(
                        onPressed: () => _showDeviceAddChoiceSheet(context),
                        icon: const Icon(Icons.add_circle_outline_rounded),
                        label: const Text('Yeni Cihaz Kaydet'),
                      )
                    : (!isSuperUser && onRegisterNewDevice != null
                        ? ElevatedButton.icon(
                            onPressed: onRegisterNewDevice,
                            icon: const Icon(Icons.add_circle_outline_rounded),
                            label: const Text('Yeni Cihaz Kaydet'),
                          )
                        : null),
              )
            else ...[
              if (unassignedDevices.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: _GroupLabel(
                    label: 'Atama Bekleyen Cihazlar (${unassignedDevices.length})',
                    tone: AppTone.warning,
                    icon: Icons.link_off_rounded,
                  ),
                ),
                for (final device in unassignedDevices) _card(device, cardIndex++),
                if (assignedDevices.isNotEmpty) const SizedBox(height: AppSpace.sm),
              ],
              if (assignedDevices.isNotEmpty) ...[
                if (unassignedDevices.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpace.md),
                    child: _GroupLabel(
                      label: 'Kapıya Atanmış Cihazlar (${assignedDevices.length})',
                      tone: AppTone.neutral,
                      icon: Icons.meeting_room_outlined,
                    ),
                  ),
                for (final device in assignedDevices) _card(device, cardIndex++),
              ],
            ],
            if (page != null && page.totalPages > 1) ...[
              const SizedBox(height: AppSpace.md),
              PaginationBar(
                label: 'Sayfa ${page.page} / ${page.totalPages} | Toplam ${page.total}',
                onPrevious: page.page > 1 && !isLoading
                    ? () => onLoadPage(page.page - 1)
                    : null,
                onNext: page.page < page.totalPages && !isLoading
                    ? () => onLoadPage(page.page + 1)
                    : null,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Cihaz grubu başlığı: normalde hap (`StatusChip`, tek satır); büyük yazıda (>= 1,75x) etiketin
/// kırpılmaması için aynı tonda sarmalanan düz metin.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel({
    required this.label,
    required this.tone,
    required this.icon,
  });

  final String label;
  final AppTone tone;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    if (!isLargeText(context)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: StatusChip(label: label, tone: tone, icon: icon),
      );
    }
    final ink = tone.ink(context.palette);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpace.xs),
          child: Icon(icon, size: 16, color: ink),
        ),
        const SizedBox(width: AppSpace.sm),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: ink,
            ),
          ),
        ),
      ],
    );
  }
}
