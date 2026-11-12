import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/parking_access.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_engine.dart';
import 'package:site_kapi_kontrol/ui/widgets/parking_access_panel.dart';

PlateRecognitionEngine _engine(MockClient client) {
  final engine = PlateRecognitionEngine.forTesting(client: client);
  engine.start(
    siteCode: 1,
    baseUrl: 'https://example.invalid',
    token: 'test-token',
    cameras: [
      PlateCameraRow.fromJson({
        'id': 5,
        'name': 'Giriş',
        'host': 'test.invalid',
        'direction': 'giris',
        'is_active': true,
        'gate': {'id': 3, 'name': 'Ana kapı', 'door_id': 2},
      }),
    ],
    blacklist: [],
    guestPermits: [],
    vehicles: {
      '34ABC123': {'apartment_label': 'A / 1'},
    },
    parkingSlots: {1: 1},
    insideCounts: {1: 0},
  );
  return engine;
}

ParkingOverview _overview() => ParkingOverview.fromJson({
  'policy': {
    'enabled': true,
    'capacity': 5,
    'registration_photo_enabled': false,
  },
  'total': 1,
  'notice':
      'Geçiş kaydına göre; fiziksel geçiş sensörü teyidi yok. Belirsiz kayıtları görevli kontrol ederek düzeltir.',
  'apartments': [
    {
      'id': 1,
      'block_name': 'Çok uzun blok adı örneği',
      'unit_label': '123456789',
      'approved': true,
      'parking_slots': 1,
      'plates': ['34ABC123', '06XYZ999'],
      'inside_plates': ['34ABC123'],
    },
  ],
  'reservations': [
    {
      'id': 1,
      'plate': '34ABC123',
      'origin': 'admission',
      'status': 'uncertain',
    },
  ],
});

class _Service extends Fake implements PlateRecognitionService {
  @override
  Future<ParkingOverview> parking(int site) async => _overview();
}

void main() {
  test(
    'sunucu onaylı komut yerelde yeniden tetiklenmez veya tekrar event gönderilmez',
    () async {
      final requests = <http.Request>[];
      final engine = _engine(
        MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'enabled': true,
              'admission_id': 1,
              'allowed': true,
              'command_accepted': true,
              'status': 'accepted',
              'direction': 'giris',
              'message':
                  'Komut kabul edildi; fiziksel geçiş sensör teyidi yok.',
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final decision = await engine.testProcessPlate('34 ABC 123');
      expect(decision.fromServer, true);
      expect(decision.isGateTriggered, true);
      expect(requests.length, 1);
      expect(requests.single.url.path, endsWith('/admissions'));
      expect((jsonDecode(requests.single.body) as Map)['confidence'], .99);
      engine.stop();
    },
  );
  test('kotası dolu kararında görevliye içerideki plaka gösterilir', () async {
    final engine = _engine(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'enabled': true,
            'admission_id': 2,
            'allowed': false,
            'command_accepted': false,
            'status': 'denied',
            'message': 'Daire hakkı dolu.',
            'blocking_plates': ['06XYZ999'],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    final result = await engine.testProcessPlate('34ABC123');
    expect(result.decision, PlateDecisionType.red);
    expect(result.reason, contains('06XYZ999'));
    expect(result.isGateTriggered, false);
    engine.stop();
  });
  test(
    '503 veya bozuk200 cached sakin plakasını açamaz; belirsiz isteğin kimliği korunur',
    () async {
      final bodies = <Map>[];
      final engine = _engine(
        MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map);
          return bodies.length == 1
              ? http.Response('{}', 503)
              : http.Response('{"enabled":true}', 200);
        }),
      );
      final first = await engine.testProcessPlate('34ABC123');
      final second = await engine.testProcessPlate('34ABC123');
      expect(first.decision, PlateDecisionType.red);
      expect(second.decision, PlateDecisionType.red);
      expect(bodies[0]['request_id'], bodies[1]['request_id']);
      expect(second.isGateTriggered, false);
      engine.stop();
    },
  );
  test('kapasite kapalı olsa da onaysız daire plakası reddedilir', () async {
    final engine = _engine(
      MockClient(
        (_) async => http.Response('{"enabled":false,"authorized":false}', 200),
      ),
    );
    final result = await engine.testProcessPlate('34ABC123');
    expect(result.decision, PlateDecisionType.red);
    expect(result.reason, contains('yönetim onayı'));
    engine.stop();
  });
  for (final canWrite in [false, true]) {
    testWidgets('320px 2x metinde otopark paneli taşmaz; yazma=$canWrite', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: ParkingAccessPanel(
                service: _Service(),
                siteCode: 1,
                canWrite: canWrite,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.textContaining('34ABC123'), findsWidgets);
      expect(
        find.text('Otopark ayarlarını kaydet'),
        canWrite ? findsOneWidget : findsNothing,
      );
      expect(
        find.text('Daire onayı / araç hakkı'),
        canWrite ? findsOneWidget : findsNothing,
      );
    });
  }
}
