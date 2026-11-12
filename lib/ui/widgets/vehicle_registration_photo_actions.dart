import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/services/apartment_management_api.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart'
    show crmMessageOf;

/// Authenticated images only: no public URL, path or registration image in logs.
class VehicleRegistrationPhotoActions extends StatefulWidget {
  const VehicleRegistrationPhotoActions({
    super.key,
    required this.service,
    required this.apartmentId,
    required this.vehicleId,
    required this.hasPhoto,
    required this.onChanged,
    this.canUpload = true,
  });
  final ApartmentManagementService service;
  final int apartmentId;
  final int vehicleId;
  final bool hasPhoto;
  final bool canUpload;
  final Future<void> Function() onChanged;
  @override
  State<VehicleRegistrationPhotoActions> createState() =>
      _VehicleRegistrationPhotoActionsState();
}

class _VehicleRegistrationPhotoActionsState
    extends State<VehicleRegistrationPhotoActions> {
  bool _busy = false;
  int _scope = 0;
  String? get _authScope => widget.service.authService.session?.token;
  String? _knownAuthScope;
  @override
  void initState() {
    super.initState();
    _knownAuthScope = _authScope;
  }

  @override
  void didUpdateWidget(covariant VehicleRegistrationPhotoActions old) {
    super.didUpdateWidget(old);
    if (old.apartmentId != widget.apartmentId ||
        old.vehicleId != widget.vehicleId ||
        old.service != widget.service ||
        old.canUpload != widget.canUpload ||
        _knownAuthScope != _authScope) {
      ++_scope;
      _busy = false;
      _knownAuthScope = _authScope;
    }
  }

  @override
  void dispose() {
    ++_scope;
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    final scope = _scope;
    final auth = _authScope;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted && scope == _scope && auth == _authScope) {
        AppSnack.show(
          context,
          crmMessageOf(e, 'Ruhsat fotoğrafı işlemi tamamlanamadı.'),
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted && scope == _scope) setState(() => _busy = false);
    }
  }

  Future<void> _upload() => _run(() async {
    final scope = _scope;
    final target = widget;
    final auth = _authScope;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (file == null || !mounted || scope != _scope || auth != _authScope) {
      return;
    }
    final length = await file.length();
    if (!mounted || scope != _scope || auth != _authScope) return;
    if (length != null && length > 524288) {
      AppSnack.show(
        context,
        'En fazla 512 KB PNG veya JPEG fotoğrafı seçin.',
        kind: AppSnackKind.error,
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted || scope != _scope || auth != _authScope) return;
    if (bytes.isEmpty || bytes.length > 524288) {
      throw const FormatException('Fotoğraf en fazla 512 KB olmalı.');
    }
    await target.service.putRegistrationPhoto(
      target.apartmentId,
      target.vehicleId,
      bytes: bytes,
      mimeType: file.name.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg',
    );
    if (mounted && scope == _scope && auth == _authScope) {
      await target.onChanged();
    }
  });
  Future<void> _view() => _run(() async {
    final scope = _scope;
    final target = widget;
    final auth = _authScope;
    final bytes = await target.service.registrationPhoto(
      target.apartmentId,
      target.vehicleId,
    );
    if (!mounted || scope != _scope || auth != _authScope) return;
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
                    errorBuilder: (_, _, _) => const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Fotoğraf görüntülenemedi.'),
                    ),
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
  });
  Future<void> _remove() => _run(() async {
    final scope = _scope;
    final target = widget;
    final auth = _authScope;
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ruhsat fotoğrafını kaldır'),
        content: const Text(
          'Yüklediğiniz fotoğraf silinecek. Araç kaydı ve daire onayı değişmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted || scope != _scope || auth != _authScope) {
      return;
    }
    await target.service.removeRegistrationPhoto(
      target.apartmentId,
      target.vehicleId,
    );
    if (mounted && scope == _scope && auth == _authScope) {
      await target.onChanged();
    }
  });
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 4,
    children: [
      if (widget.canUpload)
        TextButton.icon(
          onPressed: _busy ? null : () => unawaited(_upload()),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('Ruhsat fotoğrafı (isteğe bağlı, en fazla 512 KB)'),
        ),
      if (widget.hasPhoto)
        TextButton(
          onPressed: _busy ? null : () => unawaited(_view()),
          child: const Text('Ruhsatı görüntüle'),
        ),
      if (widget.hasPhoto && widget.canUpload)
        TextButton(
          onPressed: _busy ? null : () => unawaited(_remove()),
          child: const Text('Fotoğrafı kaldır'),
        ),
    ],
  );
}
