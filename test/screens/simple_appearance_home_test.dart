import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/interface_mode_service.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/services/view_mode_service.dart';
import 'package:site_kapi_kontrol/ui/design/view_mode_toggle.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/module_showcase_view.dart';
import 'package:site_kapi_kontrol/ui/views/individual_home_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_task_surface.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';
import 'package:site_kapi_kontrol/ui/widgets/manager_call_tile.dart';

import '../support/menu_nav.dart';
import 'emergency_view_test.dart' show loadAlarmReviewFont, alarmReviewTheme;
import 'people_fixtures.dart';
import 'voice_fake.dart';

class _SimpleVoice extends FakeVoiceDoorService {
  @override
  void updateCandidateDoors(List<DoorRecord>? doors) {}
}

class SimpleHomeAuth extends PeopleFakeAuth {
  SimpleHomeAuth({required super.role});
  @override
  Future<void> refreshSession({bool force = false}) async {}
  @override
  Future<MySiteApplications> getMySiteApplications() async => const MySiteApplications();
  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async => (<DoorRecord>[], null);
  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;
  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async => (<JoinRequestRecord>[], null);
  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async => [];
  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async => (<MyApartmentRecord>[], null);
  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({required int doorId}) async => (null, null);
  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;
  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;
  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

Future<void> simpleSettle(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 650));
}

ThemeData simpleReviewTheme(bool dark) {
  final base = alarmReviewTheme(dark);
  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(titleTextStyle: base.appBarTheme.titleTextStyle?.copyWith(fontFamily: 'ReviewRoboto')),
    listTileTheme: base.listTileTheme.copyWith(
      titleTextStyle: base.listTileTheme.titleTextStyle?.copyWith(fontFamily: 'ReviewRoboto'),
      subtitleTextStyle: base.listTileTheme.subtitleTextStyle?.copyWith(fontFamily: 'ReviewRoboto'),
    ),
  );
}

Future<void> loadSimpleReviewFonts() async {
  await loadAlarmReviewFont();
  for (final weight in ['Thin', 'Light', 'Regular', 'Bold', 'Fill']) {
    await (FontLoader('packages/phosphor_glyphs/Phosphor-$weight')..addFont(rootBundle.load('packages/phosphor_glyphs/fonts/Phosphor-$weight.ttf'))).load();
  }
}

