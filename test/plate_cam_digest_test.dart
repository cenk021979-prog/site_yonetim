import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:site_kapi_kontrol/models/plate_gates.dart';
import 'package:site_kapi_kontrol/services/plate_cameras_api.dart';
import 'package:site_kapi_kontrol/services/plate_camera_snapshot.dart';

PlateCameraRow _camera(String host, int id) => PlateCameraRow(
  id: id,
  name: 'Test kamerası',
  brand: 'hikvision',
  brandLabel: 'Hikvision',
  host: host,
  port: 554,
  rtspUrl: 'rtsp://$host:554/Streaming/Channels/101',
  username: 'test-operator',
  hasPassword: true,
  isActive: true,
  managed: true,
  status: const GateBadge(state: 'calisiyor', color: GateColor.yesil),
  probe: const ProbeInfo(status: 'ok'),
  snapshot: const SnapshotInfo(available: true),
);

String _md5(String text) => md5.convert(utf8.encode(text)).toString();
String _field(String header, String key) => RegExp(
  '(?:^|[, ])$key=(?:"([^"]*)"|([^, ]+))',
).firstMatch(header)!.groups([1, 2]).whereType<String>().single;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'Digest challenge gerçek kamera veya ağ olmadan doğrulanır, JPEG döner',
    () async {
      const host = 'digest-camera.example.test';
      const password = 'test-only-camera-password';
      const realm = 'camera-test';
      const nonce = 'test-server-nonce';
      final camera = _camera(host, 90001);
      PlateCameraSnapshot.recordCredentials(
        host: host,
        username: 'test-operator',
        password: password,
        cameraId: camera.id,
      );
      final jpeg = List<int>.filled(1200, 0)
        ..setRange(0, 3, [0xff, 0xd8, 0xff]);
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        expect(request.url.host, host);
        final authorization = request.headers['authorization'] ?? '';
        if (requests.length == 1) {
          expect(authorization, startsWith('Basic '));
          return http.Response(
            '',
            401,
            headers: {
              'www-authenticate':
                  'Digest realm="$realm", nonce="$nonce", qop="auth", opaque="test-opaque"',
            },
          );
        }
        expect(authorization, startsWith('Digest '));
        final digestUri = _field(authorization, 'uri');
        expect(digestUri, request.url.path);
        expect(_field(authorization, 'username'), 'test-operator');
        expect(_field(authorization, 'realm'), realm);
        expect(_field(authorization, 'nonce'), nonce);
        expect(_field(authorization, 'opaque'), 'test-opaque');
        expect(_field(authorization, 'qop'), 'auth');
        expect(_field(authorization, 'nc'), '00000001');
        final ha1 = _md5('test-operator:$realm:$password');
        final ha2 = _md5('GET:$digestUri');
        final expected = _md5(
          '$ha1:$nonce:${_field(authorization, 'nc')}:${_field(authorization, 'cnonce')}:auth:$ha2',
        );
        expect(_field(authorization, 'response'), expected);
        expect(authorization, isNot(contains(password)));
        return http.Response.bytes(
          jpeg,
          200,
          headers: {'content-type': 'image/jpeg'},
        );
      });
      addTearDown(client.close);
      final (uri, result) = await PlateCameraSnapshot.discover(client, camera);
      expect(result.ok, isTrue, reason: result.error);
      expect(result.bytes, orderedEquals(jpeg));
      expect(uri?.host, host);
      expect(requests, hasLength(2));
    },
  );

  test(
    'Digest yanıtı da reddedilirse başarı veya görüntü iddia edilmez',
    () async {
      const host = 'denied-camera.example.test';
      final camera = _camera(host, 90002);
      PlateCameraSnapshot.recordCredentials(
        host: host,
        username: 'test-operator',
        password: 'test-only-denied-password',
        cameraId: camera.id,
      );
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        return http.Response(
          '',
          401,
          headers: {
            'www-authenticate':
                'Digest realm="denied-test", nonce="denied-test-nonce", qop="auth"',
          },
        );
      });
      addTearDown(client.close);
      final result = await PlateCameraSnapshot.fetch(
        client,
        camera,
        Uri.parse('http://$host/snapshot.jpg'),
      );
      expect(result.ok, isFalse);
      expect(result.bytes, isNull);
      expect(result.error, contains('HTTP 401'));
      expect(calls, 2);
    },
  );
}
