import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/managed_user_account.dart';
import 'package:site_kapi_kontrol/models/managed_user_page.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/ui/design/app_card.dart';
import 'package:site_kapi_kontrol/ui/design/motion_widgets.dart';
import 'package:site_kapi_kontrol/ui/design/tokens.dart';
import 'package:site_kapi_kontrol/ui/widgets/list_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/managed_user_card.dart';
import 'package:site_kapi_kontrol/ui/widgets/workspace_split_shell.dart';

class ManagedUsersView extends StatelessWidget {
  const ManagedUsersView({
    super.key,
    required this.role,
    required this.session,
    required this.pageData,
    required this.users,
    required this.loading,
    required this.busyActivationUsers,
    required this.onRefresh,
    required this.onLoadPage,
    required this.onOpenAddDialog,
    required this.onToggleActivation,
    required this.onShowUserDetails,
    this.onDeleteUser,
  });

  final UserRole role;
  final UserSession session;
  final ManagedUserPage? pageData;
  final List<ManagedUserAccount> users;
  final bool loading;
  final Set<int> busyActivationUsers;
  final VoidCallback onRefresh;
  final ValueChanged<int> onLoadPage;
  final VoidCallback onOpenAddDialog;
  final void Function(ManagedUserAccount user, bool value) onToggleActivation;
  final ValueChanged<ManagedUserAccount> onShowUserDetails;
  final ValueChanged<ManagedUserAccount>? onDeleteUser;

  String _roleTitle(UserRole r) {
    switch (r) {
      case UserRole.superUser:
        return 'Süper Kullanıcı';
      case UserRole.siteManager:
        return 'Site Yöneticisi';
      case UserRole.apartmentOwner:
        return 'Daire Sakini';
      case UserRole.individual:
        return 'Bireysel Kullanıcı';
    }
  }

  String _rolePlural(UserRole r) {
    switch (r) {
      case UserRole.superUser:
        return 'Süper Kullanıcılar';
      case UserRole.siteManager:
        return 'Site Yöneticileri';
      case UserRole.apartmentOwner:
        return 'Daire Sakinleri';
      case UserRole.individual:
        return 'Bireysel Kullanıcılar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = pageData;
    final p = context.palette;
    final th = Theme.of(context).textTheme;

    return WorkspaceSplitShell(
      leftFlex: 4,
      rightFlex: 8,
      header: PageHeaderCard(
        title: _rolePlural(role),
        action: ElevatedButton.icon(
          onPressed: onOpenAddDialog,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text('Yeni ${_roleTitle(role)}'),
        ),
      ),
      left: WorkspacePaneCard(
        icon: Icons.badge_outlined,
        title: 'Rol Özeti & İşlemler',
        subtitle: 'Kayıtlı kullanıcı sayısı ve yeni hesap ekleme.',
        tone: AppTone.primary,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              page == null
                  ? 'Kullanıcı kayıtları yükleniyor.'
                  : 'Toplam ${page.total} kayıtlı hesap.',
              style: th.bodyMedium?.copyWith(color: p.text, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppSpace.sm),
            Text(
              'Sağdaki listeden hesap durumunu değiştirebilir veya kullanıcı detaylarını inceleyebilirsiniz.',
              style: th.bodySmall?.copyWith(color: p.textSecondary),
            ),
          ],
        ),
      ),
      right: WorkspacePaneCard(
        icon: Icons.groups_rounded,
        title: 'Kayıtlı Hesaplar',
        subtitle: 'Kullanıcı listesi, durum ve sayfa gezintisi.',
        tone: AppTone.primary,
        onRefresh: loading ? null : onRefresh,
        refreshIcon: Icons.refresh,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionHeader(
              title: page == null
                  ? _rolePlural(role)
                  : '${_rolePlural(role)} (${page.total})',
            ),
            const SizedBox(height: AppSpace.md),
            if (loading && page == null)
              const ListSkeleton()
            else if (users.isEmpty)
              EmptyCard(
                icon: Icons.group_outlined,
                title: 'Kayıtlı ${_rolePlural(role).toLowerCase()} bulunamadı.',
              )
            else ...[
              for (var i = 0; i < users.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpace.md),
                  child: StaggeredEntry(
                    index: i,
                    child: ManagedUserCard(
                      user: users[i],
                      isSelf: users[i].id == session.id,
                      activationBusy: busyActivationUsers.contains(users[i].id),
                      onActivationChanged: (value) =>
                          onToggleActivation(users[i], value),
                      onTap: () => onShowUserDetails(users[i]),
                      onDelete: onDeleteUser != null
                          ? () => onDeleteUser!(users[i])
                          : null,
                    ),
                  ),
                ),
              if (page != null)
                PaginationBar(
                  label:
                      'Sayfa ${page.page} / ${page.totalPages} | Toplam ${page.total}',
                  onPrevious:
                      page.page > 1 ? () => onLoadPage(page.page - 1) : null,
                  onNext: page.page < page.totalPages
                      ? () => onLoadPage(page.page + 1)
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }
}
