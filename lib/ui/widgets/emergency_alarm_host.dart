import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_audio.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_alarm_history_dialog.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';

/// HomePage'in tüm menülerinde yaşar. Servis hesabının normal site üyeliği gerekmez;
/// alıcı kapsamı sunucunun kimliğe göre döndürdüğü feed'den gelir.
class EmergencyAlarmHost extends StatefulWidget {
  const EmergencyAlarmHost({
    super.key,
    required this.authService,
    this.controller,
    this.builder,
  });
  final AuthService authService;
  final EmergencyAlarmController? controller;

  /// Tek alıcı yaşam döngüsü; eylem başlığa, gerçek alarm uyarısı gövdeye yerleşir.
  final Widget Function(BuildContext context, Widget action, Widget banner)?
  builder;
  @override
  State<EmergencyAlarmHost> createState() => _EmergencyAlarmHostState();
}

class _EmergencyAlarmHostState extends State<EmergencyAlarmHost>
    with WidgetsBindingObserver {
  final PushService _push = PushService.instance;
  final _uiChanges = ValueNotifier<int>(0);
  final _panelChanges = ValueNotifier<int>(0);
  Route<dynamic>? _alarmPanelRoute;
  String? _phonePushMessage;
  String? _phonePushScope;
  bool _phonePushNeedsSettings = false;
  StreamSubscription<EmergencyPushReference>? _pushForeground;
  bool _showingAlarms = false;
  bool _enablingPush = false;
  String? _receiverScope;
  bool _receiverEligible = false;
  String? get _scope {
    final session = widget.authService.session;
    return session == null
        ? null
        : '${session.id}:${session.role.name}:${session.token}';
  }

  late final EmergencyService? _service = widget.controller == null
      ? EmergencyService(authService: widget.authService)
      : null;
  late final EmergencyAlarmController _controller =
      widget.controller ??
      EmergencyAlarmController(
        authService: widget.authService,
        service: _service!,
        audio: BundledEmergencyAlarmAudio(),
      );
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _receiverScope = _scope;
    _receiverEligible = _controller.canReceive;
    _controller.addListener(_receiverChanged);
    _controller.start();
    _pushForeground = _push.foregroundEmergencies.listen((_) {
      if (mounted && _scope != null) unawaited(_controller.refreshFromPush());
    });
    _push.changes.addListener(_changed);
    _push.bindEmergencyOpener(_openPushAlarm);
  }

  void _changed() {
    if (mounted) _uiChanges.value++;
  }

  void _receiverChanged() {
    final scope = _scope;
    final eligible = _controller.canReceive;
    if (scope != _receiverScope) {
      // Authentication changes have their own push sync; never carry old feed
      // eligibility into the new account or token.
      _receiverScope = scope;
      _receiverEligible = eligible;
    } else if (eligible != _receiverEligible) {
      _receiverEligible = eligible;
      if (mounted && scope != null) {
        unawaited(_push.syncNow(widget.authService));
      }
    }
    _changed();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    unawaited(_pushForeground?.cancel());
    _push.changes.removeListener(_changed);
    _push.unbindEmergencyOpener(_openPushAlarm);
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_receiverChanged);
    if (widget.controller == null) {
      _controller.dispose();
      _service?.close();
    }
    _uiChanges.dispose();
    _panelChanges.dispose();
    super.dispose();
  }

  void _openPushAlarm(EmergencyPushReference reference) {
    final scope = _scope;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scope == null || scope != _scope) return;
      unawaited(_openVerifiedAlarm(reference, scope));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Future<void> _openVerifiedAlarm(
    EmergencyPushReference reference,
    String scope,
  ) async {
    await _controller.refreshFromPush();
    if (!mounted || scope != _scope) return;
    if (!_controller.alarms.any(
      (alarm) =>
          alarm.id == reference.alarmId && alarm.siteCode == reference.siteCode,
    )) {
      AppSnack.show(
        context,
        'Bu alarm artık etkin değil veya bu hesaba açık değil.',
        kind: AppSnackKind.info,
      );
      return;
    }
    await _showAlarms(target: reference);
  }

  Future<void> _enablePhonePush() async {
    if (_enablingPush) return;
    final scope = _scope;
    final panel = _alarmPanelRoute;
    setState(() => _enablingPush = true);
    try {
      final result = await _push.enableOnThisDevice(widget.authService);
      if (!mounted || scope != _scope) return;
      final message = switch (result) {
        PushEnableOutcome.registered =>
          'Bu cihaz telefon bildirimi için kaydedildi.',
        PushEnableOutcome.pushUnavailable =>
          'Sunucunun telefon bildirimi bağlantısı henüz hazır değil.',
        PushEnableOutcome.unsupported =>
          'Bu hesabın veya cihazın telefon bildirimi uygunluğu doğrulanamadı.',
        PushEnableOutcome.permissionDenied ||
        PushEnableOutcome.permissionPermanentlyDenied =>
          'Telefon ayarlarından bildirim iznini açın.',
        _ =>
          'Bildirim kaydı tamamlanamadı; bağlantınızı kontrol edip yeniden deneyin.',
      };
      _presentPhonePushResult(
        panel,
        scope,
        message,
        kind: result == PushEnableOutcome.registered
            ? AppSnackKind.success
            : AppSnackKind.info,
        needsSettings: result == PushEnableOutcome.permissionPermanentlyDenied,
      );
    } catch (_) {
      if (mounted && scope == _scope) {
        _presentPhonePushResult(
          panel,
          scope,
          'Telefon bildirimi kaydedilemedi. Yeniden deneyin.',
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted) setState(() => _enablingPush = false);
    }
  }

  void _presentPhonePushResult(
    Route<dynamic>? panel,
    String? scope,
    String message, {
    required AppSnackKind kind,
    bool needsSettings = false,
  }) {
    if (!mounted || scope != _scope) return;
    if (panel != null && identical(panel, _alarmPanelRoute) && panel.isActive) {
      _phonePushMessage = message;
      _phonePushScope = scope;
      _phonePushNeedsSettings = needsSettings;
      _panelChanges.value++;
      // Üstteki Geçmiş/başka rota veya kapanmakta olan panel etkilenmez.
      if (panel.isCurrent) panel.navigator?.pop();
    }
    AppSnack.show(
      context,
      message,
      kind: kind,
      action: needsSettings ? SnackBarAction(
        label: 'Telefon ayarlarını aç',
        onPressed: () {
          if (!mounted || scope == null || scope != _scope) return;
          unawaited(_push.openSettingsToEnable(widget.authService));
        },
      ) : null,
    );
  }

  Future<void> _showAlarms({EmergencyPushReference? target}) async {
    if (_showingAlarms) return;
    _showingAlarms = true;
    _phonePushMessage = null;
    _phonePushNeedsSettings = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (context) {
          _alarmPanelRoute = ModalRoute.of(context);
          return AnimatedBuilder(
            animation: Listenable.merge([_controller, _panelChanges]),
            builder: (context, _) => AlertDialog(
              title: const Text('Alarm kayıtları'),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_controller.canSound)
                        Text(
                          _controller.playing
                              ? 'Oynatıcı alarm sesini başlattı.'
                              : 'Alarm sesi için cihaz sesi ve tarayıcı izinleri açık olmalı. Uygulama açıkken alarmlar izlenir.',
                        ),
                      if (!_controller.alarms.any(
                        (alarm) =>
                            target == null ||
                            (alarm.id == target.alarmId &&
                                alarm.siteCode == target.siteCode),
                      ))
                        const Text('Bekleyen acil bildirim yok.'),
                      for (final alarm in _controller.alarms.where(
                        (alarm) =>
                            target == null ||
                            (alarm.id == target.alarmId &&
                                alarm.siteCode == target.siteCode),
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                alarm.title,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                [
                                  alarm.siteName,
                                  if (alarm.location != null) alarm.location!,
                                ].where((s) => s.isNotEmpty).join(' • '),
                              ),
                              if (alarm.createdAt != null)
                                Text('${alarm.createdAt!.toLocal()}'),
                              Text(
                                'Alarmı veren: ${alarm.createdByName ?? 'Eski kayıtta isim bulunmuyor'}',
                              ),
                              if (alarm.kind == 'fire')
                                Text(
                                  alarm.scope == 'site'
                                      ? 'Kapsam: Tüm site'
                                      : 'Kapsam: Seçili blok',
                                ),
                              if (alarm.soundEnabled)
                                const Text(
                                  'Bu cihazdaki onayınız diğer alıcıların alarmını susturmaz.',
                                ),
                              TextButton.icon(
                                key: ValueKey('emergency_ack_${alarm.id}'),
                                icon: const Icon(Icons.done),
                                label: Text(
                                  alarm.soundEnabled
                                      ? 'Gördüm, alarmı sustur'
                                      : 'Bildirimi gördüm',
                                ),
                                onPressed: () async {
                                  try {
                                    await _controller.acknowledge(alarm.id);
                                  } catch (_) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Onay kaydedilemedi; tekrar deneyin.',
                                          ),
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      if (_controller.error != null) Text(_controller.error!),
                      if (_controller.soundError != null)
                        Text(_controller.soundError!),
                      if (_phonePushMessage != null &&
                          _phonePushScope == _scope)
                        Text(
                          _phonePushMessage!,
                          key: const ValueKey('emergency_phone_push_result'),
                        ),
                      if (_phonePushNeedsSettings && _phonePushScope == _scope)
                        TextButton(
                          key: const ValueKey('emergency_phone_push_settings'),
                          onPressed: () {
                            if (_scope == null || _phonePushScope != _scope) {
                              return;
                            }
                            unawaited(
                              _push.openSettingsToEnable(widget.authService),
                            );
                          },
                          child: const Text('Telefon ayarlarını aç'),
                        ),
                      if (_controller.canReceive &&
                          _push.isSupported &&
                          !_push.activeHere.value)
                        TextButton.icon(
                          key: const ValueKey('emergency_enable_phone_push'),
                          onPressed: _enablingPush
                              ? null
                              : () => unawaited(_enablePhonePush()),
                          icon: const Icon(Icons.phone_android),
                          label: const Text('Telefon bildirimlerini aç'),
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Alarmları yenile',
                  onPressed: () => unawaited(_controller.refresh()),
                  icon: const Icon(Icons.refresh),
                ),
                TextButton.icon(
                  key: const ValueKey('emergency_history'),
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => EmergencyAlarmHistoryDialog(
                      service: _controller.service,
                    ),
                  ),
                  icon: const Icon(Icons.history),
                  label: const Text('Geçmiş'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          );
        },
      );
    } finally {
      _alarmPanelRoute = null;
      _showingAlarms = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Feed poll'ları yalnız iki küçük slotu yeniler; Scaffold ve sayfa içeriği
    // aynı ağaçta kalır, kapı yoklaması/scroll/giriş animasyonu etkilenmez.
    final action = AnimatedBuilder(
      animation: _uiChanges,
      builder: (context, _) => _alarmWidgets(context).$1,
    );
    final banner = AnimatedBuilder(
      animation: _uiChanges,
      builder: (context, _) => _alarmWidgets(context).$2,
    );
    return widget.builder?.call(context, action, banner) ??
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(alignment: Alignment.centerRight, child: action),
            banner,
          ],
        );
  }

  (Widget, Widget) _alarmWidgets(BuildContext context) {
    final controller = _controller;
    final hasError = controller.error != null || controller.soundError != null;
    final action = !controller.canReceive && !hasError
        ? const SizedBox.shrink()
        : IconButton(
            key: ValueKey(
              hasError ? 'emergency_connection_error' : 'emergency_alarm_inbox',
            ),
            tooltip: hasError
                ? 'Alarm kayıtları: bağlantıyı veya sesi kontrol edin'
                : controller.canSound && !controller.soundEnabled
                ? 'Alarm kayıtları • Sesli alarmı açmak için dokunun'
                : 'Alarm kayıtları',
            visualDensity: VisualDensity.standard,
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            onPressed: _openAlarmPanel,
            icon: Badge(
              isLabelVisible: controller.alarms.isNotEmpty || hasError,
              label: Text(
                hasError && controller.alarms.isEmpty
                    ? '!'
                    : '${controller.alarms.length}',
              ),
              child: Icon(
                Icons.sos_rounded,
                color: controller.alarms.isNotEmpty || hasError
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
          );
    final Widget banner = controller.alarms.isEmpty
        ? const SizedBox.shrink()
        : Material(
            key: const ValueKey('emergency_active_banner'),
            color: Theme.of(context).colorScheme.errorContainer,
            child: Semantics(
              liveRegion: true,
              child: InkWell(
                onTap: _openAlarmPanel,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${controller.alarms.first.title} • ${controller.alarms.first.siteName}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
          );
    return (action, banner);
  }

  void _openAlarmPanel() {
    // The user gesture belongs to SOS/opening the alarm, never an artificial
    // incident or a separate test button. A silent manager stays silent.
    if (_controller.canSound) unawaited(_controller.enableSound());
    if (_controller.error != null) unawaited(_controller.refresh());
    unawaited(_showAlarms());
  }
}
