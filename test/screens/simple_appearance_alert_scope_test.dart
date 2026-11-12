import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/announcement.dart';
import 'package:site_kapi_kontrol/models/door_record.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/models/finance.dart';
import 'package:site_kapi_kontrol/models/platform_module.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/announcement_notifier.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/services/interface_mode_service.dart';
import 'package:site_kapi_kontrol/services/module_access.dart';
import 'package:site_kapi_kontrol/ui/helpers/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/pages/home_page.dart';
import 'package:site_kapi_kontrol/ui/widgets/announcement_parts.dart';
import 'package:site_kapi_kontrol/ui/widgets/context_strip.dart';
import 'package:site_kapi_kontrol/ui/widgets/emergency_alarm_host.dart';
import 'package:site_kapi_kontrol/ui/widgets/simple_navigation.dart';
import 'package:site_kapi_kontrol/ui/widgets/yan_menu.dart';

import '../emergency_alarm_controller_test.dart'
    show FakeAlarmAudio, FakeAlarmFeedService;
import '../support/menu_nav.dart';
import 'emergency_view_test.dart' show alarmReviewTheme, loadAlarmReviewFont;
import 'simple_appearance_home_test.dart' show SimpleHomeAuth, simpleSettle;
import 'voice_fake.dart';

class _AlertAuth extends SimpleHomeAuth {
  _AlertAuth() : super(role: UserRole.apartmentOwner);
  @override
  Future<MyFinance> getMyFinance() async => const MyFinance();
  @override
  Future<List<PendingInvitation>> listMyInvitations() async => const [];
}

class _QuietCandidatesVoice extends FakeVoiceDoorService {
  @override
  void updateCandidateDoors(List<DoorRecord>? doors) {}
}

const _urgent = ResidentAnnouncement(
  id: 77,
  siteCode: 11,
  siteName: 'Gül Sitesi Uzun Ortak Yaşam Alanı',
  title:
      'Önemli duyuru: ana girişte süren bakım için alternatif geçişi kullanın',
  importance: AnnouncementImportance.urgent,
  body: 'Sanal test duyurusu. Başka site veya hesaba taşınmamalıdır.',
);
const _alarm = EmergencyAlarm(
  id: 901,
  siteCode: 22,
  kind: 'elevator',
  siteName: 'İkinci Site Uzun Yerleşke İsmi',
  equipmentName: 'B Blok Batı Giriş Asansörü',
  location: 'B Blok bodrum ortak alanı',
  createdByName: 'SANAL test sakini',
  soundEnabled: true,
);
const _liveFeed = EmergencyAlarmFeed(
  canReceive: true,
  canSound: true,
  alarms: [_alarm],
);

class _Harness {
  _Harness(
    this.auth,
    this.access,
    this.notifier,
    this.service,
    this.audio,
    this.controller,
    this.voice,
  );
  final _AlertAuth auth;
  final ModuleAccess access;
  final AnnouncementNotifier notifier;
  final FakeAlarmFeedService service;
  final FakeAlarmAudio audio;
  final EmergencyAlarmController controller;
  final _QuietCandidatesVoice voice;
  bool _disposed = false;
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.dispose();
    service.close();
    notifier.dispose();
    access.dispose();
    voice.dispose();
  }
}

