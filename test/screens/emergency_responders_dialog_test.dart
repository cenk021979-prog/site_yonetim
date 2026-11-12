import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/emergency_responders_dialog.dart';
import 'people_fixtures.dart';

class _RespondersService extends EmergencyService {
  _RespondersService() : super(authService: PeopleFakeAuth());
  List<Map<String, dynamic>>? saved;
  @override
  Future<Map<String, dynamic>> responders(int code) async => {
    'responders': [
      {'role': 'security', 'user_code': 42, 'user_name': 'Mevcut güvenlik'},
    ],
    'security_candidates': [
      {'user_code': 42, 'user_name': 'Mevcut güvenlik'},
    ],
    'vendors': [
      {'id': 9, 'name': 'Anlaşmalı Asansör'},
    ],
  };
  @override
  Future<void> saveResponders(int code, List<Map<String, dynamic>> rows) async {
    saved = rows;
  }
}

void main() {
  testWidgets(
    '320px yazı2 alıcı ayarı taşmaz; kaldırma tam listeyle kaydedilir',
    (t) async {
      final service = _RespondersService();
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 900),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showEmergencyRespondersDialog(
                    context,
                    service: service,
                    siteCode: 11,
                  ),
                  child: const Text('Aç'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('Aç'));
      await t.pumpAndSettle();
      expect(find.text('Mevcut güvenlik'), findsWidgets);
      expect(t.takeException(), isNull);
      await t.tap(find.byTooltip('Alıcıyı kaldır'));
      await t.pump();
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(service.saved, isEmpty);
      expect(find.byType(EmergencyRespondersDialog), findsNothing);
    },
  );
}
