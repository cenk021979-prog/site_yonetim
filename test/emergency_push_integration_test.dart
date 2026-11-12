import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/models/push_models.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/services/push_service.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/ui/widgets/emergency_alarm_host.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_alarm_history_dialog.dart';
import 'push_fakes.dart';
import 'emergency_alarm_controller_test.dart' show FakeAlarmAudio;

const alarmPush = PushMessage({
  'type': 'emergency',
  'alarm_id': '1',
  'site_code': '11',
});

Future<T> _finish<T>(WidgetTester tester, Future<T> operation) async {
  // Keep work in the widget fake-async zone; crossing into runAsync while a
  // serialized push task is already queued can strand its microtasks.
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump();
  }
  return operation;
}

class _AlarmService extends EmergencyService {
  _AlarmService(SwitchableAuth auth) : super(authService: auth);
  EmergencyAlarmFeed feed = const EmergencyAlarmFeed(
    canReceive: true,
    canSound: false,
  );
  int loads = 0;
  Completer<EmergencyAlarmFeed>? gate;
  @override
  Future<EmergencyAlarmFeed> alarmFeed() async {
    loads++;
    return gate?.future ?? feed;
  }

  @override
  Future<void> noteAlarmReceived(int id) async {}
  @override
  Future<void> noteAlarmPlayed(int id) async {}
  @override
  Future<EmergencyAlarmHistoryPage> alarmHistory({int? beforeId}) async =>
      const EmergencyAlarmHistoryPage();
}