Future<_Harness> _pumpAlerts(
  WidgetTester t, {
  required Size size,
  required bool dark,
}) async {
  final auth = _AlertAuth();
  SharedPreferences.setMockInitialValues({
    DeviceInterfaceModeStore.key(auth.session!.id): 'simple',
  });
  final access = ModuleAccess(
    fetch: () async => MyModulesResult(
      sites: [
        for (final (id, name) in [
          (11, 'Gül Sitesi Uzun Ortak Yaşam Alanı'),
          (22, 'İkinci Site Uzun Yerleşke İsmi'),
        ])
          MySiteModules(
            siteCode: id,
            siteName: name,
            role: 'resident',
            doorAccess: false,
            modules: {
              'door_control': false,
              'announcements': true,
              'finance': false,
              'neighbor_board': true,
              'directory': true,
              'work_tracking': true,
            },
          ),
      ],
    ),
    isSuperUser: () => false,
  );
  final notifier = AnnouncementNotifier(
    fetchSummary: () async => const NotificationSummary(
      unreadAnnouncements: 1,
      unreadUrgent: 1,
      latestAnnouncementId: 77,
    ),
    fetchInbox: () async => const ResidentAnnouncementPage(items: [_urgent]),
    fetchAnnouncement: (_) async => _urgent,
    isEligible: () => true,
  );
  final service = FakeAlarmFeedService()..feed = _liveFeed;
  final audio = FakeAlarmAudio();
  final controller = EmergencyAlarmController(
    authService: auth,
    service: service,
    audio: audio,
    soundInitiallyEnabled: true,
    pollInterval: const Duration(hours: 1),
  );
  final voice = _QuietCandidatesVoice();
  final harness = _Harness(
    auth,
    access,
    notifier,
    service,
    audio,
    controller,
    voice,
  );
  addTearDown(harness.dispose);
  await access.refresh();
  await notifier.refresh();
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: alarmReviewTheme(dark),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(2)),
        child: child!,
      ),
      home: HomePage(
        authService: auth,
        moduleAccess: access,
        announcementNotifier: notifier,
        emergencyAlarmController: controller,
        voiceDoorService: voice,
        loadEmergencySites: () async => const [
          EmergencySite(siteCode: 11, siteName: 'Gül Sitesi', canCreate: true),
          EmergencySite(siteCode: 22, siteName: 'İkinci Site', canCreate: true),
        ],
        loadContextApartments: () async => const [
          ContextApartment(siteCode: 11, label: 'A Blok / 101'),
          ContextApartment(siteCode: 22, label: 'B Blok / 202'),
        ],
      ),
    ),
  );
  await simpleSettle(t);
  return harness;
}

Future<void> _unmount(WidgetTester t, _Harness harness) async {
  await t.pumpWidget(const SizedBox.shrink());
  harness.dispose();
  await t.pump();
}

