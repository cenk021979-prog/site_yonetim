import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

Future<bool?> showEmergencyRespondersDialog(
  BuildContext context, {
  required EmergencyService service,
  required int siteCode,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      EmergencyRespondersDialog(service: service, siteCode: siteCode),
);

/// Güvenlik yalnız site personelinden; servis yalnız var olan hesap + bu sitenin
/// anlaşmalı firmasından seçilir. Tüm yetki ve hesap eşleştirmeleri sunucuda doğrulanır.
class EmergencyRespondersDialog extends StatefulWidget {
  const EmergencyRespondersDialog({
    super.key,
    required this.service,
    required this.siteCode,
  });
  final EmergencyService service;
  final int siteCode;
  @override
  State<EmergencyRespondersDialog> createState() =>
      _EmergencyRespondersDialogState();
}

class _EmergencyRespondersDialogState extends State<EmergencyRespondersDialog> {
  final _login = TextEditingController();
  List<Map<String, dynamic>> _rows = [], _candidates = [], _vendors = [];
  int? _security, _vendor;
  bool _loading = true, _saving = false;
  String? _error;
  List<Map<String, dynamic>> _maps(Object? raw) => raw is List
      ? raw
            .whereType<Map<String, dynamic>>()
            .map(Map<String, dynamic>.of)
            .toList()
      : [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _login.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.service.responders(widget.siteCode);
      if (!mounted) return;
      setState(() {
        _rows = _maps(data['responders']);
        _candidates = _maps(data['security_candidates']);
        _vendors = _maps(data['vendors']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = crmMessageOf(e, 'Alarm alıcıları alınamadı.');
        });
      }
    }
  }

  void _addSecurity() {
    final chosen = _candidates
        .where((c) => c['user_code'] == _security)
        .firstOrNull;
    if (chosen == null) return;
    if (_rows.any(
      (r) => r['role'] == 'security' && r['user_code'] == _security,
    )) {
      return;
    }
    setState(
      () => _rows.add({
        'role': 'security',
        'user_code': _security,
        'user_name': chosen['user_name'],
      }),
    );
  }

  void _addService() {
    final login = _login.text.trim();
    final vendor = _vendors.where((v) => v['id'] == _vendor).firstOrNull;
    if (login.isEmpty || vendor == null) {
      setState(
        () => _error =
            'Servis firmasını ve firmanın uygulama kullanıcı adını seçin.',
      );
      return;
    }
    if (_rows.any(
      (r) =>
          r['role'] == 'elevator_service' &&
          r['login_name'] == login &&
          r['vendor_id'] == _vendor,
    )) {
      return;
    }
    setState(() {
      _rows.add({
        'role': 'elevator_service',
        'login_name': login,
        'user_name': login,
        'vendor_id': _vendor,
        'vendor_name': vendor['name'],
      });
      _login.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveResponders(widget.siteCode, [
        for (final row in _rows)
          {
            'role': row['role'],
            if (row['user_code'] != null) 'user_code': row['user_code'],
            if (row['login_name'] != null) 'login_name': row['login_name'],
            if (row['vendor_id'] != null) 'vendor_id': row['vendor_id'],
          },
      ]);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = crmMessageOf(e, 'Alıcılar kaydedilemedi.');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: const Text('Alarm alıcıları'),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Güvenlik ve asansör servisi sesli alarm alır. Site yöneticisine yalnız uygulama içi bildirim gider. Alıcı uygulamasının açık ve bağlı olması gerekir.',
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!_loading) ...[
                for (final (index, row) in _rows.indexed)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${row['user_name'] ?? row['login_name'] ?? 'Hesap'}',
                    ),
                    subtitle: Text(
                      row['role'] == 'security'
                          ? 'Güvenlik'
                          : 'Asansör servisi • ${row['vendor_name'] ?? ''}',
                    ),
                    trailing: IconButton(
                      tooltip: 'Alıcıyı kaldır',
                      onPressed: _saving
                          ? null
                          : () => setState(() => _rows.removeAt(index)),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                if (_rows.isEmpty)
                  const Text('Sesli alarm alıcısı henüz atanmamış.'),
                const Divider(),
                const Text('Güvenlik görevlisi ekle'),
                DropdownButtonFormField<int>(
                  initialValue: _security,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Site personeli',
                  ),
                  items: [
                    for (final row in _candidates)
                      DropdownMenuItem(
                        value: row['user_code'] as int,
                        child: Text(
                          '${row['user_name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _security = value),
                ),
                TextButton(
                  onPressed: _saving || _security == null ? null : _addSecurity,
                  child: const Text('Güvenliği listeye ekle'),
                ),
                const Divider(),
                const Text('Anlaşmalı asansör servisi ekle'),
                DropdownButtonFormField<int>(
                  initialValue: _vendor,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Anlaşmalı firma',
                  ),
                  items: [
                    for (final row in _vendors)
                      DropdownMenuItem(
                        value: row['id'] as int,
                        child: Text(
                          '${row['name']}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _vendor = value),
                ),
                TextField(
                  controller: _login,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Firmanın uygulama kullanıcı adı',
                    helperText:
                        'Var olan hesabın tam kullanıcı adı. Yeni hesap açmaz.',
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _addService,
                  child: const Text('Servisi listeye ekle'),
                ),
                const Text(
                  'Değişiklikler Kaydet ile uygulanır. Firma yetkisi yalnız bu sitenin asansör alarmlarını kapsar.',
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Vazgeç'),
        ),
        if (_error != null && _rows.isEmpty)
          TextButton(
            onPressed: _saving ? null : _load,
            child: const Text('Yenile'),
          ),
        FilledButton(
          onPressed: _saving || _loading ? null : _save,
          child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
        ),
      ],
    ),
  );
}