void main() {
  late FakePushGateway gateway;
  late FakePushApi api;
  late PushService push;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final events = <String>[];
    gateway = FakePushGateway(events);
    api = FakePushApi(events);
    push = PushService(
      apiFactory: (_) => api,
      appVersion: () async => '1.0.0',
      observeLifecycle: false,
      routeBlockers: [],
    );
  });
  tearDown(() async {
    PushService.debugInstance = null;
    await push.dispose();
    await gateway.close();
  });

  test(
    'emergency references accept only valid alarm AND site IDs; body cannot supply a display record',
    () {
      expect(alarmPush.emergency?.alarmId, 1);
      expect(alarmPush.emergency?.siteCode, 11);
      for (final bad in <Object?>[
        null,
        '0',
        '01',
        '-1',
        '1e3',
        '1.5',
        1.2,
        '9999999999999999',
      ]) {
        expect(
          PushMessage({
            'type': 'emergency',
            'alarm_id': bad,
            'site_code': '11',
          }).emergency,
          isNull,
        );
        expect(
          PushMessage({
            'type': 'emergency',
            'alarm_id': '1',
            'site_code': bad,
          }).emergency,
          isNull,
        );
      }
      expect(
        const PushMessage({
          'type': 'other',
          'alarm_id': '1',
          'site_code': '11',
        }).emergency,
        isNull,
      );
    },
  );

  test(
    'only server-eligible individual opts in; revocation removes their existing device/token',
    () async {
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      api.capability = const PushCapabilities(
        available: true,
        canRegister: true,
        emergencyOnly: true,
      );
      await push.start(gateway);
      push.attach(auth);
      await pushSettle();
      expect(
        gateway.getTokenCalls,
        0,
        reason: 'no token without explicit opt-in',
      );
      expect(await push.enableOnThisDevice(auth), PushEnableOutcome.registered);
      expect(api.registers, hasLength(1));
      api.capability = const PushCapabilities(available: true);
      await push.syncNow(auth);
      expect(api.deletes, hasLength(1));
      expect(gateway.deleteTokenCalls, 1);
      expect(push.activeHere.value, isFalse);
    },
  );

  test(
    'unassigned individual is never asked for OS notification permission',
    () async {
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      gateway.permission = PushPermission.notDetermined;
      await push.start(gateway);
      push.attach(auth);
      expect(
        await push.enableOnThisDevice(auth),
        PushEnableOutcome.unsupported,
      );
      expect(gateway.requestCalls, 0);
      expect(gateway.getTokenCalls, 0);
      expect(api.registers, isEmpty);
    },
  );

  test(
    'old capability response after account change never registers using the new account',
    () async {
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      api.capabilityGate = Completer<PushCapabilities>();
      await push.start(gateway);
      push.attach(auth);
      final pending = push.enableOnThisDevice(auth);
      await pushSettle();
      expect(api.capabilityCalls, 1);
      auth.switchTo(pushSession(id: 6, token: 'tok-B'));
      api.capabilityGate!.complete(
        const PushCapabilities(
          available: true,
          canRegister: true,
          emergencyOnly: true,
        ),
      );
      expect(await pending, PushEnableOutcome.unsupported);
      expect(api.registers, isEmpty);
      expect(gateway.requestCalls, 0);
    },
  );

  test(
    'foreground emergency and taps use their own channel; announcement routing remains separate',
    () async {
      final auth = SwitchableAuth(pushSession());
      await push.start(gateway);
      push.attach(auth);
      final foreground = <EmergencyPushReference>[];
      final opened = <EmergencyPushReference>[];
      final announcements = <int>[];
      final subscription = push.foregroundEmergencies.listen(foreground.add);
      final announcementSubscription = push.foregroundAnnouncements.listen(
        announcements.add,
      );
      push.bindEmergencyOpener(opened.add);
      gateway.messageController.add(alarmPush);
      gateway.openedController.add(alarmPush);
      gateway.messageController.add(
        const PushMessage({'type': 'announcement', 'announcement_id': '7'}),
      );
      await pushSettle();
      expect(foreground.single.alarmId, 1);
      expect(opened.single.siteCode, 11);
      expect(announcements, [7]);
      await subscription.cancel();
      await announcementSubscription.cancel();
    },
  );

  test(
    'blocked emergency tap is discarded across token/account changes',
    () async {
      final blocker = ValueNotifier(true);
      final scoped = PushService(
        apiFactory: (_) => api,
        observeLifecycle: false,
        routeBlockers: [blocker],
      );
      final auth = SwitchableAuth(pushSession());
      final opened = <EmergencyPushReference>[];
      await scoped.start(gateway);
      scoped.attach(auth);
      scoped.bindEmergencyOpener(opened.add);
      gateway.openedController.add(alarmPush);
      await pushSettle();
      auth.switchTo(pushSession(token: 'refreshed-token'));
      blocker.value = false;
      await pushSettle();
      expect(opened, isEmpty);
      blocker.value = true;
      gateway.openedController.add(alarmPush);
      await pushSettle();
      auth.switchTo(pushSession(id: 6, token: 'other-account'));
      blocker.value = false;
      await pushSettle();
      expect(opened, isEmpty);
      await scoped.dispose();
      blocker.dispose();
    },
  );

  test('cold-start emergency waits for an authenticated host/opener', () async {
    gateway.initial = alarmPush;
    await push.start(gateway);
    final opened = <EmergencyPushReference>[];
    push.bindEmergencyOpener(opened.add);
    expect(opened, isEmpty);
    push.attach(SwitchableAuth(pushSession()));
    expect(opened.single.alarmId, 1);
  });

  testWidgets(
    'receiver transitions sync an opted-in device without repeated poll traffic',
    (t) async {
      PushService.debugInstance = push;
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      final service = _AlarmService(auth)..feed = const EmergencyAlarmFeed();
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: FakeAlarmAudio(),
        soundInitiallyEnabled: false,
      );
      await push.start(gateway);
      push.attach(auth);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyAlarmHost(authService: auth, controller: controller),
          ),
        ),
      );
      await t.pump();
      expect(
        await _finish(t, push.enableOnThisDevice(auth)),
        PushEnableOutcome.unsupported,
      );
      api.capability = const PushCapabilities(
        available: true,
        canRegister: true,
        emergencyOnly: true,
      );
      service.feed = const EmergencyAlarmFeed(canReceive: true, canSound: true);
      await _finish(t, controller.refresh());
      await t.pump();
      await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('emergency_enable_phone_push')));
      await _finish(t, Future<void>.value());
      await t.pump();
      expect(
        api.registers,
        hasLength(1),
        reason: 'fresh assignment replaces false cache',
      );
      final calls = api.capabilityCalls;
      await _finish(t, controller.refresh());
      await _finish(t, controller.refresh());
      expect(
        api.capabilityCalls,
        calls,
        reason: 'unchanged polls do not sync push',
      );
      api.capability = const PushCapabilities(available: true);
      service.feed = const EmergencyAlarmFeed();
      await _finish(t, controller.refresh());
      expect(
        api.deletes,
        hasLength(1),
        reason: 'revocation is cleaned without app resume',
      );
      expect(push.activeHere.value, isFalse);
      api.capability = const PushCapabilities(
        available: true,
        canRegister: true,
        emergencyOnly: true,
      );
      service.feed = const EmergencyAlarmFeed(canReceive: true, canSound: true);
      await _finish(t, controller.refresh());
      expect(
        api.registers,
        hasLength(2),
        reason: 'saved opt-in survives reassignment',
      );
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.pump();
    },
  );

  testWidgets(
    'permanent permission denial opens settings only for the unchanged eligible scope',
    (t) async {
      PushService.debugInstance = push;
      final auth = SwitchableAuth(pushSession(role: UserRole.individual));
      api.capability = const PushCapabilities(
        available: true,
        canRegister: true,
        emergencyOnly: true,
      );
      gateway.permission = PushPermission.permanentlyDenied;
      final service = _AlarmService(auth)
        ..feed = const EmergencyAlarmFeed(canReceive: true, canSound: true);
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: FakeAlarmAudio(),
        soundInitiallyEnabled: false,
      );
      await push.start(gateway);
      push.attach(auth);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyAlarmHost(authService: auth, controller: controller),
          ),
        ),
      );
      await t.pump();
      await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('emergency_enable_phone_push')));
      await _finish(t, Future<void>.value());
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      final action = t.widget<SnackBarAction>(find.byType(SnackBarAction));
      expect(action.label, 'Telefon ayarlarını aç');
      await t.tap(find.text('Telefon ayarlarını aç'));
      await _finish(t, Future<void>.value());
      expect(gateway.settingsOpened, isTrue);
      gateway.settingsOpened = false;
      api.capabilityGate = Completer<PushCapabilities>();
      action.onPressed();
      await _finish(t, Future<void>.value());
      auth.switchTo(
        pushSession(role: UserRole.siteManager, token: 'other-scope'),
      );
      api.capabilityGate!.complete(
        const PushCapabilities(
          available: true,
          canRegister: true,
          emergencyOnly: true,
        ),
      );
      await _finish(t, Future<void>.value());
      expect(
        gateway.settingsOpened,
        isFalse,
        reason: 'scope changed during eligibility request',
      );
      final calls = api.capabilityCalls;
      action.onPressed();
      await _finish(t, Future<void>.value());
      expect(
        api.capabilityCalls,
        calls,
        reason: 'old snackbar action is inert',
      );
      expect(gateway.settingsOpened, isFalse);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.pump();
    },
  );

  for (final scenario in [
    (history: true, apiFails: false),
    (history: false, apiFails: false),
    (history: true, apiFails: true),
    (history: false, apiFails: true),
  ]) {
    final openHistory = scenario.history;
    testWidgets(
      '${scenario.apiFails ? 'API error' : 'permission result'}: ${openHistory
          ? 'permission result preserves nested history and remains in its alarm panel'
          : 'permission result after manual panel close never pops a different route'}',
      (t) async {
        PushService.debugInstance = push;
        final auth = SwitchableAuth(pushSession(role: UserRole.individual));
        api.capability = const PushCapabilities(
          available: true,
          canRegister: true,
          emergencyOnly: true,
        );
        gateway.permission = scenario.apiFails
            ? PushPermission.granted
            : PushPermission.permanentlyDenied;
        final service = _AlarmService(auth);
        final controller = EmergencyAlarmController(
          authService: auth,
          service: service,
          audio: FakeAlarmAudio(),
          soundInitiallyEnabled: false,
        );
        final navigation = GlobalKey<NavigatorState>();
        await push.start(gateway);
        push.attach(auth);
        await t.pumpWidget(
          MaterialApp(
            navigatorKey: navigation,
            home: Scaffold(
              body: EmergencyAlarmHost(
                authService: auth,
                controller: controller,
              ),
            ),
          ),
        );
        await t.pump();
        await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
        await t.pumpAndSettle();
        if (scenario.apiFails) {
          api.registerGate = Completer<void>();
          api.registerError = ApiException('API offline', statusCode: 503);
        } else {
          api.capabilityGate = Completer<PushCapabilities>();
        }
        await t.tap(find.byKey(const ValueKey('emergency_enable_phone_push')));
        await _finish(t, Future<void>.value());
        if (scenario.apiFails) {
          expect(api.registers, hasLength(1), reason: 'yetki kontrolünü geçip gerçek kayıt API çağrısında beklemeli');
        }
        if (openHistory) {
          await t.tap(find.byKey(const ValueKey('emergency_history')));
          await t.pumpAndSettle();
          expect(find.byType(EmergencyAlarmHistoryDialog), findsOneWidget);
        } else {
          await t.tap(find.text('Kapat'));
          await t
              .pump(); // izin sonucu kapanış animasyonu aralığında da gelebilir.
          unawaited(
            navigation.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Başka sayfa')),
              ),
            ),
          );
          await t.pumpAndSettle();
        }
        if (scenario.apiFails) {
          api.registerGate!.complete();
        } else {
          api.capabilityGate!.complete(
          const PushCapabilities(
            available: true,
            canRegister: true,
            emergencyOnly: true,
          ),
          );
        }
        await _finish(t, Future<void>.value());
        await t.pumpAndSettle();
        if (openHistory) {
          expect(find.byType(EmergencyAlarmHistoryDialog), findsOneWidget);
          navigation.currentState!.pop();
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('emergency_phone_push_result')),
            findsOneWidget,
          );
          if (scenario.apiFails) {
            expect(t.widget<Text>(find.byKey(const ValueKey('emergency_phone_push_result'))).data,
              'Telefon bildirimi kaydedilemedi. Yeniden deneyin.');
            expect(find.byKey(const ValueKey('emergency_phone_push_settings')), findsNothing);
          } else {
            await t.tap(find.byKey(const ValueKey('emergency_phone_push_settings')));
            await _finish(t, Future<void>.value());
            expect(gateway.settingsOpened, isTrue);
          }
        } else {
          expect(find.text('Başka sayfa'), findsOneWidget);
          expect(navigation.currentState!.canPop(), isTrue);
        }
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        controller.dispose();
        await t.pump();
      },
    );
  }

  testWidgets(
    'host refreshes foreground feed and opens only the API-authorized referenced alarm',
    (t) async {
      PushService.debugInstance = push;
      final auth = SwitchableAuth(pushSession());
      final service = _AlarmService(auth);
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: FakeAlarmAudio(),
        soundInitiallyEnabled: false,
      );
      await push.start(gateway);
      push.attach(auth);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyAlarmHost(authService: auth, controller: controller),
          ),
        ),
      );
      await t.pump();
      service.feed = const EmergencyAlarmFeed(
        canReceive: true,
        canSound: false,
        alarms: [
          EmergencyAlarm(
            id: 1,
            siteCode: 11,
            kind: 'fire',
            siteName: 'Authorized site',
            createdByName: 'Authorized sender',
          ),
          EmergencyAlarm(
            id: 2,
            siteCode: 12,
            kind: 'fire',
            siteName: 'Other permitted site',
          ),
        ],
      );
      final loads = service.loads;
      gateway.messageController.add(alarmPush);
      await t.pump();
      await t.pump();
      expect(service.loads, greaterThan(loads));
      gateway.openedController.add(alarmPush);
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Alarmı veren: Authorized sender'), findsOneWidget);
      expect(
        find.text('Other permitted site'),
        findsNothing,
        reason: 'tap shows the referenced alarm only',
      );
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.pump();
    },
  );

  testWidgets(
    'foreign alarm/site references never show push body as an authorized event',
    (t) async {
      PushService.debugInstance = push;
      final auth = SwitchableAuth(pushSession());
      final service = _AlarmService(auth);
      final controller = EmergencyAlarmController(
        authService: auth,
        service: service,
        audio: FakeAlarmAudio(),
        soundInitiallyEnabled: false,
      );
      await push.start(gateway);
      push.attach(auth);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyAlarmHost(authService: auth, controller: controller),
          ),
        ),
      );
      await t.pump();
      gateway.openedController.add(
        const PushMessage({
          'type': 'emergency',
          'alarm_id': '1',
          'site_code': '999',
          'message': 'Untrusted body',
        }),
      );
      await t.pump();
      await t.pump();
      await t.pump();
      await t.pump();
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('Untrusted body'), findsNothing);
      expect(
        find.text('Bu alarm artık etkin değil veya bu hesaba açık değil.'),
        findsOneWidget,
      );
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.pump();
    },
  );
}
