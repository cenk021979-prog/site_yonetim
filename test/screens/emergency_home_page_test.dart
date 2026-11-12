// Acil durum: ana kabuk (HomePage) entegrasyonu. Menü öğesi MODÜL DEĞİL çekirdek özelliktir: süper kullanıcı dışında herkeste ve modül verisi
// hiç gelmese bile (acil durumda ağ ya da modül durumuna bağlı olmasın) "Ana sayfa" başlığı altında görünür; seçilince Acil durum ekranı açılır.
// Çekmecedeki site seçimi ekrana taşınır; bakım firması düzenleme yetkisi yalnız yönetici modundaki yöneticidedir.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/apartment_member_record.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/door_runtime_status.dart';
import 'package:site_kapi_kontrol/models/join_request_record.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/site_manager_record.dart';
import 'package:site_kapi_kontrol/models/site_application.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/views/emergency_view.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import '../emergency_alarm_controller_test.dart'
    show FakeAlarmAudio, FakeAlarmFeedService;

import '../support/menu_nav.dart';
import 'dialog_layout_harness.dart' show settleFor;
import 'people_fixtures.dart';
import 'emergency_view_test.dart'
    show boundaryKey, renderProof, loadAlarmReviewFont, alarmReviewTheme;

class _HomeAuth extends PeopleFakeAuth {
  _HomeAuth({super.role});

  @override
  Future<void> refreshSession({bool force = false}) async {}

  @override
  Future<MySiteApplications> getMySiteApplications() async =>
      const MySiteApplications();

  List<DoorRecord> doors = <DoorRecord>[];

  @override
  Future<(List<DoorRecord>?, String?)> listMyDoors() async =>
      (List<DoorRecord>.of(doors), null);

  @override
  Future<SiteManagersData?> getSiteManagers(int siteCode) async => null;

  @override
  Future<(List<JoinRequestRecord>?, String?)> getMyJoinRequests() async =>
      (<JoinRequestRecord>[], null);

  @override
  Future<List<Map<String, dynamic>>> getMyClaimedDevices() async =>
      <Map<String, dynamic>>[];

  @override
  Future<(List<MyApartmentRecord>?, String?)> getMyApartments() async =>
      (<MyApartmentRecord>[], null);

  @override
  Future<(DoorRuntimeStatus?, String?)> getDoorRuntimeStatus({
    required int doorId,
  }) async => (null, null);

  @override
  Future<bool> isPhoneConnectedToLocalWifi() async => false;

  @override
  Future<bool> isDeviceReachableOnLocalWifi(String deviceUid) async => false;

  @override
  void selectWidgetDoor(DoorRecord door, {bool? isOnline}) {}
}

MySiteModules _my(String role, {int code = 11, String name = 'Gül Sitesi'}) =>
    MySiteModules(
      siteCode: code,
      siteName: name,
      role: role,
      modules: const <String, bool>{'door_control': true},
      doorAccess: !(role == 'staff' || role == 'board_member'),
    );

Future<ModuleAccess> _access(
  List<MySiteModules> Function() sites, {
  bool superUser = false,
}) async {
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(sites: sites()),
    isSuperUser: () => superUser,
  );
  await access.refresh();
  addTearDown(access.dispose);
  return access;
}

AnnouncementNotifier _quietNotifier() => AnnouncementNotifier(
  fetchSummary: () async => throw StateError('yok'),
  fetchInbox: () async => throw StateError('yok'),
  fetchAnnouncement: (id) async => throw StateError('yok'),
  isEligible: () => false,
);

