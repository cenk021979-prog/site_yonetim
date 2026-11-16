import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/site_record.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/skeleton.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart' show filledToneStyle;

enum ClaimDeviceAssignOutcome {
  assigned,
  createDoor,
  dismissed,
}

class ClaimDeviceAssignResult {
  const ClaimDeviceAssignResult({
    required this.outcome,
    this.assignedDoor,
    this.site,
  });

  final ClaimDeviceAssignOutcome outcome;
  final DoorRecord? assignedDoor;
  final SiteRecord? site;
}

/// Cihaz sahiplenme / ekleme sonrası başarılı durum penceresi.
///
/// Kullanıcıya "Site Kur" dayatması YAPILMAZ. Cihazın hesaba başarıyla eklendiği
/// belirtilir; var olan kapılar listelenerek tek tıkla kapıya atanması sağlanır,
/// istenirse yeni kapı oluşturulabilir veya "Daha Sonra" ile sadece cihaz eklenmiş olarak bırakılabilir.
class ClaimDeviceAssignDialog extends StatefulWidget {
  const ClaimDeviceAssignDialog({
    super.key,
    required this.authService,
    required this.deviceUid,
    this.sites = const [],
    this.initialSite,
  });

  final AuthService authService;
  final String deviceUid;
  final List<SiteRecord> sites;
  final SiteRecord? initialSite;

  static Future<ClaimDeviceAssignResult?> show(
    BuildContext context, {
    required AuthService authService,
    required String deviceUid,
    List<SiteRecord> sites = const [],
    SiteRecord? initialSite,
  }) {
    return showDialog<ClaimDeviceAssignResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ClaimDeviceAssignDialog(
        authService: authService,
        deviceUid: deviceUid,
        sites: sites,
        initialSite: initialSite,
      ),
    );
  }

  @override
  State<ClaimDeviceAssignDialog> createState() =>
      _ClaimDeviceAssignDialogState();
}

class _ClaimDeviceAssignDialogState extends State<ClaimDeviceAssignDialog> {
  List<SiteRecord> _sites = [];
  SiteRecord? _selectedSite;
  bool _loadingSites = false;

  List<DoorRecord> _doors = [];
  DoorRecord? _selectedDoor;
  bool _loadingDoors = false;

