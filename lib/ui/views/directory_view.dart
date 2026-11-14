import 'dart:async';

import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/helpers/paged_loader.dart' show crmMessageOf;
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';
import 'package:url_launcher/url_launcher.dart';

/// Telefon uygulamasında bir adres açar (`tel:`); açılamazsa false.
typedef DirectoryLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLauncher(Uri uri) async {
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

/// Sakin "Rehber" ekranı (`directory` modülü): yönetici, kurul ve görevlerin adı/görevi ve yönetimin eklediği faydalı
/// telefonlar. Telefona dokununca arama açılır. Yalnız rehberde göstermeye izin verilen kişiler ve elle girilen telefonlar
/// gelir (sunucu süzer). HATA ASLA "rehber boş" demez.
class DirectoryView extends StatefulWidget {
  const DirectoryView({super.key, required this.authService, this.launcher = _defaultLauncher});

  final AuthService authService;
  final DirectoryLauncher launcher;

  @override
  State<DirectoryView> createState() => DirectoryViewState();
}

class DirectoryViewState extends State<DirectoryView> {
  List<DirectorySite> _sites = const <DirectorySite>[];
  bool _loading = true;
  String? _error;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    ++_token;
    super.dispose();
  }

  Future<void> reload() async {
    final token = ++_token;
    setState(() {
      _loading = _sites.isEmpty;
      _error = null;
    });
    try {
      final sites = await widget.authService.getDirectory();
      if (!mounted || token != _token) return;
      setState(() {
        _sites = sites;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _error = crmMessageOf(e, 'Rehber yüklenemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      });
    }
  }

  Future<void> _call(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final ok = await widget.launcher(Uri(scheme: 'tel', path: cleaned));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Arama başlatılamadı. Numara: $phone')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context).textTheme;
    final secondary = th.bodyMedium?.copyWith(color: context.palette.textSecondary);
    if (_loading) return Padding(padding: const EdgeInsets.all(AppSpace.lg), child: Text('Rehber yükleniyor...', style: secondary));
    if (_error != null) return InlineNotice(message: _error!, onRetry: reload);
    if (_sites.isEmpty) {
      return WorkspaceSplitShell(
        left: WorkspacePaneCard(
          icon: Icons.contact_phone_outlined,
          title: 'Rehber',
          child: Text('Site yönetimi ve faydalı telefonlar bir siteye bağlandığınızda burada yer alır.', style: secondary),
        ),
        right: WorkspacePaneCard(
          child: Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Text('Bir siteye bağlı olduğunuzda rehber burada görünür.', style: secondary),
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, site) in _sites.indexed) ...[
          if (index > 0) const SizedBox(height: AppSpace.lg),
          WorkspaceSplitShell(
            header: _sites.length > 1 ? Text(site.siteName, style: th.titleLarge) : null,
            left: WorkspacePaneCard(
              icon: Icons.badge_outlined,
              title: 'Yönetim ve Kadro',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (site.managers.isNotEmpty) _section(context, 'Yönetim', [for (final m in site.managers) _row(context, m, 'Site yöneticisi', null)]),
                  if (site.board.isNotEmpty) _section(context, 'Yönetim kurulu', [for (final p in site.board) _row(context, p.fullName, p.label, p.phone)]),
                  if (site.staff.isNotEmpty) _section(context, 'Görevliler', [for (final p in site.staff) _row(context, p.fullName, p.label, p.phone)]),
                  if (site.managers.isEmpty && site.board.isEmpty && site.staff.isEmpty)
                    Text('Yönetim veya görevli iletişim kaydı yok.', style: secondary),
                ],
              ),
            ),
            right: WorkspacePaneCard(
              icon: Icons.contact_phone_outlined,
              title: 'Faydalı Telefonlar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (site.isEmpty)
                    Text('Henüz kayıt eklenmedi.', style: secondary)
                  else if (site.contacts.isNotEmpty)
                    _section(context, 'Faydalı telefonlar', [
                      for (final c in site.contacts) _row(context, c.label, kContactCategoryLabels[c.category] ?? '', c.phone, note: c.note),
                    ])
                  else
                    Text('Faydalı telefon kaydı eklenmedi.', style: secondary),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _section(BuildContext context, String title, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpace.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Text(title, style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: AppSpace.sm), ...rows],
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String name, String subtitle, String? phone, {String? note}) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(name),
      subtitle: Text([subtitle, ?phone, ?note].where((e) => e.isNotEmpty).join('\n')),
      isThreeLine: phone != null && (note != null || subtitle.isNotEmpty),
      trailing: phone == null
          ? null
          : IconButton(
              tooltip: 'Ara',
              icon: const Icon(Icons.call_rounded),
              onPressed: () => unawaited(_call(phone)),
            ),
    );
  }
}