Future<void> _pumpHome(
  WidgetTester t,
  _HomeAuth auth, {
  ModuleAccess? access,
  EmergencyAlarmController? alarmController,
  List<EmergencySite>? alarmSites,
  Size size = const Size(400, 900),
  double scale = 1,
  bool dark = false,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final notifier = _quietNotifier();
  addTearDown(notifier.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: alarmReviewTheme(false),
      darkTheme: alarmReviewTheme(true),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: RepaintBoundary(
        key: boundaryKey,
        child: HomePage(
          authService: auth,
          moduleAccess: access,
          announcementNotifier: notifier,
          emergencyAlarmController: alarmController,
          loadEmergencySites: alarmSites == null
              ? null
              : () async => alarmSites,
        ),
      ),
    ),
  );
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

Future<void> _disposeHome(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

Finder _tile(String title) =>
    find.descendant(of: find.byType(Drawer), matching: find.text(title));

void main() {
  setUpAll(loadAlarmReviewFont);
  for (final dark in [false, true]) {
    for (final size in [
      const Size(320, 640),
      const Size(800, 320),
      const Size(1366, 768),
    ]) {
      testWidgets('kompakt başlık: $size ${dark ? 'koyu' : 'açık'}', (t) async {
        final auth = _HomeAuth(role: UserRole.individual);
        final access = await _access(() => []);
        final service = FakeAlarmFeedService()
          ..feed = const EmergencyAlarmFeed(canReceive: true, canSound: true);
        final controller = EmergencyAlarmController(
          authService: auth,
          service: service,
          audio: FakeAlarmAudio(),
          soundInitiallyEnabled: false,
        );
        await _pumpHome(
          t,
          auth,
          access: access,
          alarmController: controller,
          size: size,
          scale: 2,
          dark: dark,
        );
        expect(t.getSize(find.byType(AppBar)).height, kToolbarHeight);
        expect(
          find.byKey(const ValueKey('emergency_active_banner')),
          findsNothing,
        );
        expect(find.text('Bu cihazda sessize al'), findsNothing);
        expect(find.textContaining('sına'), findsNothing);
        for (final key in [
          'temporary_feedback_open',
          'emergency_alarm_inbox',
        ]) {
          final button = find.byKey(ValueKey(key));
          expect(
            find.descendant(of: find.byType(AppBar), matching: button),
            findsOneWidget,
          );
          expect(t.getSize(button).width, greaterThanOrEqualTo(48));
        }
        expect(t.takeException(), isNull);
        await renderProof(
          t,
          'kompakt-baslik-${size.width.toInt()}-${dark ? 'koyu' : 'acik'}',
        );
        if (size.width != 800) {
          await _pumpHome(
            t,
            auth,
            access: access,
            alarmController: controller,
            size: size,
            dark: dark,
          );
          await renderProof(
            t,
            'kompakt-onizleme-${size.width.toInt()}-${dark ? 'koyu' : 'acik'}',
          );
        }
        await _disposeHome(t);
        controller.dispose();
        await t.pump();
      });
    }
  }
  testWidgets('sakin Acil ekranını görür, yönetici modunda başlatma yok', (
    t,
  ) async {
    final resident = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(() => [_my('resident')]);
    await _pumpHome(t, resident, access: access);
    await openMenuDrawer(t);
    expect(_tile('Acil durum'), findsOneWidget);
    await tapMenuEntry(t, 'Acil durum');
    await settleFor(t);
    expect(find.byType(EmergencyView), findsOneWidget);
    expect(find.text('112 Acil Çağrı Merkezi'), findsNothing);
    await _disposeHome(t);
    final manager = _HomeAuth();
    final managerAccess = await _access(() => [_my('manager')]);
    await _pumpHome(
      t,
      manager,
      access: managerAccess,
      alarmSites: const [
        EmergencySite(siteCode: 11, siteName: 'Gül', canCreate: true),
      ],
    );
    await openMenuDrawer(t);
    expect(_tile('Acil durum'), findsNothing);
    await t.tap(find.text('Sakin Moduna Geç'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 600));
    await openMenuDrawer(t);
    expect(_tile('Acil durum'), findsOneWidget);
    await tapMenuEntry(t, 'Acil durum');
    await settleFor(t);
    expect(
      t.widget<EmergencyView>(find.byType(EmergencyView)).allowEdit,
      isFalse,
    );
    await _disposeHome(t);
  });
  testWidgets('yalnız görevli Acil başlatma menüsü görmez', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(
      () => [
        const MySiteModules(
          siteCode: 11,
          siteName: 'Gül',
          role: 'staff',
          doorAccess: true,
        ),
      ],
    );
    await _pumpHome(t, auth, access: access);
    await openMenuDrawer(t);
    expect(_tile('Acil durum'), findsNothing);
    await _disposeHome(t);
  });
  testWidgets(
    'site üyesi olmayan servis hesabı Home içinde alarm alır; geri bildirim korunur',
    (t) async {
      final auth = _HomeAuth(role: UserRole.individual);
      final access = await _access(() => []);
      final service = FakeAlarmFeedService()
        ..feed = const EmergencyAlarmFeed(
          canReceive: true,
          canSound: true,
          alarms: [
            EmergencyAlarm(
              id: 9,
              siteCode: 11,
              siteName: 'Gül Sitesi',
              kind: 'elevator',
              equipmentName: 'A Blok',
              soundEnabled: true,
            ),
          ],
        );
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: audio,
        soundInitiallyEnabled: false,
      );
      await _pumpHome(t, auth, access: access, alarmController: controller);
      expect(
        find.byKey(const ValueKey('emergency_active_banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('emergency_alarm_inbox')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('temporary_feedback_open')),
        findsOneWidget,
      );
      expect(audio.starts, 0);
      expect(service.played, 0);
      await t.ensureVisible(
        find.byKey(const ValueKey('emergency_alarm_inbox')),
      );
      await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
      await t.pump();
      expect(audio.starts, 1);
      expect(service.played, 1);
      await _disposeHome(t);
      controller.dispose();
      await t.pump();
    },
  );
  testWidgets('süper kullanıcı Acil başlatamaz', (t) async {
    final auth = _HomeAuth(role: UserRole.superUser);
    final access = await _access(() => [], superUser: true);
    await _pumpHome(t, auth, access: access);
    await openMenuDrawer(t);
    expect(_tile('Acil durum'), findsNothing);
    await _disposeHome(t);
  });
  testWidgets('sakin vitrini yeni alarm akışına gider', (t) async {
    final auth = _HomeAuth(role: UserRole.apartmentOwner);
    final access = await _access(() => [_my('resident')]);
    await _pumpHome(t, auth, access: access);
    final card = find.text('Asansör ve yangın için site ekibine alarm');
    await t.ensureVisible(card);
    await t.tap(card);
    await settleFor(t);
    expect(find.byType(EmergencyView), findsOneWidget);
    await _disposeHome(t);
  });
}
