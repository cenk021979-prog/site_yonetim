// EmergencyService (lib/services/emergency_api.dart): uç yolları, gövde biçimi, hata çevirisi, oturum bitişi.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/user_session.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_api.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';
import 'package:site_kapi_kontrol/services/emergency_api.dart';

const String _base = 'https://api.example.test';

http.Response _json(int status, Object? body) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: <String, String>{'content-type': 'application/json; charset=utf-8'},
);

class _FakeAuth extends AuthService {
  _FakeAuth() : super(api: AuthApi(baseUrl: '$_base/'));

  String? token = 'tok-1';
  int refreshForced = 0;

  @override
  UserSession? get session => token == null
      ? null
      : UserSession(
          id: 1,
          fullName: 'Test',
          email: 't@x.com',
          loginName: null,
          role: UserRole.siteManager,
          isActive: true,
          token: token!,
        );

  @override
  Future<void> refreshSession({bool force = false}) async {
    if (force) refreshForced++;
  }
}

Future<ApiException> _failureOf(Future<Object?> Function() call) async {
  try {
    await call();
  } on ApiException catch (e) {
    return e;
  }
  fail('ApiException bekleniyordu');
}

void main() {
  test(
    'bozuk asansör veya konum cevabı başarılı boş kapsam sayılmaz',
    () async {
      for (final body in [
        <String, dynamic>{},
        <String, dynamic>{
          'elevators': [
            {'id': 0},
          ],
        },
        <String, dynamic>{'locations': []},
        <String, dynamic>{
          'locations': [
            {'id': 'block:0'},
          ],
        },
        <String, dynamic>{
          'locations': [
            {'id': 'başka'},
          ],
        },
      ]) {
        final service = EmergencyService(
          authService: _FakeAuth(),
          client: MockClient((_) async => _json(200, body)),
        );
        final call = body.containsKey('elevators')
            ? () => service.listElevators(11)
            : () => service.listLocations(11);
        expect((await _failureOf(call)).code, 'ALARM_RESULT_UNCERTAIN');
        service.close();
      }
      final emptyElevators = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((_) async => _json(200, {'elevators': []})),
      );
      expect(await emptyElevators.listElevators(11), isEmpty);
      emptyElevators.close();
    },
  );
  test(
    'alarm geçmişi sayfalama, başlatan isim ve kayıt durumu; bozuk yanıt başarı sayılmaz',
    () async {
      final service = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((request) async {
          expect(request.url.path, '/app/emergency/alarms/history');
          expect(request.url.queryParameters['before_id'], '91');
          return _json(200, {
            'alarms': [
              {
                'id': 88,
                'site_code': 11,
                'kind': 'fire',
                'created_by_name': 'Ayşe Yılmaz',
                'scope': 'block',
                'status': 'resolved',
              },
            ],
            'has_more': true,
          });
        }),
      );
      final page = await service.alarmHistory(beforeId: 91);
      expect(page.hasMore, true);
      expect(page.alarms.single.createdByName, 'Ayşe Yılmaz');
      expect(page.alarms.single.scope, 'block');
      expect(page.alarms.single.status, 'resolved');
      final broken = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((_) async => _json(200, {})),
      );
      expect(
        (await _failureOf(broken.alarmHistory)).code,
        'ALARM_RESULT_UNCERTAIN',
      );
    },
  );
  test('bozuk feed ve ACK JSONu başarı sayılmaz', () async {
    final service = EmergencyService(
      authService: _FakeAuth(),
      client: MockClient((_) async => _json(200, {})),
    );
    expect(
      (await _failureOf(service.alarmFeed)).code,
      'ALARM_RESULT_UNCERTAIN',
    );
    expect(
      (await _failureOf(() => service.acknowledgeAlarm(1))).code,
      'ALARM_RESULT_UNCERTAIN',
    );
  });
  test('boş/yanlış başarılı yanıt alarm kaydı diye gösterilmez', () async {
    for (final body in [
      {},
      {
        'alarm': {'id': 1, 'site_code': 22, 'kind': 'fire'},
      },
      {
        'alarm': {'id': 1, 'site_code': 11, 'kind': 'elevator'},
      },
    ]) {
      final service = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((_) async => _json(200, body)),
      );
      final error = await _failureOf(
        () => service.createAlarm(
          siteCode: 11,
          kind: 'fire',
          locationId: 'site',
          idempotencyKey: 'same-uncertain-key',
        ),
      );
      expect(error.code, 'ALARM_RESULT_UNCERTAIN');
      expect(error.statusCode, isNull);
    }
  });
  test(
    'yeni alarm uçları, yangın konumu ve idempotency anahtarı taşınır; 201 kabul edilir',
    () async {
      final seen = <http.Request>[];
      final service = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((request) async {
          seen.add(request);
          if (request.url.path.endsWith('/ack') ||
              request.url.path.endsWith('/received') ||
              request.url.path.endsWith('/played')) {
            return _json(200, {'ok': true, 'status': 'open'});
          }
          if (request.url.path.endsWith('/sites')) {
            return _json(200, {
              'sites': [
                {'site_code': 11, 'can_create': true},
              ],
            });
          }
          if (request.url.path.endsWith('/elevators')) {
            return _json(200, {
              'elevators': [
                {'id': 71, 'name': 'A Asansörü'},
              ],
            });
          }
          if (request.url.path.endsWith('/locations')) {
            return _json(200, {
              'locations': [
                {'id': 'block:34', 'name': 'A Blok'},
              ],
            });
          }
          if (request.method == 'POST' &&
              request.url.path.endsWith('/alarms')) {
            return _json(201, {
              'alarm': {'id': 81, 'site_code': 11, 'kind': 'fire'},
              'delivery': {'security_assigned': 1, 'manager_notified': 1},
            });
          }
          return _json(200, {
            'alarms': [],
            'can_receive': true,
            'can_sound': false,
          });
        }),
      );
      expect((await service.listAlarmSites()).single.canCreate, isTrue);
      expect((await service.listElevators(11)).single.id, 71);
      expect((await service.listLocations(11)).single.id, 'block:34');
      final result = await service.createAlarm(
        siteCode: 11,
        kind: 'fire',
        locationId: 'block:34',
        idempotencyKey: 'same-request-123',
      );
      expect(result.alarm.id, 81);
      expect(result.securityAssigned, 1);
      expect(jsonDecode(seen.last.body), {
        'site_code': 11,
        'kind': 'fire',
        'location_id': 'block:34',
        'idempotency_key': 'same-request-123',
      });
      expect((await service.alarmFeed()).canSound, isFalse);
      await service.noteAlarmReceived(81);
      expect(seen.last.url.path, '/app/emergency/alarms/81/received');
      await service.noteAlarmPlayed(81);
      expect(seen.last.url.path, '/app/emergency/alarms/81/played');
      await service.acknowledgeAlarm(81);
      expect(seen.last.url.path, '/app/emergency/alarms/81/ack');
    },
  );
  test(
    'listSites: GET /app/emergency, taşıyıcı belirteç, siteler sırayla ayrıştırılır; site olmayan girdiler atılır',
    () async {
      final auth = _FakeAuth();
      late http.Request seen;
      final service = EmergencyService(
        authService: auth,
        client: MockClient((request) async {
          seen = request;
          return _json(200, <String, dynamic>{
            'sites': <Object>[
              <String, dynamic>{
                'site_code': 1,
                'site_name': 'Gül Sitesi',
                'address': 'Atatürk Mah.',
                'city': 'İstanbul',
                'district': 'Kadıköy',
                'elevator_firm_name': 'Yıldız',
                'elevator_firm_phone': '0212 555 12 34',
                'can_edit': true,
              },
              'bozuk',
              <String, dynamic>{
                'site_code': 2,
                'site_name': 'Lale Sitesi',
                'address': null,
                'can_edit': false,
              },
            ],
          });
        }),
      );
      final sites = await service.listSites();
      expect(seen.method, 'GET');
      expect(seen.url.toString(), '$_base/app/emergency');
      expect(seen.headers['Authorization'], 'Bearer tok-1');
      expect(sites.map((s) => s.siteCode), <int>[1, 2]);
      expect(sites.first.addressLine, 'Atatürk Mah., Kadıköy / İstanbul');
      expect(sites.first.canEdit, isTrue);
      expect(sites.last.hasAddress, isFalse);
      expect(sites.last.canEdit, isFalse);
    },
  );

  test('listSites: sites alanı yoksa ya da liste değilse boş liste', () async {
    final service = EmergencyService(
      authService: _FakeAuth(),
      client: MockClient(
        (_) async => _json(200, <String, dynamic>{'sites': 'x'}),
      ),
    );
    expect(await service.listSites(), isEmpty);
    final none = EmergencyService(
      authService: _FakeAuth(),
      client: MockClient((_) async => _json(200, <String, dynamic>{})),
    );
    expect(await none.listSites(), isEmpty);
  });

  test(
    'saveElevatorFirm: PUT /manager/sites/:kod/emergency, iki alan gövdede; yanıt temizlenmiş değerleri döner',
    () async {
      late http.Request seen;
      final service = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((request) async {
          seen = request;
          return _json(200, <String, dynamic>{
            'site_code': 1000000001,
            'elevator_firm_name': ' Yıldız Asansör ',
            'elevator_firm_phone': '0212 555 12 34',
          });
        }),
      );
      final saved = await service.saveElevatorFirm(
        1000000001,
        name: 'Yıldız   Asansör',
        phone: '0212 555 12 34',
      );
      expect(seen.method, 'PUT');
      expect(seen.url.path, '/manager/sites/1000000001/emergency');
      expect(seen.headers['Content-Type'], contains('application/json'));
      expect(jsonDecode(seen.body), <String, dynamic>{
        'elevator_firm_name': 'Yıldız   Asansör',
        'elevator_firm_phone': '0212 555 12 34',
      });
      expect(saved, (name: 'Yıldız Asansör', phone: '0212 555 12 34'));
    },
  );

  test(
    'saveElevatorFirm: kaldırma iki alanı da null gönderir; yanıt null döner',
    () async {
      late http.Request seen;
      final service = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((request) async {
          seen = request;
          return _json(200, <String, dynamic>{
            'site_code': 1,
            'elevator_firm_name': null,
            'elevator_firm_phone': null,
          });
        }),
      );
      final saved = await service.saveElevatorFirm(1);
      expect(jsonDecode(seen.body), <String, dynamic>{
        'elevator_firm_name': null,
        'elevator_firm_phone': null,
      });
      expect(saved, (name: null, phone: null));
    },
  );

  test(
    'sunucu hatası: sunucunun Türkçe metni ve kodu korunur; 401 oturumu yeniler; genel hata yedek metin taşır',
    () async {
      final auth = _FakeAuth();
      final forbidden = EmergencyService(
        authService: auth,
        client: MockClient(
          (_) async => _json(403, <String, dynamic>{
            'error': 'Bu işlem için yetkiniz yok.',
            'code': 'FORBIDDEN_ROLE',
          }),
        ),
      );
      final denied = await _failureOf(
        () => forbidden.saveElevatorFirm(1, name: 'A', phone: '112'),
      );
      expect(denied.message, 'Bu işlem için yetkiniz yok.');
      expect(denied.code, 'FORBIDDEN_ROLE');
      expect(denied.statusCode, 403);

      final expired = EmergencyService(
        authService: auth,
        client: MockClient(
          (_) async =>
              _json(401, <String, dynamic>{'error': 'Oturum süresi doldu.'}),
        ),
      );
      final unauthorized = await _failureOf(expired.listSites);
      expect(unauthorized.statusCode, 401);
      expect(auth.refreshForced, 1);

      final broken = EmergencyService(
        authService: auth,
        client: MockClient((_) async => http.Response('<html>', 502)),
      );
      final generic = await _failureOf(broken.listSites);
      expect(generic.statusCode, 502);
      expect(generic.message, contains('502'));
    },
  );

  test(
    'ağ hatası Türkçe mesajlı ApiException olur; oturum yoksa istek hiç gitmez',
    () async {
      final offline = EmergencyService(
        authService: _FakeAuth(),
        client: MockClient((_) async => throw http.ClientException('yok')),
      );
      final failure = await _failureOf(offline.listSites);
      expect(failure.message, contains('Sunucuya bağlanılamadı'));

      final signedOut = _FakeAuth()..token = null;
      var requests = 0;
      final service = EmergencyService(
        authService: signedOut,
        client: MockClient((_) async {
          requests++;
          return _json(200, <String, dynamic>{});
        }),
      );
      final noSession = await _failureOf(service.listSites);
      expect(noSession.message, contains('Oturum'));
      expect(requests, 0);
    },
  );
}
