import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_alarm_history_dialog.dart';
import 'people_fixtures.dart';

class _HistoryService extends EmergencyService {
  _HistoryService() : super(authService: PeopleFakeAuth());
  final beforeIds = <int?>[];
  @override
  Future<EmergencyAlarmHistoryPage> alarmHistory({int? beforeId}) async {
    beforeIds.add(beforeId);
    return EmergencyAlarmHistoryPage(
      alarms: [
        EmergencyAlarm(
          id: beforeId == null ? 9 : 8,
          siteCode: 11,
          kind: 'fire',
          scope: 'block',
          location: 'A Blok',
          status: 'resolved',
          createdByName: 'Ayşe Yılmaz',
        ),
      ],
      hasMore: beforeId == null,
    );
  }
}

void main() {
  testWidgets(
    '320px yüksek yazıda kayıtlı kişi/durum görünür, eski kayıtlar eklenir ve yenilenir',
    (t) async {
      t.view.physicalSize = const Size(320, 700);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final service = _HistoryService();
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 700),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: EmergencyAlarmHistoryDialog(service: service),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Alarmı veren: Ayşe Yılmaz'), findsOneWidget);
      expect(find.text('Olay kapatıldı'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Önceki kayıtlar'));
      await t.tap(find.text('Önceki kayıtlar'));
      await t.pumpAndSettle();
      expect(service.beforeIds, [null, 9]);
      expect(find.text('Alarmı veren: Ayşe Yılmaz'), findsNWidgets(2));
      await t.tap(find.text('Yenile'));
      await t.pumpAndSettle();
      expect(service.beforeIds, [null, 9, null]);
      expect(find.text('Alarmı veren: Ayşe Yılmaz'), findsOneWidget);
      expect(t.takeException(), isNull);
      service.close();
    },
  );
}