void main() {
  setUpAll(loadAlarmReviewFont);
  for (final size in [const Size(320, 640), const Size(640, 360)]) {
    for (final dark in [false, true]) {
      testWidgets(
        'Sade urgent/alarm/two-site scope survives ${size.width.toInt()}x${size.height.toInt()} text2 ${dark ? 'dark' : 'light'}',
        (t) async {
          final h = await _pumpAlerts(t, size: size, dark: dark);
          expect(find.byType(SimpleTopicBar), findsOneWidget);
          expect(find.byType(EmergencyAlarmHost), findsOneWidget);
          expect(find.byType(UrgentAnnouncementBanner), findsOneWidget);
          expect(h.notifier.urgentAnnouncement?.id, 77);
          expect(h.notifier.urgentAnnouncement?.siteCode, 11);
          expect(h.controller.alarms.single.siteCode, 22);
          final contextHost = t.widget<ContextStripHost>(
            find.byType(ContextStripHost),
          );
          expect(contextHost.sites.map((s) => s.code), [11, 22]);
          if (size.height >= 480) {
            final context = t.widget<ContextStrip>(find.byType(ContextStrip));
            expect(context.data.siteLabel, contains('+1 site'));
            expect(context.data.apartmentLabel, '2 daire');
            expect(context.data.roleLabel, 'Sakin');
          } else {
            // Existing short-window policy hides the fixed strip. The same
            // real site context must still be available from the real drawer.
            expect(find.byType(ContextStrip), findsNothing);
            await openMenuDrawer(t);
            final drawer = t.widget<YanMenu>(find.byType(YanMenu));
            expect(drawer.siteContext!.sites.map((s) => s.code), [11, 22]);
            expect(drawer.siteContext!.label, contains('+1 site'));
            expect(
              find.text(drawer.siteContext!.label).hitTestable(),
              findsOneWidget,
            );
            expect(t.takeException(), isNull);
            await closeMenuPanels(t);
          }
          expect(
            find.byKey(const ValueKey('emergency_alarm_inbox')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('emergency_active_banner')).hitTestable(),
            findsOneWidget,
          );
          expect(
            find
                .byKey(const ValueKey('urgent_announcement_banner'))
                .hitTestable(),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);

          // Site topic changes presentation, never the independently scoped
          // urgent announcement or assigned emergency receiver lifecycle.
          final siteTopic = find.byKey(const ValueKey('simple_topic_site'));
          await t.ensureVisible(siteTopic);
          await t.tap(siteTopic);
          await simpleSettle(t);
          expect(
            t.widget<SimpleModuleList>(find.byType(SimpleModuleList)).topic,
            SimpleTopic.site,
          );
          final board = find.byKey(const ValueKey('simple_route_komsuPanosu'));
          await t.ensureVisible(board);
          await t.pump();
          expect(
            board.hitTestable(),
            findsOneWidget,
            reason:
                'actual authorized topic row is reachable below both live warnings',
          );
          expect(h.controller.alarms.single.id, 901);
          expect(
            h.audio.starts,
            1,
            reason: 'topic rebuild must not restart the active alarm',
          );
          expect(
            find.byKey(const ValueKey('emergency_active_banner')).hitTestable(),
            findsOneWidget,
          );
          expect(find.byType(UrgentAnnouncementBanner), findsOneWidget);
          expect(t.takeException(), isNull);

          await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
          await simpleSettle(t);
          expect(
            find.byKey(const ValueKey('emergency_ack_901')),
            findsOneWidget,
          );
          expect(find.text('Alarmı veren: SANAL test sakini'), findsOneWidget);
          await t.ensureVisible(
            find.byKey(const ValueKey('emergency_ack_901')),
          );
          expect(
            find.byKey(const ValueKey('emergency_ack_901')).hitTestable(),
            findsOneWidget,
          );
          expect(t.takeException(), isNull);
          await _unmount(t, h);
        },
      );
    }
  }

  testWidgets(
    'Sade Home personal ACK rejects late GET revival while topic and urgent context survive',
    (t) async {
      final h = await _pumpAlerts(t, size: const Size(320, 640), dark: false);
      await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
      await simpleSettle(t);
      h.service.feedGate = Completer<EmergencyAlarmFeed>();
      final lateGet = h.controller.refresh();
      await t.pump();
      await t.ensureVisible(find.byKey(const ValueKey('emergency_ack_901')));
      await t.tap(find.byKey(const ValueKey('emergency_ack_901')));
      await simpleSettle(t);
      expect(h.service.acknowledgements, 1);
      expect(h.controller.alarms, isEmpty);
      expect(h.audio.playing, isFalse);
      h.service.feedGate!.complete(
        const EmergencyAlarmFeed(
          canReceive: true,
          canSound: true,
          alarms: [
            _alarm,
            EmergencyAlarm(
              id: 902,
              siteCode: 11,
              kind: 'fire',
              siteName: 'Gül Sitesi',
              soundEnabled: false,
            ),
          ],
        ),
      );
      await lateGet;
      await simpleSettle(t);
      expect(h.controller.alarms.map((a) => a.id), [902]);
      expect(
        h.audio.starts,
        1,
        reason: 'late stale GET must not replay personal-ACKed alarm',
      );
      expect(h.audio.playing, isFalse);
      expect(find.byKey(const ValueKey('emergency_ack_901')), findsNothing);
      expect(find.byKey(const ValueKey('emergency_ack_902')), findsOneWidget);
      expect(h.controller.canReceive, isTrue);
      expect(h.notifier.urgentAnnouncement?.id, 77);
      expect(t.takeException(), isNull);
      await _unmount(t, h);
    },
  );
}
