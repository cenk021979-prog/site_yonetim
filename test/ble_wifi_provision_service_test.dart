import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BleWifiProvisionService (masaüstü: Windows/Linux, BLE eklentisi yok)', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    test(
      'kurucu FlutterReactiveBle başlatmaz: yakalanmamış asenkron UnimplementedError oluşmaz',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final uncaught = <Object>[];

        await runZonedGuarded(() async {
          final service = BleWifiProvisionService();
          // FlutterReactiveBle() yapıcısı durum akışını asenkron başlatır; hata gecikmeli gelir.
          await Future<void>.delayed(const Duration(milliseconds: 150));
          expect(service.isSupportedPlatform, isFalse);
          await service.dispose();
        }, (error, stack) => uncaught.add(error));

        expect(uncaught, isEmpty);
      },
    );

    test('ensureReady desteklenmeyen platformda anlaşılır BleProvisionException fırlatır', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        final service = BleWifiProvisionService();
        await expectLater(service.ensureReady(), throwsA(isA<BleProvisionException>()));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }, (error, stack) => uncaught.add(error));

      expect(uncaught, isEmpty);
    });
  });

  group('AHBU ve SmartKeyPass BLE Cihaz Tanıma ve UID Çıkarımı', () {
    test('isBleProvisionDeviceName hem AHBU hem SmartKeyPass hem varyantları tanır', () {
      expect(isBleProvisionDeviceName('AHBU240AC4E2E001'), isTrue);
      expect(isBleProvisionDeviceName('ahbu-240ac4e2e001'), isTrue);
      expect(isBleProvisionDeviceName('AHBU'), isTrue);
      expect(isBleProvisionDeviceName('SmartKeyPass240AC4E2E001'), isTrue);
      expect(isBleProvisionDeviceName('SmartKey_Gate'), isTrue);
      expect(isBleProvisionDeviceName('SKP_RELAY'), isTrue);
      expect(isBleProvisionDeviceName('KAPI_01'), isTrue);
      expect(isBleProvisionDeviceName('ESP32_C3_GATE'), isTrue);

      // İlgisiz cihazlar elenir
      expect(isBleProvisionDeviceName('Mi Band 7'), isFalse);
      expect(isBleProvisionDeviceName('JBL Flip 5'), isFalse);
      expect(isBleProvisionDeviceName(''), isFalse);
    });

    test('extractBleDeviceUid isim veya MAC adresinden doğru UID ayıklar', () {
      expect(extractBleDeviceUid('AHBU240AC4E2E001'), equals('240AC4E2E001'));
      expect(extractBleDeviceUid('AHBU-240AC4E2E001'), equals('240AC4E2E001'));
      expect(extractBleDeviceUid('SmartKeyPass240AC4E2E001'), equals('240AC4E2E001'));
      expect(extractBleDeviceUid('SKP-AABBCCDDEEFF'), equals('AABBCCDDEEFF'));
      expect(extractBleDeviceUid('240AC4E2E001'), equals('240AC4E2E001'));
      // İsim sade AHBU ise MAC adresinden ayıklar
      expect(
        extractBleDeviceUid('AHBU', deviceId: '24:0A:C4:E2:E0:01'),
        equals('240AC4E2E001'),
      );
    });

    test('BleWifiState.fromPayload eski ve yeni formatları ve fallback UID destekler', () {
      // Standart payload
      final standard = BleWifiState.fromPayload(
        '{"device_uid":"240AC4E2E001","wifi_connected":true,"provisioning":false,"has_credentials":true,"mqtt_configured":true,"ssid":"MyWifi","ip":"192.168.1.50"}',
      );
      expect(standard.deviceUid, equals('240AC4E2E001'));
      expect(standard.wifiConnected, isTrue);

      // Eski firmware payload: uid veya id anahtarı
      final legacy = BleWifiState.fromPayload(
        '{"uid":"240AC4E2E001","wifi_connected":false,"provisioning":true}',
      );
      expect(legacy.deviceUid, equals('240AC4E2E001'));

      // UID bulunmayan boş payload, fallbackUid ile kurtarılır
      final fallback = BleWifiState.fromPayload(
        '{"wifi_connected":false,"provisioning":true}',
        fallbackUid: '240AC4E2E001',
      );
      expect(fallback.deviceUid, equals('240AC4E2E001'));

      // copyWith çalışır
      final updated = fallback.copyWith(wifiConnected: true, ip: '192.168.1.100');
      expect(updated.wifiConnected, isTrue);
      expect(updated.ip, equals('192.168.1.100'));
      expect(updated.deviceUid, equals('240AC4E2E001'));
    });
  });
}
