import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/emergency_dialer.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_alarm_history_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

/// Sakinlerin site içi alarm başlatması. Telefon rehberi diğer destek ekranları
/// için korunur; burada alarm kaydı ve gerçek alıcı durumu gösterilir.
class EmergencyView extends StatefulWidget {
  const EmergencyView({
    super.key,
    required this.authService,
    this.service,
    this.channel,
    this.preferredSiteCode,
    this.allowEdit = false,
  });
  final AuthService authService;
  final EmergencyService? service;
  // Eski çağıranlar için korunur; yeni akış telefon araması başlatmaz.
  final EmergencyCallChannel? channel;
  final int? preferredSiteCode;
  final bool allowEdit;
  @override
  State<EmergencyView> createState() => EmergencyViewState();
}

typedef _PendingAlarm = ({
  int site,
  String kind,
  int? equipment,
  String? location,
  String key,
});

class EmergencyViewState extends State<EmergencyView> {
  late EmergencyService _service =
      widget.service ?? EmergencyService(authService: widget.authService);
  List<EmergencySite> _sites = [];
  List<EmergencyElevator> _elevators = [];
  List<EmergencyLocation> _locations = [];
  bool _showLocations = false, _locationLoading = false;
  String? _locationError;
  int _locationToken = 0;
  int? _siteCode;
  bool _loading = true,
      _elevatorLoading = false,
      _showElevators = false,
      _sending = false;
  bool _openingElevators = false;
  String? _error, _elevatorError, _sendError;
  int _siteToken = 0, _elevatorToken = 0;
  EmergencyAlarmReceipt? _receipt;
  _PendingAlarm? _pending;
  String? _lastAlarmKind;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void didUpdateWidget(EmergencyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService != widget.authService ||
        oldWidget.service != widget.service) {
      if (oldWidget.service == null) _service.close();
      _service =
          widget.service ?? EmergencyService(authService: widget.authService);
      _sites = [];
      _siteCode = null;
      ++_elevatorToken;
      ++_locationToken;
      _elevators = [];
      _locations = [];
      _elevatorLoading = false;
      _locationLoading = false;
      _openingElevators = false;
      _receipt = null;
      _pending = null;
      unawaited(reload());
    } else if (oldWidget.preferredSiteCode != widget.preferredSiteCode &&
        !_sending &&
        _pending == null) {
      final preferred = widget.preferredSiteCode;
      if (_sites.any((s) => s.siteCode == preferred)) _selectSite(preferred);
    }
  }

  @override
  void dispose() {
    ++_siteToken;
    ++_elevatorToken;
    ++_locationToken;
    if (widget.service == null) _service.close();
    super.dispose();
  }

  Future<void> reload() async {
    final token = ++_siteToken;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
        // Yenileme yeni bir kullanıcı niyetidir; eski otomatik gönderim sürmez.
        if (_locationLoading) {
          ++_locationToken;
          _locationLoading = false;
          _locationError = null;
        }
      });
    }
    try {
      final sites = (await _service.listAlarmSites())
          .where((s) => s.canCreate)
          .toList();
      if (!mounted || token != _siteToken) return;
      final preferred = widget.preferredSiteCode;
      final code = sites.any((s) => s.siteCode == _siteCode)
          ? _siteCode
          : sites.any((s) => s.siteCode == preferred)
          ? preferred
          : sites.firstOrNull?.siteCode;
      setState(() {
        if (code != _siteCode) {
          ++_elevatorToken;
          ++_locationToken;
          _elevators = [];
          _locations = [];
          _elevatorError = null;
          _locationError = null;
          _elevatorLoading = false;
          _locationLoading = false;
        }
        _sites = sites;
        _loading = false;
        _siteCode = code;
      });
      if (code != null) await _loadElevators(reveal: _showElevators);
      if (_showLocations) await _loadLocations();
    } catch (e) {
      if (!mounted || token != _siteToken) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Site bilgileri alınamadı.');
      });
    }
  }

  void _selectSite(int? code) {
    ++_elevatorToken;
    ++_locationToken;
    setState(() {
      _siteCode = code;
      _elevators = [];
      _locations = [];
      _elevatorError = null;
      _locationError = null;
      _elevatorLoading = false;
      _locationLoading = false;
      _openingElevators = false;
      _receipt = null;
      _sendError = null;
      _lastAlarmKind = null;
    });
    if (code != null) unawaited(_loadElevators(reveal: _showElevators));
    if (_showLocations) unawaited(_loadLocations());
  }

  Future<void> _loadElevators({bool reveal = true}) async {
    final code = _siteCode;
    if (code == null) return;
    final token = ++_elevatorToken;
    setState(() {
      if (reveal) {
        // Yangın listesi beklerken asansöre geçildiyse geç gelen konum alarm başlatamaz.
        ++_locationToken;
        _locationLoading = false;
        _locationError = null;
        _showElevators = true;
        _showLocations = false;
      }
      _openingElevators = reveal;
      _elevatorLoading = true;
      _elevators = [];
      _elevatorError = null;
      _sendError = null;
    });
    try {
      final items = await _service.listElevators(code);
      if (!mounted || token != _elevatorToken || code != _siteCode) return;
      setState(() {
        _elevators = items;
        _elevatorLoading = false;
        _openingElevators = false;
        if (items.isEmpty) _showElevators = false;
      });
    } catch (e) {
      if (!mounted || token != _elevatorToken || code != _siteCode) return;
      setState(() {
        _elevatorLoading = false;
        _openingElevators = false;
        _elevatorError = crmMessageOf(e, 'Asansörler alınamadı.');
      });
    }
  }

  Future<void> _loadLocations({bool sendWhenSingle = false}) async {
    final code = _siteCode;
    if (code == null || _sending || _locationLoading) return;
    final token = ++_locationToken;
    setState(() {
      if (_openingElevators) {
        ++_elevatorToken;
        _elevatorLoading = false;
        _openingElevators = false;
      }
      _showLocations = false;
      _showElevators = false;
      _locationLoading = true;
      _locations = [];
      _locationError = null;
      _sendError = null;
    });
    try {
      final items = await _service.listLocations(code);
      if (!mounted || token != _locationToken || code != _siteCode) return;
      final blocks = items.where((item) => item.blockId != null).toList();
      final direct = blocks.length == 1
          ? blocks.single.id
          : blocks.isEmpty && items.any((item) => item.id == 'site')
          ? 'site'
          : null;
      setState(() {
        _locations = items;
        _locationLoading = false;
        _showLocations = blocks.length > 1;
        if (items.isEmpty || (blocks.isEmpty && direct == null)) {
          _locationError = 'Yangın konumu doğrulanamadı. Konumları yenileyin.';
        }
      });
      if (sendWhenSingle && direct != null) {
        await _send('fire', locationId: direct);
      }
    } catch (e) {
      if (!mounted || token != _locationToken || code != _siteCode) return;
      setState(() {
        _locationLoading = false;
        _locationError = crmMessageOf(e, 'Konumlar alınamadı.');
      });
    }
  }

  Future<void> _send(
    String kind, {
    int? equipmentId,
    String? locationId,
  }) async {
    final code = _pending?.site ?? _siteCode;
    if (_sending || code == null) return;
    // Belirsiz ağ sonucunda aynı anahtar korunur; tekrar ikinci alarm üretmez.
    _pending ??= (
      site: code,
      kind: kind,
      equipment: equipmentId,
      location: locationId,
      key:
          '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 30)}',
    );
    final pending = _pending!;
    setState(() {
      _lastAlarmKind = pending.kind;
      _sending = true;
      _sendError = null;
      _receipt = null;
    });
    try {
      final receipt = await _service.createAlarm(
        siteCode: pending.site,
        kind: pending.kind,
        equipmentId: pending.equipment,
        locationId: pending.location,
        idempotencyKey: pending.key,
      );
      if (!mounted) return;
      setState(() {
        _receipt = receipt;
        _pending = null;
      });
      await reload();
    } catch (e) {
      if (!mounted) return;
      final rejected =
          e is ApiException &&
          e.statusCode != null &&
          e.statusCode! >= 400 &&
          e.statusCode! < 500 &&
          e.statusCode != 408;
      setState(() {
        if (rejected) _pending = null;
        _sendError =
            '${crmMessageOf(e, 'Alarm kaydı doğrulanamadı.')} ${rejected ? 'Seçiminizi yenileyebilirsiniz.' : 'Aynı bildirimi tekrar deneyebilirsiniz.'}';
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled =
        _siteCode == null || _loading || _sending || _pending != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Site içi acil bildirim',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpace.sm),
        Text(
          _elevators.isEmpty
              ? 'Yangın ekibe ve ilgili dairelere bildirilir.'
              : 'Asansör ekibe; yangın ekibe ve ilgili dairelere bildirilir.',
        ),
        const SizedBox(height: AppSpace.md),
        if (_sites.length > 1) ...[
          DropdownButtonFormField<int>(
            key: ValueKey('emergency_site_$_siteCode'),
            initialValue: _siteCode,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Site'),
            items: [
              for (final site in _sites)
                DropdownMenuItem(
                  value: site.siteCode,
                  child: Text(
                    site.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _sending || _pending != null ? null : _selectSite,
          ),
          const SizedBox(height: AppSpace.md),
        ] else if (_sites.isNotEmpty) ...[
          Text(_sites.first.label),
          const SizedBox(height: AppSpace.md),
        ],
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) _notice(_error!, reload),
        if (!_loading && _sites.isEmpty && _error == null)
          const AppCard(
            child: Text(
              'Alarm başlatmak için bu sitede aktif daire/sakin kaydınız bulunmalı.',
            ),
          ),
        if (_elevatorLoading || _locationLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: AppSpace.sm),
            child: LinearProgressIndicator(
              semanticsLabel: 'Acil seçenekleri güncelleniyor',
            ),
          ),
        if (_elevatorError != null)
          _notice(_elevatorError!, () => _loadElevators(reveal: false)),
        if (_locationError != null)
          _notice(_locationError!, () => _loadLocations(sendWhenSingle: true)),
        LayoutBuilder(
          builder: (context, constraints) {
            // Henüz gelmemiş veriyi "asansör yok" diye göstermeyin.
            if (_elevatorLoading && _elevators.isEmpty) {
              return const SizedBox.shrink();
            }
            final buttons = [
              if (_elevators.isNotEmpty)
                _button(
                  'Asansör',
                  Icons.elevator_rounded,
                  'emergency_quick_elevator',
                  disabled || _elevatorLoading
                      ? null
                      : () => unawaited(_loadElevators()),
                ),
              _button(
                'Yangın',
                Icons.local_fire_department_rounded,
                'emergency_quick_fire',
                disabled || _locationLoading
                    ? null
                    : () => unawaited(_loadLocations(sendWhenSingle: true)),
              ),
            ];
            if (constraints.maxWidth < 380 ||
                MediaQuery.textScalerOf(context).scale(16) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (index, button) in buttons.indexed) ...[
                    if (index > 0) const SizedBox(height: AppSpace.sm),
                    button,
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (final (index, button) in buttons.indexed) ...[
                  if (index > 0) const SizedBox(width: AppSpace.sm),
                  Expanded(child: button),
                ],
              ],
            );
          },
        ),
        if (_showElevators) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            'Hangi asansör?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('Adına dokunduğunuzda alarm oluşturulur.'),
          if (!_elevatorLoading && _elevatorError == null && _elevators.isEmpty)
            const AppCard(
              child: Text(
                'Bu sitede kayıtlı aktif asansör yok. Yönetim Ekipman ve Bakım bölümünden ekleyebilir.',
              ),
            ),
          for (final elevator in _elevators)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: OutlinedButton(
                key: ValueKey('emergency_elevator_${elevator.id}'),
                onPressed: disabled
                    ? null
                    : () => unawaited(
                        _send('elevator', equipmentId: elevator.id),
                      ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(elevator.name),
                      if (elevator.blockName != null) Text(elevator.blockName!),
                      if (elevator.location != null) Text(elevator.location!),
                    ],
                  ),
                ),
              ),
            ),
        ],
        if (_showLocations) ...[
          const SizedBox(height: AppSpace.md),
          Text(
            'Yangın nerede?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Text('Bloğu seçin veya tüm siteyi bilgilendirin.'),
          if (!_locationLoading && _locationError == null && _locations.isEmpty)
            const Text('Konum listesi alınamadı; yenileyin.'),
          for (final location in _locations)
            Padding(
              padding: const EdgeInsets.only(top: AppSpace.sm),
              child: OutlinedButton(
                key: ValueKey('emergency_location_${location.id}'),
                onPressed: disabled
                    ? null
                    : () => unawaited(_send('fire', locationId: location.id)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  child: Text(location.name),
                ),
              ),
            ),
        ],
        if (_sending)
          const Padding(
            padding: EdgeInsets.all(AppSpace.sm),
            child: Text('Alarm kaydediliyor…'),
          ),
        if (_sendError != null)
          _notice(
            _sendError!,
            () => _pending != null
                ? _send(
                    _pending!.kind,
                    equipmentId: _pending!.equipment,
                    locationId: _pending!.location,
                  )
                : _lastAlarmKind == 'fire'
                ? _loadLocations(sendWhenSingle: true)
                : _loadElevators(),
          ),
        if (_receipt case final receipt?) ...[
          const SizedBox(height: AppSpace.md),
          AppCard(
            key: const ValueKey('emergency_receipt'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Alarm #${receipt.alarm.id} kaydedildi.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Atanan güvenlik: ${receipt.securityAssigned} • Asansör servisi: ${receipt.serviceAssigned}',
                ),
                Text('Yönetici bildirimi: ${receipt.managerNotified}'),
                if (receipt.alarm.kind == 'fire')
                  Text('Daire hesabı alarmı: ${receipt.residentAssigned}'),
                if (receipt.alarm.createdByName != null)
                  Text('Alarmı veren: ${receipt.alarm.createdByName}'),
                const Text(
                  'Kayıt oluşması, alıcının alarmı gördüğü veya sesi duyduğu anlamına gelmez.',
                ),
                if (receipt.securityAssigned == 0 &&
                    receipt.serviceAssigned == 0 &&
                    receipt.residentAssigned == 0)
                  const Text(
                    'Sesli alarm alıcısı atanmamış. Yönetim Alarm alıcıları ayarını tamamlamalı.',
                  ),
                for (final warning in receipt.warningMessages) Text(warning),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const ValueKey('emergency_history'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EmergencyAlarmHistoryDialog(service: _service),
            ),
            icon: const Icon(Icons.history),
            label: const Text('Alarm kayıtları'),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: _sending ? null : () => unawaited(reload()),
            icon: const Icon(Icons.refresh),
            label: const Text('Yenile'),
          ),
        ),
      ],
    );
  }

  Widget _button(
    String text,
    IconData icon,
    String key,
    VoidCallback? onPressed,
  ) => FilledButton.icon(
    key: ValueKey(key),
    onPressed: onPressed,
    icon: Icon(icon),
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpace.lg,
        horizontal: AppSpace.md,
      ),
    ),
    label: Text(text),
  );
  Widget _notice(String message, Future<void> Function() retry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(message),
          TextButton(
            onPressed: _sending ? null : () => unawaited(retry()),
            child: const Text('Tekrar dene'),
          ),
        ],
      ),
    ),
  );
}
