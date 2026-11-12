import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/ui/helpers/module_showcase.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

void main() {
  for (final audience in ShowcaseAudience.values) {
    test('every enum has a permanent topic without granting access: ${audience.name}', () {
      expect(SirketMenuItem.values, hasLength(49));
      for (final item in SirketMenuItem.values) {
        expect(simpleTopics(audience), contains(simpleTopicFor(item, audience)), reason: item.name);
        expect(simpleGroupFor(item), isNotEmpty);
      }
    });
  }
  for (final role in UserRole.values) {
    for (final resident in [false, true]) {
      test('visible set conserved across topic union: ${role.name} resident=$resident', () {
        final visible = YanMenu.visibleItems(role: role, isResidentMode: resident, canToggleMode: true,
          additionalItems: {SirketMenuItem.finans, SirketMenuItem.belgeler, SirketMenuItem.plakaTanima},
          hiddenItems: {SirketMenuItem.finans},
        );
        final audience = showcaseAudience(role: role, isResidentMode: resident, canToggleMode: true);
        final expected = visible.toSet()..remove(SirketMenuItem.dashboard);
        if (audience != ShowcaseAudience.admin) expected.remove(SirketMenuItem.yeniSite);
        final grouped = <SirketMenuItem>[];
        for (final topic in simpleTopics(audience).where((t) => t != SimpleTopic.today)) {
          grouped.addAll(simpleGroups(visibleItems: visible, audience: audience, topic: topic).values.expand((items) => items));
        }
        expect(grouped.toSet(), expected);
        expect(grouped.length, expected.length, reason: 'each available item has exactly one permanent topic');
        expect(grouped, isNot(contains(SirketMenuItem.finans)));
        expect(grouped, isNot(contains(SirketMenuItem.odemeKamera)), reason: 'merged alias never reappears');
      });
    }
  }
  test('empty/restricted site menus never synthesize finance or doors', () {
    final groups = simpleGroups(visibleItems: [SirketMenuItem.dashboard, SirketMenuItem.profilim], audience: ShowcaseAudience.resident, topic: SimpleTopic.today);
    expect(groups, isEmpty, reason: 'Today never repeats the profile/module catalogue');
    expect(simpleGroups(visibleItems: [SirketMenuItem.profilim], audience: ShowcaseAudience.resident, topic: SimpleTopic.site).values.expand((items) => items), [SirketMenuItem.profilim]);
  });
  test('all four topics form an exact partition; Today has no module route', () {
    final available = SirketMenuItem.values.where((item) => item != SirketMenuItem.dashboard).toList();
    final today = simpleGroups(visibleItems: available, audience: ShowcaseAudience.admin, topic: SimpleTopic.today, featuredItems: available.toSet());
    expect(today, isEmpty);
    final permanent = [for (final topic in simpleTopics(ShowcaseAudience.admin).where((t) => t != SimpleTopic.today)) ...simpleGroups(visibleItems: available, audience: ShowcaseAudience.admin, topic: topic).values.expand((items) => items)];
    expect(permanent.toSet(), available.toSet());
  });
}
