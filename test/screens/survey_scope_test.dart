import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/survey_models.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/survey_manager_view.dart';
import 'package:site_kapi_kontrol/ui/views/survey_resident_view.dart';

import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart' show pumpList;
import 'survey_fixtures.dart';

const _managerSites = [SurveySite(code: 11, name: 'Gül Sitesi'), SurveySite(code: 12, name: 'Mavi Park')];
const _residentSites = [PeopleSite(code: 11, name: 'Gül Sitesi'), PeopleSite(code: 12, name: 'Mavi Park')];

Future<void> _pump(WidgetTester t, Widget child) async {
  await pumpList(t, child, width: 1100, height: 1600, scale: 1, dark: false);
  await settleFor(t, 100);
  await settleFor(t, 100);
}

void main() {
  testWidgets('yönetici üst siteyi kullanır, yinelenen seçim yok; eski yanıt yeni kapsamı değiştiremez', (t) async {
    final auth = SurveyFakeAuth();
    final service = seededSurvey(auth);
    final key = GlobalKey<SurveyManagerViewState>();
    Widget screen(int scope) => SurveyManagerView(key: key, authService: auth, service: service, sites: _managerSites, scopedSiteCode: scope);
    final late = Completer<void>();
    service.gates['listManaged'] = [late];
    await _pump(t, screen(11));
    await _pump(t, screen(12));
    expect(service.listManagedCalls.last.site, 12);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(svKey('svm_card_4'), findsOneWidget);
    late.complete();
    await settleFor(t, 100);
    expect(svKey('svm_card_4'), findsOneWidget);
    expect(svKey('svm_card_1'), findsNothing);
    await _pump(t, screen(99));
    expect(service.listManagedCalls.map((call) => call.site), [11, 12]);
    expect(svKey('svm_card_4'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('sakin üst siteyi API filtresine geçirir ve geç yanıtı iptal eder', (t) async {
    final auth = SurveyFakeAuth();
    final service = seededSurvey(auth);
    final key = GlobalKey<SurveyResidentViewState>();
    Widget screen(int scope) => SurveyResidentView(key: key, authService: auth, service: service, sites: _residentSites, scopedSiteCode: scope);
    final late = Completer<void>();
    service.gates['listMine'] = [late];
    await _pump(t, screen(11));
    await _pump(t, screen(12));
    expect(service.listMineCalls.last.site, 12);
    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(svKey('survey_card_4'), findsOneWidget);
    late.complete();
    await settleFor(t, 100);
    expect(svKey('survey_card_4'), findsOneWidget);
    expect(svKey('survey_card_1'), findsNothing);
    await _pump(t, screen(99));
    expect(service.listMineCalls.map((call) => call.site), [11, 12]);
    expect(svKey('survey_card_4'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('üst kapsam yokken çoklu site seçimi korunur ve masaüstünde kompakt kalır', (t) async {
    final auth = SurveyFakeAuth();
    final service = seededSurvey(auth);
    await _pump(t, SurveyManagerView(authService: auth, service: service, sites: _managerSites));
    expect(t.getSize(find.byType(DropdownButtonFormField<int>)).width, lessThanOrEqualTo(420));
    expect(service.listManagedCalls.last.site, 11);
    await t.tap(find.byType(DropdownButtonFormField<int>));
    await t.pumpAndSettle();
    await t.tap(find.text('Mavi Park').last);
    await t.pumpAndSettle();
    expect(service.listManagedCalls.last.site, 12);
    expect(svKey('svm_card_4'), findsOneWidget);
    expect(t.takeException(), isNull);
  });
}
