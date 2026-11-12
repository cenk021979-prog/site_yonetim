import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import 'people_fixtures.dart' show pplSession;
import 'simple_appearance_home_test.dart' show loadSimpleReviewFonts, simpleReviewTheme, simpleSettle;

Future<void> _pump(WidgetTester t, Widget child, {double width = 1100, double scale = 1, bool dark = false, ViewModeService? modes}) async {
  t.view.physicalSize = Size(width, 850);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ViewModeScope(service: modes ?? ViewModeService(), child: MaterialApp(
    theme: simpleReviewTheme(dark),
    builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: Scaffold(body: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: child))),
  )));
  await simpleSettle(t);
}

void main() {
  setUpAll(loadSimpleReviewFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('fitting topic group is genuinely centered', (t) async {
    await _pump(t, SimpleTopicBar(audience: ShowcaseAudience.resident, selected: SimpleTopic.today, onSelected: (_) {}));
    final first = t.getRect(find.byKey(const ValueKey('simple_topic_today')));
    final last = t.getRect(find.byKey(const ValueKey('simple_topic_site')));
    expect((first.left + last.right) / 2, closeTo(550, 0.5));
    expect(t.takeException(), isNull);
  });
  testWidgets('320px text2 retains access to all four scrollable topics', (t) async {
    final tapped = <SimpleTopic>[];
    await _pump(t, SimpleTopicBar(audience: ShowcaseAudience.resident, selected: SimpleTopic.today, onSelected: tapped.add), width: 320, scale: 2, dark: true);
    for (final topic in simpleTopics(ShowcaseAudience.resident)) {
      final chip = find.byKey(ValueKey('simple_topic_${topic.name}'));
      await t.ensureVisible(chip);
      await t.pump();
      expect(chip.hitTestable(), findsOneWidget);
      await t.tap(chip);
    }
    expect(tapped, simpleTopics(ShowcaseAudience.resident));
    expect(t.takeException(), isNull);
  });
  for (final (width, scale) in <(double, double)>[(320, 2), (1100, 1)]) {
    for (final dark in [false, true]) {
      testWidgets('same authorized entries in list/tiles ${width.toInt()} dark=$dark', (t) async {
        final modes = ViewModeService();
        addTearDown(modes.dispose);
        await modes.setMode(ViewScreen.modules, ListViewMode.list);
        final opened = <SirketMenuItem>[];
        const items = [SirketMenuItem.duyurular, SirketMenuItem.belgeler, SirketMenuItem.komsuPanosu];
        await _pump(t, SimpleModuleList(items: items, audience: ShowcaseAudience.resident, topic: SimpleTopic.site, role: UserRole.apartmentOwner,
          badges: {SirketMenuItem.duyurular: 3}, badgeNouns: {SirketMenuItem.duyurular: 'okunmamış'}, onOpen: opened.add), width: width, scale: scale, dark: dark, modes: modes);
        for (final item in items) {
          expect(find.byKey(ValueKey('simple_route_${item.name}')), findsOneWidget);
        }
        expect(find.textContaining('3 okunmamış'), findsOneWidget);
        expect(find.byKey(const ValueKey('simple_route_finans')), findsNothing);
        final toggle = find.byTooltip('Kutucuk görünümüne geç');
        await t.ensureVisible(toggle);
        await t.tap(toggle);
        await simpleSettle(t);
        expect(modes.modeOf(ViewScreen.simpleModules), ListViewMode.tiles);
        expect(modes.modeOf(ViewScreen.modules), ListViewMode.list, reason: 'Classic style is independent');
        for (final item in items) {
          expect(find.byKey(ValueKey('simple_route_${item.name}')), findsOneWidget);
        }
        final route = find.byKey(const ValueKey('simple_route_belgeler'));
        await t.ensureVisible(route);
        await t.tap(route);
        expect(opened, [SirketMenuItem.belgeler]);
        final restored = ViewModeService();
        await restored.load();
        expect(restored.modeOf(ViewScreen.simpleModules), ListViewMode.tiles);
        expect(restored.modeOf(ViewScreen.modules), ListViewMode.list);
        restored.dispose();
        final back = find.byTooltip('Liste görünümüne geç');
        await t.ensureVisible(back);
        await t.tap(back);
        await simpleSettle(t);
        expect(modes.modeOf(ViewScreen.simpleModules), ListViewMode.list);
        expect(t.takeException(), isNull);
      });
    }
  }
  testWidgets('resident commands and finance hero each have exactly one topic owner', (t) async {
    const items = [SirketMenuItem.dashboard, SirketMenuItem.borcum, SirketMenuItem.dairem, SirketMenuItem.duyurular, SirketMenuItem.profilim];
    final owners = <String, List<SimpleTopic>>{};
    for (final topic in simpleTopics(ShowcaseAudience.resident)) {
      await _pump(t, ModuleShowcaseView(
        key: ValueKey(topic), session: pplSession(UserRole.apartmentOwner), audience: ShowcaseAudience.resident,
        simple: true, simpleTopic: topic, menuItems: items, onOpen: (_) {},
        onOpenHelp: () {}, onOpenAllActions: () {}, onCreateGuestPass: () {}, onPay: (_) {},
        fetchMyFinance: () async => const MyFinance(items: [MyFinanceApartment(siteCode: 11, siteName: 'Gül Sitesi', apartmentId: 4, label: 'D:4', blockName: 'A', balanceMinor: 125000)]),
        aboveHero: TextButton(key: const ValueKey('old_announcement_cta'), onPressed: () {}, child: const Text('Read announcement')),
        belowHero: TextButton(key: const ValueKey('invitations_owner'), onPressed: () {}, child: const Text('Invitations')),
        simpleTodayOverview: const SimpleTodayOverview(canReceiveAnnouncements: true, unreadCount: 4),
      ));
      for (final key in ['panel_hero_borc', 'simple_action_guest_pass', 'simple_action_help', 'simple_action_all', 'invitations_owner', 'old_announcement_cta']) {
        if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) (owners[key] ??= []).add(topic);
      }
      if (topic == SimpleTopic.today) {
        expect(find.byType(ListTile), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.text('4 okunmamış duyuru'), findsOneWidget);
      }
    }
    expect(owners, {
      'panel_hero_borc': [SimpleTopic.payments],
      'simple_action_guest_pass': [SimpleTopic.home],
      'simple_action_help': [SimpleTopic.site],
      'simple_action_all': [SimpleTopic.site],
      'invitations_owner': [SimpleTopic.home],
      'old_announcement_cta': [SimpleTopic.site],
    });
  });
  testWidgets('administrator finance/setup/phone actions stay outside read-only Today', (t) async {
    final owners = <String, List<SimpleTopic>>{};
    for (final topic in simpleTopics(ShowcaseAudience.admin)) {
      await _pump(t, ModuleShowcaseView(
        key: ValueKey(topic), session: pplSession(UserRole.siteManager), audience: ShowcaseAudience.admin,
        simple: true, simpleTopic: topic, menuItems: const [SirketMenuItem.finans, SirketMenuItem.siteler, SirketMenuItem.profilim], onOpen: (_) {},
        badgeCounts: const {SirketMenuItem.finans: 2}, managerPhoneMissing: true,
        attentionBar: TextButton(key: const ValueKey('old_combined_attention'), onPressed: () {}, child: const Text('Old attention')),
        simpleFinanceAttention: TextButton(key: const ValueKey('finance_owner'), onPressed: () {}, child: const Text('Bank lines')),
        simpleManagementAttention: TextButton(key: const ValueKey('setup_owner'), onPressed: () {}, child: const Text('Resume setup')),
      ));
      expect(find.byKey(const ValueKey('old_combined_attention')), findsNothing);
      for (final key in ['finance_owner', 'setup_owner', 'panel_telefon_ipucu']) {
        if (find.byKey(ValueKey(key)).evaluate().isNotEmpty) (owners[key] ??= []).add(topic);
      }
      if (topic == SimpleTopic.today) {
        expect(find.byType(ListTile), findsNothing);
        expect(find.byType(TextButton), findsNothing);
        expect(find.textContaining('2 bekleyen'), findsOneWidget);
      }
    }
    expect(owners, {'finance_owner': [SimpleTopic.finance], 'setup_owner': [SimpleTopic.management]});
  });
}
