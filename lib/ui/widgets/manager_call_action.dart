import 'dart:async';
import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/manager_contact.dart';
import 'package:site_kapi_kontrol/ui/design/app_snack.dart';
import 'package:site_kapi_kontrol/ui/helpers/dial_call.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_tile.dart';

/// Contact is fetched when requested, so the header never retains another site's number.
class ManagerCallAction extends StatefulWidget {
  const ManagerCallAction({
    super.key,
    required this.fetch,
    this.siteCode,
    this.launcher,
  });
  final Future<List<ManagerContact>> Function() fetch;
  final int? siteCode;
  final DialLauncher? launcher;
  @override
  State<ManagerCallAction> createState() => _ManagerCallActionState();
}

class _ManagerCallActionState extends State<ManagerCallAction> {
  bool _busy = false;
  int _token = 0;
  @override
  void didUpdateWidget(ManagerCallAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteCode != widget.siteCode) {
      ++_token;
      _busy = false;
    }
  }

  Future<void> _call() async {
    if (_busy) return;
    final token = ++_token;
    final siteCode = widget.siteCode;
    setState(() => _busy = true);
    try {
      final fetched = await widget.fetch();
      if (!mounted || token != _token) return;
      final contacts = ManagerCallTile.callable(
        fetched.where((c) => siteCode == null || c.siteCode == siteCode),
      );
      if (contacts.isEmpty) {
        AppSnack.show(
          context,
          'Bu site için yönetici iletişim bilgisi bulunmuyor.',
        );
      } else {
        await ManagerCallTile.activate(
          context,
          contacts,
          launcher: widget.launcher,
        );
      }
    } catch (_) {
      if (mounted && token == _token) {
        AppSnack.show(
          context,
          'Yönetici bilgisi alınamadı. Tekrar deneyin.',
          kind: AppSnackKind.error,
        );
      }
    } finally {
      if (mounted && token == _token) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => IconButton(
    key: const ValueKey('header_call_manager'),
    tooltip: 'Yöneticiyi ara',
    onPressed: _busy ? null : () => unawaited(_call()),
    icon: _busy
        ? const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.phone_outlined, size: 21),
  );
}
