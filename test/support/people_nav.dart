import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/ui/widgets/people_section_navigation.dart';

int selectedPeopleSection(WidgetTester tester) => tester
    .widget<PeopleSectionNavigation>(find.byType(PeopleSectionNavigation))
    .selected;

/// Aynı veri görünümüne kullanıcıya sunulan yeni yoldan ulaşır. Araçlar ana
/// gezinmede tekrarlanmaz; ikincil İşlemler menüsündedir.
Future<void> selectPeopleSection(WidgetTester tester, int index) async {
  if (selectedPeopleSection(tester) == index) return;
  if (index == 2) {
    final more = find.byKey(const ValueKey('people_more_actions'));
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
  final target = find.byKey(ValueKey('people_tab_$index'));
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}
