import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/widgets/people_filters.dart';
import 'package:site_kapi_kontrol/ui/widgets/people_section_navigation.dart';

import 'list_fixtures.dart';
import 'people_fixtures.dart';
import '../support/people_nav.dart';

Future<void> _ready(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _pump(
  WidgetTester tester,
  Widget view, {
  double width = 400,
  double height = 1600,
  double scale = 1,
  bool dark = false,
}) => pumpList(
  tester,
  view,
  width: width,
  height: height,
  scale: scale,
  dark: dark,
);

void main() {
  testWidgets(
    'ana gezinme yalnız Daireler ve Kadro; araçlar İşlemler üzerinden korunur',
    (tester) async {
      await _pump(
        tester,
        PeopleView(authService: PeopleFakeAuth.seeded()),
        width: 1400,
        height: 1400,
      );
      await _ready(tester);
      expect(find.byType(PeopleSectionNavigation), findsOneWidget);
      expect(find.byKey(const ValueKey('people_tab_0')), findsNothing);
      expect(find.byKey(const ValueKey('people_tab_1')), findsOneWidget);
      expect(find.byKey(const ValueKey('people_tab_3')), findsOneWidget);
      expect(find.byKey(const ValueKey('people_tab_2')), findsNothing);
      expect(
        find.byKey(const ValueKey('people_safety_requests')),
        findsNothing,
      );
      await selectPeopleSection(tester, 2);
      expect(selectedPeopleSection(tester), 2);
      expect(find.byKey(const ValueKey('vehicles_search')), findsOneWidget);
      await selectPeopleSection(tester, 0);
      expect(find.byKey(const ValueKey('people_search')), findsOneWidget);
    },
  );

  testWidgets(
    'Kadro ikincil güvenlik talepleri yalnız yazabilen yöneticiye açık',
    (tester) async {
      await _pump(
        tester,
        PeopleView(authService: PeopleFakeAuth.seeded()),
        height: 1600,
      );
      await _ready(tester);
      await selectPeopleSection(tester, 3);
      final more = find.byKey(const ValueKey('people_more_actions'));
      await tester.ensureVisible(more);
      await tester.tap(more);
      await _ready(tester);
      expect(
        find.byKey(const ValueKey('people_safety_requests')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('people_tab_2')));
      await _ready(tester);
      expect(selectedPeopleSection(tester), 2);

      await _pump(
        tester,
        PeopleView(
          key: const ValueKey('board_people'),
          authService: PeopleFakeAuth.seeded(),
          manageSites: false,
          readOnlySites: const [PeopleSite(code: 11, name: 'Site')],
          initialTab: 3,
        ),
        height: 1600,
      );
      await _ready(tester);
      await tester.tap(find.byKey(const ValueKey('people_more_actions')));
      await _ready(tester);
      expect(
        find.byKey(const ValueKey('people_safety_requests')),
        findsNothing,
      );
    },
  );

  testWidgets('genişte kişi arama ilişki ve durum aynı satırdadır', (
    tester,
  ) async {
    await _pump(
      tester,
      PeopleView(authService: PeopleFakeAuth.seeded()),
      width: 1400,
      height: 1400,
    );
    await _ready(tester);
    final search = tester.getTopLeft(
      find.byKey(const ValueKey('people_search')),
    );
    final relation = tester.getTopLeft(
      find.byKey(const ValueKey('people_relation_')),
    );
    final status = tester.getTopLeft(
      find.byKey(const ValueKey('people_status_active')),
    );
    expect(search.dy, relation.dy);
    expect(search.dy, status.dy);
    expect(search.dx, lessThan(relation.dx));
    expect(relation.dx, lessThan(status.dx));
    expect(find.byType(PeopleFilters), findsOneWidget);
  });

  for (final size in [
    const Size(320, 640),
    const Size(640, 320),
    const Size(1400, 800),
  ]) {
    for (final dark in [false, true]) {
      testWidgets(
        'sade kişi kontrolleri $size x2 ${dark ? 'koyu' : 'açık'} taşmaz',
        (tester) async {
          await _pump(
            tester,
            PeopleView(authService: PeopleFakeAuth.seeded()),
            width: size.width,
            height: size.height,
            scale: 2,
            dark: dark,
          );
          await _ready(tester);
          expect(tester.takeException(), isNull);
          await selectPeopleSection(tester, 1);
          expect(tester.takeException(), isNull);
          await selectPeopleSection(tester, 3);
          expect(tester.takeException(), isNull);
          await selectPeopleSection(tester, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
