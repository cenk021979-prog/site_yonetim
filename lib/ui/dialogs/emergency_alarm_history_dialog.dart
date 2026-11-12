import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';

/// ACK and event resolution do not delete records. The server scopes every page to the current account.
class EmergencyAlarmHistoryDialog extends StatefulWidget {
  const EmergencyAlarmHistoryDialog({super.key, required this.service});
  final EmergencyService service;
  @override
  State<EmergencyAlarmHistoryDialog> createState() =>
      _EmergencyAlarmHistoryDialogState();
}

class _EmergencyAlarmHistoryDialogState
    extends State<EmergencyAlarmHistoryDialog> {
  List<EmergencyAlarm> _alarms = [];
  bool _loading = true, _hasMore = false;
  String? _error;
  int _token = 0;
  String? _authScope;
  String? get _currentAuthScope {
    final session = widget.service.authService.session;
    return session == null
        ? null
        : '${session.id}:${session.role.name}:${session.token}';
  }

  @override
  void initState() {
    super.initState();
    _authScope = _currentAuthScope;
    widget.service.authService.addListener(_authChanged);
    unawaited(_load());
  }

  void _authChanged() {
    if (_authScope == _currentAuthScope) return;
    _authScope = _currentAuthScope;
    ++_token;
    setState(() {
      _alarms = [];
      _hasMore = false;
      _error = null;
      _loading = false;
    });
    if (_authScope != null) unawaited(_load());
  }

  @override
  void dispose() {
    ++_token;
    widget.service.authService.removeListener(_authChanged);
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final token = ++_token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.service.alarmHistory(
        beforeId: more ? _alarms.lastOrNull?.id : null,
      );
      if (!mounted || token != _token) return;
      setState(() {
        _alarms = more ? [..._alarms, ...page.alarms] : page.alarms;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = 'Alarm geçmişi alınamadı. Yeniden deneyin.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Alarm kayıtları'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading) const LinearProgressIndicator(),
            if (!_loading && _alarms.isEmpty && _error == null)
              const Text('Erişebildiğiniz alarm kaydı yok.'),
            for (final alarm in _alarms)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '#${alarm.id} • ${alarm.title}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      [
                        alarm.siteName,
                        ?alarm.location,
                      ].where((s) => s.isNotEmpty).join(' • '),
                    ),
                    Text(
                      'Alarmı veren: ${alarm.createdByName ?? 'Eski kayıtta isim bulunmuyor'}',
                    ),
                    if (alarm.kind == 'fire')
                      Text(
                        alarm.scope == 'site'
                            ? 'Kapsam: Tüm site'
                            : 'Kapsam: Seçili blok',
                      ),
                    if (alarm.createdAt != null)
                      Text('${alarm.createdAt!.toLocal()}'),
                    Text(switch (alarm.status) {
                      'resolved' => 'Olay kapatıldı',
                      'acknowledged' => 'Görevli gördü',
                      _ => 'Açık',
                    }),
                  ],
                ),
              ),
            if (_error != null) Text(_error!),
            if (_hasMore)
              TextButton(
                onPressed: _loading ? null : () => _load(more: true),
                child: const Text('Önceki kayıtlar'),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _loading ? null : _load,
        child: const Text('Yenile'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Kapat'),
      ),
    ],
  );
}