final _layoutMeasurements = <String, Object>{};
Future<void> _capture(WidgetTester t, Key key, String name) async {
  const directory = String.fromEnvironment('SIMPLE_REVIEW_DIR', defaultValue: 'work/sade-redesign-2026-11-10');
  final entries = find.byType(SimpleTaskSurface).evaluate().expand((e) => (e.widget as SimpleTaskSurface).entries).toList();
  final rects = entries.map((e) => t.getRect(find.byKey(ValueKey(e.id)))).toList();
  final viewport = t.view.physicalSize / t.view.devicePixelRatio;
  _layoutMeasurements[name] = {
    'viewport': {'width': viewport.width, 'height': viewport.height},
    'actionCount': rects.length,
    'fullyVisibleActions': rects.where((r) => r.top >= 0 && r.bottom <= viewport.height && r.left >= 0 && r.right <= viewport.width).length,
    'actionRegionHeight': rects.isEmpty ? 0 : rects.map((r) => r.bottom).reduce((a,b) => a > b ? a : b) - rects.map((r) => r.top).reduce((a,b) => a < b ? a : b),
  };
  await t.runAsync(() async {
    await Directory(directory).create(recursive: true);
    final image = await t.renderObject<RenderRepaintBoundary>(find.byKey(key)).toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('$directory/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    await File('$directory/layout-metrics.json').writeAsString(const JsonEncoder.withIndent('  ').convert(_layoutMeasurements));
    image.dispose();
  });
}

void main() {
  setUpAll(loadSimpleReviewFonts);
  for (final (width, height, scale) in <(double, double, double)>[(320, 640, 2), (390, 844, 1), (1100, 850, 1), (1366, 768, 1)]) {
    for (final dark in [false, true]) {
      for (final role in [UserRole.apartmentOwner, UserRole.siteManager]) {
        testWidgets('actual Home classic/simple return ${role.name} ${width.toInt()} ${dark ? 'dark' : 'light'}', (t) async {
          SharedPreferences.setMockInitialValues({});
          final auth = SimpleHomeAuth(role: role);
          final viewModes = ViewModeService();
          await viewModes.load();
          addTearDown(viewModes.dispose);
          final notifier = AnnouncementNotifier(fetchSummary: () async => throw StateError('quiet'), fetchInbox: () async => throw StateError('quiet'), fetchAnnouncement: (_) async => throw StateError('quiet'), isEligible: () => false);
          final access = ModuleAccess(fetch: () async => MyModulesResult(sites: [MySiteModules(siteCode: 11, siteName: 'Gül Sitesi', role: role == UserRole.siteManager ? 'manager' : 'resident', doorAccess: false, modules: {'door_control': false, 'finance': true, 'announcements': true, 'drive_storage': true, 'work_tracking': true, 'survey': true, 'equipment': true, 'reservation': true, 'neighbor_board': true, 'directory': true})]), isSuperUser: () => false);
          await access.refresh();
          addTearDown(access.dispose);
          addTearDown(notifier.dispose);
          final voice = _SimpleVoice();
          addTearDown(voice.dispose);
          const boundaryKey = ValueKey('simple_actual_home_review');
          t.view.physicalSize = Size(width, height);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(ViewModeScope(service: viewModes, child: MaterialApp(
            theme: simpleReviewTheme(dark),
            builder: (context, child) => RepaintBoundary(key: boundaryKey, child: ColoredBox(color: simpleReviewTheme(dark).scaffoldBackgroundColor, child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)), child: child!))),
            home: HomePage(authService: auth, moduleAccess: access, announcementNotifier: notifier, voiceDoorService: voice),
          )));
          await simpleSettle(t);
          expect(find.byType(SimpleTopicBar), findsNothing);
          final classicMenu = t.widget<ModuleShowcaseView>(find.byType(ModuleShowcaseView)).menuItems.toSet();
          final name = 'simple-${role.name}-${width.toInt()}-${dark ? 'dark' : 'light'}';
          await openSettingsPanel(t);
          await t.ensureVisible(find.byKey(const ValueKey('interface_mode_simple')));
          await t.tap(find.byKey(const ValueKey('interface_mode_simple')));
          await simpleSettle(t);
          await t.ensureVisible(find.text('Görünüm'));
          await t.pump();
          await _capture(t, boundaryKey, '$name-settings');
          await closeMenuPanels(t);
          expect(find.byType(SimpleTopicBar), findsOneWidget);
          expect(find.byType(SimpleModuleList), findsOneWidget);
          expect(t.widget<ModuleShowcaseView>(find.byType(ModuleShowcaseView)).menuItems.toSet(), classicMenu);
          expect(find.byKey(const ValueKey('panel_vitrin_izgara')), findsNothing);
          expect(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).items.contains(SirketMenuItem.kapilar), classicMenu.contains(SirketMenuItem.kapilar), reason: 'existing door availability is preserved exactly');
          expect(t.takeException(), isNull);
          expect(find.byType(IndividualHomeView), findsNothing, reason: 'Today must not append the old personal setup/catalogue');
          final todayGroups = simpleGroups(visibleItems: classicMenu.toList(), audience: t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).audience, topic: SimpleTopic.today);
          expect(todayGroups, isEmpty, reason: 'Today has no repeated module/action entry');
          expect(find.byType(ManagerPhoneHint), findsNothing);
          await _capture(t, boundaryKey, '$name-today');
          for (final topic in simpleTopics(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).audience).where((value) => value != SimpleTopic.today)) {
            final chip = find.byKey(ValueKey('simple_topic_${topic.name}'));
            await t.ensureVisible(chip);
            await t.tap(chip);
            await simpleSettle(t);
            await _capture(t, boundaryKey, '$name-topic-${topic.name}');
            expect(t.takeException(), isNull);
          }
          if (role == UserRole.apartmentOwner && width == 1100 && !dark) {
            final homeTopic = find.byKey(const ValueKey('simple_topic_home'));
            await t.ensureVisible(homeTopic);
            await t.tap(homeTopic);
            await simpleSettle(t);
            await _capture(t, boundaryKey, '$name-home-list');
            final homeTiles = find.byTooltip('Kutucuk görünümüne geç');
            await t.ensureVisible(homeTiles);
            await t.tap(homeTiles);
            await simpleSettle(t);
            await _capture(t, boundaryKey, '$name-home-tiles');
            final homeList = find.byTooltip('Liste görünümüne geç');
            await t.ensureVisible(homeList);
            await t.tap(homeList);
            await simpleSettle(t);
          }
          final target = find.byKey(ValueKey('simple_topic_${role == UserRole.siteManager ? 'management' : 'site'}'));
          await t.ensureVisible(target);
          await t.tap(target);
          await simpleSettle(t);
          final list = t.widget<SimpleModuleList>(find.byType(SimpleModuleList));
          expect(list.topic, role == UserRole.siteManager ? SimpleTopic.management : SimpleTopic.site);
          expect(list.items.toSet(), classicMenu);
          if (role == UserRole.siteManager) {
            expect(find.byType(ManagerPhoneHint), findsNothing);
            final phone = find.byKey(const ValueKey('header_add_manager_phone'));
            expect(phone, findsOneWidget);
            await t.tap(phone);
            await simpleSettle(t);
            expect(find.byType(ModuleShowcaseView), findsNothing);
            await t.ensureVisible(target);
            await t.tap(target);
            await simpleSettle(t);
          }
          if (role == UserRole.apartmentOwner) expect(find.byType(IndividualHomeView), findsNothing, reason: 'Site does not duplicate personal setup');
          await _capture(t, boundaryKey, name);
          final topicBarBeforeTiles = t.getRect(find.byType(SimpleTopicBar));
          final toTiles = find.byTooltip('Kutucuk görünümüne geç');
          await t.ensureVisible(toTiles);
          await t.tap(toTiles);
          await simpleSettle(t);
          expect(viewModes.modeOf(ViewScreen.simpleModules), ListViewMode.tiles);
          expect(viewModes.modeOf(ViewScreen.modules), ListViewMode.tiles, reason: 'Classic preference remains untouched');
          final restored = ViewModeService();
          await restored.load();
          expect(restored.modeOf(ViewScreen.simpleModules), ListViewMode.tiles);
          restored.dispose();
          if (width > 900) {
            expect(t.getRect(find.byType(SimpleTopicBar)).top, topicBarBeforeTiles.top, reason: 'desktop topic bar remains fixed while list changes to tiles');
            expect(find.byType(SimpleTopicBar).hitTestable(), findsOneWidget);
          }
          await _capture(t, boundaryKey, '$name-tiles');
          await openMenuDrawer(t);
          await t.binding.handlePopRoute();
          await simpleSettle(t);
          expect(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).topic, list.topic, reason: 'Back closes the drawer before changing the topic');
          await t.binding.handlePopRoute();
          await simpleSettle(t);
          expect(find.byType(HomePage), findsOneWidget, reason: 'Back from a topic does not exit the application');
          expect(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).topic, SimpleTopic.today);
          await t.ensureVisible(target);
          await t.tap(target);
          await simpleSettle(t);
          await tapMenuEntry(t, YanMenu.titleFor(SirketMenuItem.dashboard, role));
          await simpleSettle(t);
          expect(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).topic, SimpleTopic.today, reason: 'explicit Panel/Home command means Today');
          await t.ensureVisible(target);
          await t.tap(target);
          await simpleSettle(t);
          final profile = find.byKey(const ValueKey('simple_route_profilim'));
          await t.ensureVisible(profile);
          await t.tap(profile);
          await simpleSettle(t);
          expect(find.byType(ModuleShowcaseView), findsNothing, reason: 'row delegates to the actual existing profile dispatcher');
          final today = find.byKey(const ValueKey('simple_topic_today'));
          await t.ensureVisible(today);
          await t.tap(today);
          await simpleSettle(t);
          expect(find.byType(ModuleShowcaseView), findsOneWidget);
          expect(t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).topic, SimpleTopic.today);
          await openSettingsPanel(t);
          await t.ensureVisible(find.byKey(const ValueKey('interface_mode_classic')));
          await t.tap(find.byKey(const ValueKey('interface_mode_classic')));
          await simpleSettle(t);
          await closeMenuPanels(t);
          expect(find.byType(SimpleTopicBar), findsNothing);
          expect(find.byType(SimpleModuleList), findsNothing);
          expect((await SharedPreferences.getInstance()).getString(DeviceInterfaceModeStore.key(auth.session!.id)), 'classic');
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump();
        });
      }
    }
  }
}
