import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/account_export_share.dart' show ExportShareOutcome;
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_file_delivery.dart';
import 'package:site_kapi_kontrol/ui/design/app_dialog.dart';
import 'package:site_kapi_kontrol/ui/design/buttons.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';

class ResidentUsernamesDownloadDialog extends StatefulWidget {
  const ResidentUsernamesDownloadDialog({
    super.key,
    required this.siteCode,
    required this.authService,
    this.initialQuery,
    this.delivery,
  });

  final int siteCode;
  final AuthService authService;
  final String? initialQuery;
  final BulkFileDelivery? delivery;

  static Future<bool?> show(
    BuildContext context, {
    required int siteCode,
    required AuthService authService,
    String? initialQuery,
    BulkFileDelivery? delivery,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ResidentUsernamesDownloadDialog(
        siteCode: siteCode,
        authService: authService,
        initialQuery: initialQuery,
        delivery: delivery,
      ),
    );
  }

  @override
  State<ResidentUsernamesDownloadDialog> createState() =>
      _ResidentUsernamesDownloadDialogState();
}

class _ResidentUsernamesDownloadDialogState
    extends State<ResidentUsernamesDownloadDialog> {
  late final TextEditingController _unitController;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _unitController = TextEditingController(text: widget.initialQuery ?? '');
  }

  @override
  void dispose() {
    _unitController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    final messenger = ScaffoldMessenger.of(context);
    final render = context.findRenderObject();
    final origin = render is RenderBox && render.hasSize
        ? render.localToGlobal(Offset.zero) & render.size
        : null;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final query = _unitController.text.trim();
      final envelope = await widget.authService.exportResidentUsernames(
        widget.siteCode,
        query: query.isEmpty ? null : query,
      );

      final file = await renderExportAsync(
        envelope,
        ExportFormat.xlsx,
        sheetName: 'Kullanıcı Adları',
      );

      final deliverer = widget.delivery ?? BulkFileSharer();
      final outcome = await deliverer.deliver(
        file,
        sharePositionOrigin: origin,
        subject: 'Daire kullanıcı adları listesi',
      );

      if (!mounted) return;

      if (outcome != ExportShareOutcome.dismissed) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              BulkFileSharer.platformUsesSaveDialog
                  ? 'Kullanıcı adları dosyası kaydedildi: ${file.fileName}'
                  : 'Kullanıcı adları listesi hazırlandı.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            'Kullanıcı adları listesi indirilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.';
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      title: 'Kullanıcı Adlarını İndir',
      subtitle:
          'Sakinlerin sisteme giriş yapabilmesi için kullanıcı adlarını ve başlangıç şifrelerini Excel olarak indirin.',
      icon: Icons.badge_outlined,
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('İptal'),
        ),
        PrimaryActionButton(
          label: _busy ? 'Hazırlanıyor...' : 'İndir (Excel)',
          icon: Icons.download_rounded,
          onPressed: _busy ? null : _download,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpace.xs),
          TextFormField(
            controller: _unitController,
            enabled: !_busy,
            decoration: const InputDecoration(
              labelText: 'Daire No (İsteğe bağlı)',
              hintText: 'Tüm daireler için boş bırakın (örn: Daire 1)',
              prefixIcon: Icon(Icons.apartment_rounded),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _download(),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}
