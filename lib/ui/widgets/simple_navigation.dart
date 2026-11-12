import 'package:flutter/material.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_task_surface.dart';

class SimpleTopicBar extends StatelessWidget {
  const SimpleTopicBar({super.key, required this.audience, required this.selected, required this.onSelected});
  final ShowcaseAudience audience;
  final SimpleTopic selected;
  final ValueChanged<SimpleTopic> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: ConstrainedBox(
      constraints: BoxConstraints(minWidth: constraints.maxWidth),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [for (final topic in simpleTopics(audience)) Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: ChoiceChip(key: ValueKey('simple_topic_${topic.name}'), label: Text(topic.label), selected: selected == topic, onSelected: (_) => onSelected(topic)),
        )]),
      ),
    ),
  ));
}

class SimpleModuleList extends StatelessWidget {
  const SimpleModuleList({super.key, required this.items, required this.audience, required this.topic, required this.role, required this.badges, required this.onOpen, this.badgeNouns = const {}, this.featuredItems, this.onHelp, this.onGuestPass, this.onAllActions, this.todayOverview, this.focusEntries = const [], this.onTopicSelected});
  final List<SirketMenuItem> items;
  final ShowcaseAudience audience;
  final SimpleTopic topic;
  final UserRole role;
  final Map<SirketMenuItem, int> badges;
  final Map<SirketMenuItem, String> badgeNouns;
  final Set<SirketMenuItem>? featuredItems;
  final ValueChanged<SirketMenuItem> onOpen;
  final VoidCallback? onHelp;
  final VoidCallback? onGuestPass;
  final VoidCallback? onAllActions;
  final Widget? todayOverview;
  final List<ShowcaseFocusEntry> focusEntries;
  final ValueChanged<SimpleTopic>? onTopicSelected;
  @override
  Widget build(BuildContext context) {
    final groups = simpleGroups(visibleItems: items, audience: audience, topic: topic, featuredItems: featuredItems);
    if (topic == SimpleTopic.today) {
      return Column(key: const ValueKey('simple_module_list'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ?todayOverview,
        for (final entry in focusEntries) Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: onTopicSelected == null
          ? Text(entry.text, style: Theme.of(context).textTheme.titleSmall)
          : ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.text), trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onTopicSelected!(simpleTopicFor(entry.item, audience)))),
      ]);
    }
    final mode = ViewModeScope.modeOf(context, ViewScreen.simpleModules);
    final toggle = ViewModeToggle.maybe(context, ViewScreen.simpleModules);
    final supportOwner = audience == ShowcaseAudience.admin ? SimpleTopic.management : SimpleTopic.site;
    final entries = <SimpleTaskEntry>[
      for (final group in groups.entries) for (final item in group.value)
        SimpleTaskEntry(id: 'simple_route_${item.name}', title: YanMenu.titleFor(item, role), group: group.key,
          icon: YanMenu.iconFor(item), description: showcaseDescription(item, role), badge: badges[item] ?? 0,
          badgeNoun: badgeNouns[item] ?? 'bekleyen', onTap: () => onOpen(item)),
      if (onGuestPass != null && topic == SimpleTopic.home)
        SimpleTaskEntry(id: 'simple_action_guest_pass', title: 'Ziyaretçi kodu', group: 'Geçiş ve cihazlar', icon: Icons.qr_code_rounded,
          description: 'Misafir ve kurye için süreli geçiş bağlantısı', onTap: onGuestPass!),
      if (topic == supportOwner && onAllActions != null)
        SimpleTaskEntry(id: 'simple_action_all', title: 'Tüm işlemler', group: 'Yardım ve erişim', icon: Icons.apps_rounded,
          description: 'Hesabınıza açık bütün işlemler', onTap: onAllActions!),
      if (topic == supportOwner && onHelp != null)
        SimpleTaskEntry(id: 'simple_action_help', title: 'Yardım ve Destek', group: 'Yardım ve erişim', icon: Icons.help_outline_rounded,
          description: 'Kullanım rehberi', onTap: onHelp!),
    ];
    return Column(key: const ValueKey('simple_module_list'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
        Expanded(child: Text('${entries.length} işlem', style: Theme.of(context).textTheme.labelLarge)),
        ?toggle,
      ])),
      if (entries.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Bu konuda hesabınıza açık işlem bulunmuyor.')),
      SimpleTaskSurface(entries: entries, mode: mode),
    ]);
  }
}

/// Existing notifier data only; no navigation action and no inferred success.
class SimpleTodayOverview extends StatelessWidget {
  const SimpleTodayOverview({super.key, required this.canReceiveAnnouncements, this.unreadCount, this.degraded = false, this.onOpenTopic});
  final bool canReceiveAnnouncements;
  final int? unreadCount;
  final bool degraded;
  final VoidCallback? onOpenTopic;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = !canReceiveAnnouncements
        ? 'Güncel bildirimler ve dikkat gerektiren durumlar burada özetlenir.'
        : degraded
          ? (unreadCount == null ? 'Bildirim bilgisi güncellenemedi.' : 'Bildirim bilgisi güncellenemedi. Son alınan sayı: $unreadCount okunmamış duyuru.')
          : (unreadCount == null ? 'Bildirim özeti henüz alınamadı.' : '$unreadCount okunmamış duyuru');
    return Container(
      key: const ValueKey('simple_today_summary'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: .6))),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(degraded ? Icons.sync_problem_rounded : Icons.notifications_none_rounded, color: theme.colorScheme.primary),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Güncel durum', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(message, style: theme.textTheme.bodyMedium),
          if (onOpenTopic != null && canReceiveAnnouncements && (unreadCount ?? 0) > 0)
            TextButton(onPressed: onOpenTopic, child: const Text('İlgili bölüme git')),
        ])),
      ]),
    );
  }
}
