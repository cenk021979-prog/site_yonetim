import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/ble_wifi_provision_service.dart';

class _BleRadio implements FlutterReactiveBle {
  List<DiscoveredDevice> advertisements = [];
  List<Uuid>? scanFilter;
  List<QualifiedCharacteristic> reads = [];
  List<List<int>> writes = [];
  String payload = '{"device_uid":"FFEEDDCCBBAA","provisioning":true}';
  bool missingService = false;

  @override
  Stream<DiscoveredDevice> scanForDevices({
    required List<Uuid> withServices,
    ScanMode scanMode = ScanMode.balanced,
    bool requireLocationServicesEnabled = true,
  }) {
    scanFilter = withServices;
    return Stream.fromIterable(advertisements);
  }

  @override
  Stream<ConnectionStateUpdate> connectToDevice({
    required String id,
    Map<Uuid, List<Uuid>>? servicesWithCharacteristicsToDiscover,
    Duration? connectionTimeout,
  }) => Stream.value(
    ConnectionStateUpdate(
      deviceId: id,
      connectionState: DeviceConnectionState.connected,
      failure: null,
    ),
  );

  @override
  Future<int> requestMtu({required String deviceId, required int mtu}) async =>
      mtu;

  @override
  Future<List<int>> readCharacteristic(
    QualifiedCharacteristic characteristic,
  ) async {
    reads.add(characteristic);
    if (missingService) throw StateError('Required GATT service absent');
    return utf8.encode(payload);
  }

  @override
  Future<void> writeCharacteristicWithResponse(
    QualifiedCharacteristic characteristic, {
    required List<int> value,
  }) async => writes.add(value);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadyProvisioner extends BleWifiProvisionService {
  _ReadyProvisioner(_BleRadio radio) : super(ble: radio);

  @override
  Future<void> ensureReady() async {}
}

DiscoveredDevice _advert(String id, String name, {bool service = false}) =>
    DiscoveredDevice(
      id: id,
      name: name,
      serviceData: const {},
      serviceUuids: service ? [Uuid.parse(bleWifiServiceUuid)] : [],
      manufacturerData: Uint8List(0),
      rssi: -50,
    );

const _device = BleProvisionDevice(
  id: '11:22:33:44:55:66',
  name: 'AHBU',
  rssi: -50,
);

void main() {
  test(
    'AHBU/SmartKey adları ve adsız doğru servis donanım filtresi olmadan bulunur',
    () async {
      final radio = _BleRadio()
        ..advertisements = [
          _advert('old', 'AHBU'),
          _advert('new', 'SmartKeyPa'),
          _advert('anonymous', '', service: true),
          _advert('generic', 'ESP32_C3_GATE'),
          _advert('unrelated', 'Mi Band 7'),
        ];
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      final devices = await service.scanDevices(
        duration: const Duration(milliseconds: 10),
      );
      expect(radio.scanFilter, isEmpty);
      expect(
        devices.map((d) => d.id),
        unorderedEquals(['old', 'new', 'anonymous', 'generic']),
      );
      expect(
        devices.singleWhere((d) => d.id == 'anonymous').name,
        'SmartKey/AHBU (anonymous)',
      );
    },
  );

  test(
    'Genel ESP32 adayının özel kurulum servisi yoksa bağlantı kapanır ve bilgi yazılmaz',
    () async {
      final radio = _BleRadio()..missingService = true;
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      await expectLater(
        service.connect(_device),
        throwsA(isA<BleProvisionException>()),
      );
      expect(radio.reads.single.serviceId, Uuid.parse(bleWifiServiceUuid));
      expect(radio.reads.single.characteristicId, Uuid.parse(bleWifiStateUuid));
      expect(radio.writes, isEmpty);
      await expectLater(
        service.readState(),
        throwsA(isA<BleProvisionException>()),
      );
    },
  );

  test(
    'Cihazın durum UID alanı BLE adresinden farklıysa firmware kimliği seçilir',
    () async {
      final radio = _BleRadio();
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      expect((await service.connect(_device)).deviceUid, 'FFEEDDCCBBAA');
    },
  );

  test('Boş device_uid dolu eski uid alanını gölgelemez', () {
    final state = BleWifiState.fromPayload(
      '{"device_uid":" ","uid":"FFEEDDCCBBAA"}',
    );
    expect(state.deviceUid, 'FFEEDDCCBBAA');
  });

  test(
    'UID eksikse farklı olabilecek BLE MAC üzerinden MQTT kimliği türetilmez',
    () async {
      final radio = _BleRadio()..payload = '{"provisioning":true}';
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      await expectLater(
        service.connect(_device),
        throwsA(isA<BleProvisionException>()),
      );
      expect(radio.writes, isEmpty);
    },
  );

  test('MAC benzeri yalın reklam adı da firmware UID yerine kullanılmaz', () async {
    final radio = _BleRadio()..payload = '{"provisioning":true}';
    final service = _ReadyProvisioner(radio);
    addTearDown(service.dispose);
    await expectLater(service.connect(const BleProvisionDevice(
      id: '11:22:33:44:55:66', name: '11:22:33:44:55:66', rssi: -50,
    )), throwsA(isA<BleProvisionException>()));
  });

  test(
    'Eski cihaz geçerli durum JSONu ve tam AHBU adıyla UID sağlayabilir',
    () async {
      final radio = _BleRadio()..payload = '{"provisioning":true}';
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      final state = await service.connect(
        const BleProvisionDevice(
          id: '11:22:33:44:55:66',
          name: 'AHBUFFEEDDCCBBAA',
          rssi: -50,
        ),
      );
      expect(state.deviceUid, 'FFEEDDCCBBAA');
    },
  );

  test(
    'Kısaltılmış UID içeren reklam adı tamamlanmış kimlik sanılmaz',
    () async {
      final radio = _BleRadio()..payload = '{"provisioning":true}';
      final service = _ReadyProvisioner(radio);
      addTearDown(service.dispose);
      await expectLater(
        service.connect(
          const BleProvisionDevice(
            id: '11:22:33:44:55:66',
            name: 'SmartKeyPassFFEEDD',
            rssi: -50,
          ),
        ),
        throwsA(isA<BleProvisionException>()),
      );
    },
  );

  test('Bozuk durum JSONu reklam adıyla başarılı bağlantı sayılmaz', () async {
    final radio = _BleRadio()..payload = 'invalid JSON';
    final service = _ReadyProvisioner(radio);
    addTearDown(service.dispose);
    await expectLater(
      service.connect(
        const BleProvisionDevice(
          id: '11:22:33:44:55:66',
          name: 'AHBUFFEEDDCCBBAA',
          rssi: -50,
        ),
      ),
      throwsA(isA<BleProvisionException>()),
    );
  });
}
