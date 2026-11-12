import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/emergency_alarm_controller.dart';
import 'package:site_kapi_kontrol/ui/widgets/emergency_alarm_host.dart';
import '../emergency_alarm_controller_test.dart';
import 'emergency_view_test.dart'
    show boundaryKey, renderProof, loadAlarmReviewFont, alarmReviewTheme;

void main() {
  setUpAll(loadAlarmReviewFont);
  testWidgets(
    'ilk istek hatası gizlenmez; yenileme başarılı olunca alıcı arayüzü gelir',
    (t) async {
      final service = FakeAlarmFeedService()
        ..feedError = StateError('offline')
        ..feed = alarmFeed();
      final audio = FakeAlarmAudio();
      final controller = EmergencyAlarmController(
        authService: service.authService,
        service: service,
        audio: audio,
        soundInitiallyEnabled: false,
      );
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmergencyAlarmHost(
              authService: service.authService,
              controller: controller,
            ),
          ),
        ),
      );
      await t.pump();
      expect(
        find.byKey(const ValueKey('emergency_connection_error')),
        findsOneWidget,
      );
      expect(audio.starts, 0);
      service.feedError = null;
      await t.tap(find.byKey(const ValueKey('emergency_connection_error')));
      await t.pump();
      await t.pump();
      expect(
        find.byKey(const ValueKey('emergency_connection_error')),
        findsNothing,
      );
      expect(find.text('Alarm kayıtları'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      controller.dispose();
      await t.pump();
    },
  );
  for (final dark in [false, true]) {
    testWidgets(
      '320px yazı2 alarm şeridi ve kişisel onay ${dark ? 'koyu' : 'açık'}',
      (t) async {
        final service = FakeAlarmFeedService()..feed = alarmFeed();
        final audio = FakeAlarmAudio();
        final controller = EmergencyAlarmController(
          authService: service.authService,
          service: service,
          audio: audio,
          soundInitiallyEnabled: false,
        );
        t.view.physicalSize = const Size(320, 900);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final theme = alarmReviewTheme(dark);
        await t.pumpWidget(
          MaterialApp(
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'ReviewRoboto'),
            ),
            home: MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 900),
                textScaler: TextScaler.linear(2),
              ),
              child: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: ColoredBox(
                    color: theme.scaffoldBackgroundColor,
                    child: Column(
                      children: [
                        EmergencyAlarmHost(
                          authService: service.authService,
                          controller: controller,
                        ),
                        const Expanded(
                          child: Center(child: Text('Uygulama içeriği')),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.pump();
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        expect(service.played, 0);
        await renderProof(t, 'alarm-seridi-320-${dark ? 'koyu' : 'acik'}');
        await t.tap(find.byKey(const ValueKey('emergency_alarm_inbox')));
        await t.pumpAndSettle();
        expect(find.text('Gördüm, alarmı sustur'), findsOneWidget);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.byKey(const ValueKey('emergency_ack_1')));
        await t.tap(find.byKey(const ValueKey('emergency_ack_1')));
        await t.pump();
        await t.pump();
        expect(service.acknowledgements, 1);
        expect(controller.alarms, isEmpty);
        await t.pumpWidget(const SizedBox());
        controller.dispose();
        await t.pump();
      },
    );
  }
}
