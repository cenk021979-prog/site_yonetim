import 'package:flutter/material.dart';

/// Henüz bir siteye bağlanmamış kullanıcı için erişilebilir hesap eylemleri.
class UnaffiliatedAccountMenu extends StatelessWidget {
  const UnaffiliatedAccountMenu({
    super.key,
    required this.fullName,
    required this.onProfile,
    required this.onLogout,
  });

  final String fullName;
  final VoidCallback onProfile;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: const ValueKey('unaffiliated_account_menu'),
    tooltip: 'Hesap',
    icon: const Icon(Icons.account_circle_outlined, size: 22),
    onSelected: (value) => value == 'profile' ? onProfile() : onLogout(),
    itemBuilder: (_) => [
      PopupMenuItem(
        value: 'profile',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.person_outline_rounded),
          title: Text(
            fullName.isEmpty ? 'Profilim' : fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      const PopupMenuDivider(),
      const PopupMenuItem(
        value: 'logout',
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.logout_rounded),
          title: Text('Çıkış Yap'),
        ),
      ),
    ],
  );
}
