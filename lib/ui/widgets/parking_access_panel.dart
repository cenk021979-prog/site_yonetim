import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/parking_access.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmInt;
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

/// Apartment approval is separate from optional capacity enforcement. Never approves individual plates.
class ParkingAccessPanel extends StatefulWidget {
  const ParkingAccessPanel({
    super.key,
    required this.service,
    required this.siteCode,
    required this.canWrite,
  });
  final PlateRecognitionService service;
  final int siteCode;
  final bool canWrite;
  @override
  State<ParkingAccessPanel> createState() => _ParkingAccessPanelState();
}

class _ParkingAccessPanelState extends State<ParkingAccessPanel> {
  ParkingOverview? _data;
  String? _error;
  bool _busy = false;
  int _generation = 0;
  final _capacity = TextEditingController();
  bool _enabled = false;
  bool _photo = false;
  bool _clientsConfirmed = false;
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant ParkingAccessPanel old) {
    super.didUpdateWidget(old);
    if (old.siteCode != widget.siteCode ||
        old.service != widget.service ||
        old.canWrite != widget.canWrite) {
      ++_generation;
      _data = null;
      _clientsConfirmed = false;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    ++_generation;
    _capacity.dispose();
    super.dispose();
  }

  void _apply(ParkingOverview data) {
    _data = data;
    _enabled = data.enabled;
    _photo = data.photoEnabled;
    _capacity.text = data.capacity?.toString() ?? '';
  }

  Future<void> _load() => _run(() => widget.service.parking(widget.siteCode));
  Future<void> _run(Future<ParkingOverview> Function() action) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await action();
      if (!mounted || generation != _generation) return;
      setState(() => _apply(result));
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = crmMessageOf(e, 'Otopark işlemi tamamlanamadı.'),
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _editApartment(Map<String, dynamic> apartment) async {
    final scope = _generation;
    final site = widget.siteCode;
    final auth = widget.service.authService.session?.token;
    final input = TextEditingController(
      text: '${crmInt(apartment['parking_slots'])}',
    );
    bool approved = apartment['approved'] == true;
    String? error;
    final result = await showDialog<({int slots, bool approved})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AppDialog(
          title:
              '${apartment['block_name'] ?? ''} / ${apartment['unit_label'] ?? ''}',
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () {
                final slots = int.tryParse(input.text);
                if (slots == null || slots < 0 || slots > 50) {
                  update(() => error = '0–50 arası sayı girin.');
                  return;
                }
                Navigator.pop(context, (slots: slots, approved: approved));
              },
              child: const Text('Kaydet'),
            ),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Onay, dairenin şimdi ve ileride eklenen tüm plakalarını kapsar. Araç hakkı aynı anda içeride bulunabilecek araç sayısıdır.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Dairenin araç girişlerini onayla'),
                value: approved,
                onChanged: (v) => update(() => approved = v == true),
              ),
              TextField(
                controller: input,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Eşzamanlı araç hakkı (0–50)',
                  errorText: error,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // The route transition can still reference the controller during its exit frame.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    input.dispose();
    if (result == null ||
        !mounted ||
        scope != _generation ||
        site != widget.siteCode ||
        !widget.canWrite ||
        auth != widget.service.authService.session?.token) {
      return;
    }
    await _run(
      () => widget.service.saveApartmentParking(
        widget.siteCode,
        crmInt(apartment['id']),
        approved: result.approved,
        slots: result.slots,
      ),
    );
  }

  Future<void> _release(Map<String, dynamic> record) async {
    final scope = _generation;
    final site = widget.siteCode;
    final auth = widget.service.authService.session?.token;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Geçiş kaydını düzelt'),
        content: Text(
          '${record['plate']} için aracın dışarıda olduğunu ve bekleyen kapı komutu kalmadığını fiziksel olarak kontrol edin. Onaylandığında kontenjan serbest bırakılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kontrol ettim, dışarıda'),
          ),
        ],
      ),
    );
    if (yes == true &&
        mounted &&
        scope == _generation &&
        site == widget.siteCode &&
        widget.canWrite &&
        auth == widget.service.authService.session?.token) {
      await _run(
        () => widget.service.releaseParking(
          widget.siteCode,
          crmInt(record['id']),
          legacyPresence: record['origin'] == 'presence',
        ),
      );
    }
  }

  Future<void> _viewPhoto(int apartment, int vehicle) async {
    final scope = _generation;
    final site = widget.siteCode;
    final auth = widget.service.authService.session?.token;
    try {
      final encoded = await widget.service.parkingPhoto(apartment, vehicle);
      final bytes = base64Decode(encoded);
      if (!mounted ||
          scope != _generation ||
          site != widget.siteCode ||
          auth != widget.service.authService.session?.token) {
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 720,
              maxHeight: MediaQuery.sizeOf(context).height * .85,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: InteractiveViewer(
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('Fotoğraf görüntülenemedi.'),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Kapat'),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted &&
          scope == _generation &&
          site == widget.siteCode &&
          auth == widget.service.authService.session?.token) {
        setState(
          () => _error = crmMessageOf(e, 'Ruhsat fotoğrafı görüntülenemedi.'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Daire araç onayları ve otopark',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            IconButton(
              tooltip: 'Yenile',
              onPressed: _busy ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (data != null) ...[
          Text(
            'Geçiş kaydına göre yer kullanan araç: ${data.total}${data.capacity == null ? '' : ' / ${data.capacity}'}',
          ),
          const SizedBox(height: 8),
          Text(data.notice),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('parking_capacity'),
            controller: _capacity,
            enabled: widget.canWrite && !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Sitenin toplam otopark kapasitesi (araç)',
              helperText: 'Boşsa toplam kapasite tanımlı değildir.',
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Eşzamanlı araç ve toplam kapasite denetimi'),
            subtitle: const Text(
              'Daire onayı bu anahtardan bağımsızdır. Denetim açıkken bağlantı kesilirse otomatik giriş verilmez.',
            ),
            value: _enabled,
            onChanged: widget.canWrite && !_busy
                ? (v) => setState(() => _enabled = v)
                : null,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('İsteğe bağlı ruhsat fotoğrafı yüklemesi'),
            subtitle: const Text(
              'PNG/JPEG, en fazla 512 KB. Fotoğraf araç girişi için zorunlu değildir.',
            ),
            value: _photo,
            onChanged: widget.canWrite && !_busy
                ? (v) => setState(() => _photo = v)
                : null,
          ),
          if (_enabled && widget.canWrite)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _clientsConfirmed,
              title: const Text('Tüm izleme istemcilerini güncelledim.'),
              subtitle: const Text(
                'Eski veya çevrimdışı yerel açma yapan istemciler sunucu kontenjanını aşabilir. Yalnız güncel uygulamayı kullanın.',
              ),
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _clientsConfirmed = v == true),
            ),
          if (widget.canWrite)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => unawaited(
                        _run(
                          () => widget.service.saveParking(widget.siteCode, {
                            'enabled': _enabled,
                            'capacity': _capacity.text.trim().isEmpty
                                ? null
                                : int.tryParse(_capacity.text),
                            'registration_photo_enabled': _photo,
                            'confirm_updated_clients': _clientsConfirmed,
                          }),
                        ),
                      ),
                child: const Text('Otopark ayarlarını kaydet'),
              ),
            ),
          const SizedBox(height: 16),
          for (final apartment in data.apartments)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${apartment['block_name'] ?? ''} / ${apartment['unit_label'] ?? ''}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      '${apartment['approved'] == true ? 'Daire onaylı' : 'Daire onayı bekliyor'} • Araç hakkı: ${apartment['parking_slots'] ?? 0}',
                    ),
                    Text(
                      'Kayıtlı plakalar: ${(apartment['plates'] as List? ?? []).join(', ')}',
                    ),
                    Text(
                      'Geçiş kaydındaki plakalar: ${(apartment['inside_plates'] as List? ?? []).join(', ')}',
                    ),
                    if (widget.canWrite)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _busy
                              ? null
                              : () => unawaited(_editApartment(apartment)),
                          child: const Text('Daire onayı / araç hakkı'),
                        ),
                      ),
                    if (widget.canWrite && data.photoEnabled)
                      Wrap(
                        children: [
                          for (final photo in parkingRows(
                            apartment['photo_vehicles'],
                          ))
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(
                                      _viewPhoto(
                                        crmInt(apartment['id']),
                                        crmInt(photo['id']),
                                      ),
                                    ),
                              child: Text('Ruhsat: ${photo['plate']}'),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          if (data.reservations.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Kontenjan kullanan komut kayıtları',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            for (final r in data.reservations)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${r['plate']} • ${r['status'] == 'accepted'
                            ? 'Komut kabul edildi; geçiş sensör teyidi yok'
                            : r['status'] == 'legacy'
                            ? 'Önceki geçiş kaydı; sensör teyidi yok'
                            : 'Komut bekliyor / sonuç belirsiz'}',
                      ),
                      if (widget.canWrite)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _busy
                                ? null
                                : () => unawaited(_release(r)),
                            child: const Text(
                              'Fiziksel kontrol sonrası düzelt',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ],
    );
  }
}