  bool _isAssigning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _sites = List<SiteRecord>.from(widget.sites);
    if (_sites.isEmpty) {
      _loadSites();
    } else {
      _initSelectedSite();
    }
  }

  Future<void> _loadSites() async {
    setState(() {
      _loadingSites = true;
      _error = null;
    });
    try {
      final page = await widget.authService.listSites(page: 1, pageSize: 50);
      if (!mounted) return;
      setState(() {
        _loadingSites = false;
        _sites = page.sites;
      });
      _initSelectedSite();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSites = false;
        _error = 'Siteler yüklenemedi: $e';
      });
    }
  }

  void _initSelectedSite() {
    if (_sites.isEmpty) return;
    if (widget.initialSite != null &&
        _sites.any((s) => s.id == widget.initialSite!.id)) {
      _selectedSite =
          _sites.firstWhere((s) => s.id == widget.initialSite!.id);
    } else {
      _selectedSite = _sites.first;
    }
    if (_selectedSite != null) {
      _loadDoors(_selectedSite!.id);
    }
  }

  Future<void> _loadDoors(int siteCode) async {
    setState(() {
      _loadingDoors = true;
      _doors = const [];
      _selectedDoor = null;
      _error = null;
    });
    try {
      final (structure, err) =
          await widget.authService.getSiteStructure(siteCode: siteCode);
      if (!mounted) return;
      setState(() {
        _loadingDoors = false;
        if (err != null) {
          _error = err;
        } else if (structure != null) {
          _doors = structure.doors;
          if (_doors.isNotEmpty) {
            _selectedDoor =
                _doors.where((d) => !d.hasDevice).firstOrNull ?? _doors.first;
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDoors = false;
        _error = 'Kapılar yüklenemedi: $e';
      });
    }
  }

  Future<void> _assignToSelectedDoor() async {
    final door = _selectedDoor;
    if (door == null) return;

    setState(() {
      _isAssigning = true;
      _error = null;
    });

    try {
      final (updatedDoor, error) = await widget.authService.assignDoorDevice(
        doorId: door.id,
        deviceUid: widget.deviceUid,
      );

      if (!mounted) return;

      if (error != null) {
        setState(() {
          _isAssigning = false;
          _error = error;
        });
        return;
      }

      HapticFeedback.lightImpact();
      Navigator.of(context).pop(
        ClaimDeviceAssignResult(
          outcome: ClaimDeviceAssignOutcome.assigned,
          assignedDoor: updatedDoor ?? door,
          site: _selectedSite,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isAssigning = false;
        _error = 'Cihaz atanırken hata oluştu: $e';
      });
    }
  }

  void _createNewDoor() {
    HapticFeedback.lightImpact();
    Navigator.of(context).pop(
      ClaimDeviceAssignResult(
        outcome: ClaimDeviceAssignOutcome.createDoor,
        site: _selectedSite,
      ),
    );
  }

  void _dismiss() {
    Navigator.of(context).pop(
      ClaimDeviceAssignResult(
        outcome: ClaimDeviceAssignOutcome.dismissed,
        site: _selectedSite,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    final hasDoors = _doors.isNotEmpty;
    final isSelectedDoorOccupied = _selectedDoor?.hasDevice ?? false;

    return AppDialog(
      title: 'Cihaz Başarıyla Eklendi',
      subtitle: 'Cihaz (${widget.deviceUid}) hesabınıza bağlandı.',
      icon: Icons.check_circle_outline,
      tone: AppTone.success,
      actions: [
        TextButton(
          key: const ValueKey<String>('claim_device_later_btn'),
          onPressed: _isAssigning ? null : _dismiss,
          child: const Text('Daha Sonra'),
        ),
        OutlinedButton(
          key: const ValueKey<String>('claim_device_create_door_btn'),
          onPressed: _isAssigning ? null : _createNewDoor,
          child: const Text('Yeni Kapı Oluştur'),
        ),
        if (hasDoors)
          ElevatedButton(
            key: const ValueKey<String>('claim_device_assign_btn'),
            style: filledToneStyle(context, tone: AppTone.primary),
            onPressed: _isAssigning || _selectedDoor == null
                ? null
                : _assignToSelectedDoor,
            child: _isAssigning
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Kapıya Ata'),
          ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Site Seçimi
          if (_loadingSites)
            const ShimmerScope(
              child: SkeletonBox(height: 52, radius: AppRadius.md),
            )
          else if (_sites.length > 1) ...[
            DropdownButtonFormField<int>(
              initialValue: _selectedSite?.id,
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppRadius.md),
              dropdownColor: p.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              style: th.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'Site',
                prefixIcon: Icon(Icons.apartment_rounded),
              ),
              items: _sites.map((site) {
                return DropdownMenuItem<int>(
                  value: site.id,
                  child: Text(
                    site.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: _isAssigning
                  ? null
                  : (val) {
                      if (val == null) return;
                      final site = _sites.firstWhere((s) => s.id == val);
                      setState(() => _selectedSite = site);
                      _loadDoors(site.id);
                    },
            ),
            const SizedBox(height: AppSpace.md),
          ] else if (_sites.length == 1) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.md,
                vertical: AppSpace.sm,
              ),
              decoration: BoxDecoration(
                color: p.surfaceMuted,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: p.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.apartment_rounded, size: 20, color: p.action),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(
                    child: Text(
                      'Site: ${_sites.first.name}',
                      style: th.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpace.md),
          ],

          // Kapı Listesi & Atama Bölümü
          if (_loadingDoors)
            const ShimmerScope(
              child: SkeletonBox(height: 52, radius: AppRadius.md),
            )
          else if (_error != null)
            InlineNotice(
              tone: AppTone.danger,
              message: _error!,
            )
          else if (hasDoors) ...[
            Text(
              'Cihazı atamak istediğiniz kapıyı seçiniz:',
              style: th.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpace.sm),
            DropdownButtonFormField<int>(
              initialValue: _selectedDoor?.id,
              isExpanded: true,
              borderRadius: BorderRadius.circular(AppRadius.md),
              dropdownColor: p.surface,
              menuMaxHeight: 320,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              style: th.bodyLarge,
              decoration: const InputDecoration(
                labelText: 'Mevcut Kapı',
                prefixIcon: Icon(Icons.meeting_room_rounded),
              ),
              items: _doors.map((door) {
                final isFree = !door.hasDevice;
                final badge = isFree
                    ? 'Boş'
                    : '${door.hardwareBadgeText} (${door.assignedDeviceUid})';
                return DropdownMenuItem<int>(
                  value: door.id,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          door.doorName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AppSpace.xs),
                      Text(
                        '($badge)',
                        style: th.bodySmall?.copyWith(
                          color: isFree ? p.statusOk : p.textMuted,
                          fontWeight:
                              isFree ? FontWeight.w600 : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: _isAssigning
                  ? null
                  : (val) {
                      if (val == null) return;
                      final door = _doors.firstWhere((d) => d.id == val);
                      setState(() => _selectedDoor = door);
                    },
            ),
            if (isSelectedDoorOccupied) ...[
              const SizedBox(height: AppSpace.sm),
              InlineNotice(
                tone: AppTone.warning,
                message:
                    'Bu kapıya şu anda başka bir cihaz atanmış (${_selectedDoor!.assignedDeviceUid}). Yeni atama yapıldığında mevcut cihaz serbest kalacaktır.',
              ),
            ],
          ] else ...[
            const InlineNotice(
              tone: AppTone.info,
              message:
                  'Bu sitede henüz tanımlı bir kapı bulunmuyor. Yeni bir kapı oluşturarak cihazınızı hemen kapıya bağlayabilirsiniz.',
            ),
          ],
        ],
      ),
    );
  }
}
