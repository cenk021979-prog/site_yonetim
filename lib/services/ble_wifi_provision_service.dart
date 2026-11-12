import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:permission_handler/permission_handler.dart';

const String bleWifiServiceUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f001';
const String bleWifiStateUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f002';
const String bleWifiCommandUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f003';
const String bleWifiNetworksUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f004';
const String bleWifiResultUuid = '6f64be30-0d46-4f6d-9cd4-4f9d08b5f005';

/// Kurulum yayınındaki cihaz adı önekleri. Yeni firmware `SmartKeyPass<UID>` yayınlar; 128-bit servis UUID'si
/// reklam paketinde yer kapladığından ad orada kısaltılabilir (`SmartKey…`), bu yüzden önek `SmartKey`dir.
/// Sahadaki eski kartlar (yeni firmware yüklenene kadar) `AHBU<UID>` yayınlar. İkisi de tanınır.
const List<String> bleProvisionDeviceNamePrefixes = <String>[
  'SmartKey',
  'SmartKeyPass',
  'AHBU',
  'SKP',
  'KAPI',
  'ESP32',
];

/// Tarama adayıdır; kurulum servisi ve cihaz kimliği bağlantıdan sonra okunur.
bool isBleProvisionDeviceName(String name) {
  final String upper = name.trim().toUpperCase();
  if (upper.isEmpty) {
    return false;
  }
  for (final String prefix in bleProvisionDeviceNamePrefixes) {
    if (upper.startsWith(prefix.toUpperCase())) {
      return true;
    }
  }
  if (upper.contains('AHBU') ||
      upper.contains('SMARTKEY') ||
      upper.contains('SKP')) {
    return true;
  }
  return false;
}

/// BLE cihaz adı veya MAC adresinden hex kimlik adayı ayıklar.
/// [deviceId] ile bulunan adres, firmware UID'sinin doğrulandığı anlamına gelmez.
/// Kurulum akışı bu geri dönüşü kullanmaz; BLE MAC adresi eFuse UID'den farklı olabilir.
/// Örn: "AHBU240AC4E2E001" -> "240AC4E2E001", "AHBU-240AC4E2E001" -> "240AC4E2E001",
/// "SmartKeyPass240AC4E2E001" -> "240AC4E2E001", "24:0A:C4:E2:E0:01" -> "240AC4E2E001".
String extractBleDeviceUid(String name, {String? deviceId}) {
  final String trimmedName = name.trim();
  final Match? prefixMatch = RegExp(
    r'(?:AHBU|SmartKey|SmartKeyPass|SKP|ESP32|KAPI)[-_:]?([0-9A-Fa-f]{6,16})',
    caseSensitive: false,
  ).firstMatch(trimmedName);
  if (prefixMatch != null && prefixMatch.group(1) != null) {
    return prefixMatch.group(1)!.toUpperCase();
  }

  final String cleanName = trimmedName.replaceAll('-', '').replaceAll(':', '');
  if (RegExp(r'^[0-9A-Fa-f]{8,16}$').hasMatch(cleanName)) {
    return cleanName.toUpperCase();
  }

  if (deviceId != null && deviceId.trim().isNotEmpty) {
    final String cleanMac = deviceId
        .replaceAll(':', '')
        .replaceAll('-', '')
        .trim();
    if (RegExp(r'^[0-9A-Fa-f]{12}$').hasMatch(cleanMac)) {
      return cleanMac.toUpperCase();
    }
  }

  return '';
}

class BleProvisionException implements Exception {
  const BleProvisionException(this.message);

  final String message;

  @override
  String toString() => message;
}

class BleProvisionDevice {
  const BleProvisionDevice({
    required this.id,
    required this.name,
    required this.rssi,
  });

  final String id;
  final String name;
  final int rssi;
}

class BleWifiState {
  const BleWifiState({
    required this.deviceUid,
    required this.wifiConnected,
    required this.provisioning,
    required this.hasCredentials,
    required this.mqttConfigured,
    required this.ssid,
    required this.ip,
  });

  final String deviceUid;
  final bool wifiConnected;
  final bool provisioning;
  final bool hasCredentials;
  final bool mqttConfigured;
  final String ssid;
  final String ip;

  factory BleWifiState.fromPayload(String payload, {String? fallbackUid}) {
    final Map<String, dynamic> json = _decodeJsonMap(payload);
    if (json.isEmpty) {
      throw const BleProvisionException(
        'Cihazın kurulum durumu okunamadı. Bağlantıyı yenileyip tekrar deneyin.',
      );
    }
    String uid = '';
    for (final key in const ['device_uid', 'uid', 'id', 'deviceUid']) {
      final Object? value = json[key];
      if (value is! String && value is! num) continue;
      final String candidate = value.toString().trim();
      if (candidate.isNotEmpty) {
        uid = candidate;
        break;
      }
    }
    if (uid.isEmpty && fallbackUid != null && fallbackUid.trim().isNotEmpty) {
      uid = fallbackUid.trim();
    }
    return BleWifiState(
      deviceUid: uid,
      wifiConnected: json['wifi_connected'] == true,
      provisioning: json['provisioning'] == true,
      hasCredentials: json['has_credentials'] == true,
      mqttConfigured: json['mqtt_configured'] == true,
      ssid: (json['ssid'] ?? '').toString(),
      ip: (json['ip'] ?? '').toString(),
    );
  }

  BleWifiState copyWith({
    String? deviceUid,
    bool? wifiConnected,
    bool? provisioning,
    bool? hasCredentials,
    bool? mqttConfigured,
    String? ssid,
    String? ip,
  }) {
    return BleWifiState(
      deviceUid: deviceUid ?? this.deviceUid,
      wifiConnected: wifiConnected ?? this.wifiConnected,
      provisioning: provisioning ?? this.provisioning,
      hasCredentials: hasCredentials ?? this.hasCredentials,
      mqttConfigured: mqttConfigured ?? this.mqttConfigured,
      ssid: ssid ?? this.ssid,
      ip: ip ?? this.ip,
    );
  }
}

class BleWifiNetwork {
  const BleWifiNetwork({
    required this.ssid,
    required this.rssi,
    required this.secure,
  });

  final String ssid;
  final int rssi;
  final bool secure;
}

class BleWifiResult {
  const BleWifiResult({required this.status, required this.message});

  final String status;
  final String message;

  bool get isFailure => status == 'error' || status == 'failed';
  bool get isScanComplete => status == 'scan_complete';
  bool get isProvisionAccepted =>
      status == 'connected' || status == 'restarting' || status == 'saved';

  factory BleWifiResult.fromPayload(String payload) {
    final Map<String, dynamic> json = _decodeJsonMap(payload);
    return BleWifiResult(
      status: (json['status'] ?? 'idle').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

Map<String, dynamic> _decodeJsonMap(String payload) {
  if (payload.trim().isEmpty) {
    return <String, dynamic>{};
  }

  try {
    final Object? decoded = jsonDecode(payload);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
  } catch (_) {
    return <String, dynamic>{};
  }
  return <String, dynamic>{};
}

class BleWifiProvisionService {
  BleWifiProvisionService({FlutterReactiveBle? ble}) : _bleOverride = ble;

  final FlutterReactiveBle? _bleOverride;

  /// FlutterReactiveBle yalnızca ilk kullanımda (desteklenen platformda: Android/iOS) oluşturulur.
  /// Kurucu, platform uygulaması olmayan masaüstünde (Windows/Linux) asenkron
  /// `UnimplementedError: initialize() has not been implemented` fırlatıp yakalanmamış istisna olur;
  /// bu yüzden sayfa açılırken (kurucuda) değil, `ensureReady()` desteği doğruladıktan sonra yaratılır.
  late final FlutterReactiveBle _ble = _bleOverride ?? FlutterReactiveBle();
  final Uuid _serviceUuid = Uuid.parse(bleWifiServiceUuid);
  final Uuid _stateUuid = Uuid.parse(bleWifiStateUuid);
  final Uuid _commandUuid = Uuid.parse(bleWifiCommandUuid);
  final Uuid _networksUuid = Uuid.parse(bleWifiNetworksUuid);
  final Uuid _resultUuid = Uuid.parse(bleWifiResultUuid);

  StreamSubscription<ConnectionStateUpdate>? _connectionSubscription;
  String? _deviceId;
  String? _connectedDeviceName;

  bool get isSupportedPlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  Future<void> ensureReady() async {
    if (!isSupportedPlatform) {
      throw const BleProvisionException(
        'Bluetooth ile Wi-Fi kurulumu yalnizca Android ve iPhone cihazlarda destekleniyor.',
      );
    }

    await _requestPermissions();

    // Give native BLE bridge a brief moment to update its status after permission prompt
    await Future<void>.delayed(const Duration(milliseconds: 300));

    BleStatus status = _ble.status;
    if (status != BleStatus.ready && status != BleStatus.poweredOff) {
      try {
        status = await _ble.statusStream
            .firstWhere(
              (BleStatus value) =>
                  value == BleStatus.ready ||
                  value == BleStatus.poweredOff ||
                  value == BleStatus.locationServicesDisabled ||
                  value == BleStatus.unsupported,
            )
            .timeout(const Duration(milliseconds: 1500));
      } catch (_) {
        status = _ble.status;
      }
    }

    if (status == BleStatus.ready) {
      return;
    }

    switch (status) {
      case BleStatus.ready:
        return;
      case BleStatus.poweredOff:
        throw const BleProvisionException(
          'Bluetooth kapali. Once Bluetooth acin.',
        );
      case BleStatus.locationServicesDisabled:
        throw const BleProvisionException(
          'Konum servislerini acip tekrar deneyin.',
        );
      case BleStatus.unauthorized:
        final bool permissionsGranted = await _checkPermissionsGranted();
        if (permissionsGranted) {
          return;
        }
        throw const BleProvisionException(
          'Bluetooth izni verilmedi. Uygulama izinlerini acin.',
        );
      case BleStatus.unsupported:
        throw const BleProvisionException(
          'Bu cihaz Bluetooth LE desteklemiyor.',
        );
      case BleStatus.unknown:
        return;
    }
  }

  Future<bool> _checkPermissionsGranted() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final scan = await Permission.bluetoothScan.status;
      final connect = await Permission.bluetoothConnect.status;
      if (scan.isGranted ||
          scan.isLimited ||
          connect.isGranted ||
          connect.isLimited) {
        return true;
      }
      final location = await Permission.locationWhenInUse.status;
      final bt = await Permission.bluetooth.status;
      return location.isGranted || bt.isGranted;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final bt = await Permission.bluetooth.status;
      return bt.isGranted || bt.isLimited;
    }
    return true;
  }

  Future<void> _requestPermissions() async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final scanStatus = await Permission.bluetoothScan.request();
      final connectStatus = await Permission.bluetoothConnect.request();

      final isScanGranted = scanStatus.isGranted || scanStatus.isLimited;
      final isConnectGranted =
          connectStatus.isGranted || connectStatus.isLimited;

      if (!isScanGranted && !isConnectGranted) {
        final locationStatus = await Permission.locationWhenInUse.request();
        final bluetoothStatus = await Permission.bluetooth.request();
        if (!locationStatus.isGranted && !bluetoothStatus.isGranted) {
          throw const BleProvisionException(
            'Bluetooth tarama ve baglanti izinleri zorunludur.',
          );
        }
      }
      return;
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final PermissionStatus bluetoothStatus = await Permission.bluetooth
          .request();
      if (!bluetoothStatus.isGranted && !bluetoothStatus.isLimited) {
        throw const BleProvisionException('Bluetooth izni verilmedi.');
      }
    }
  }

  Future<List<BleProvisionDevice>> scanDevices({
    Duration duration = const Duration(seconds: 6),
  }) async {
    await ensureReady();

    final Map<String, BleProvisionDevice> devices =
        <String, BleProvisionDevice>{};
    Object? scanError;

    // Sahadaki eski AHBU cihazlarinda 128-bit servis UUID'si reklam paketindeki 31 bayt siniri nedeniyle
    // yalniz Scan Response icinde yer alabilir veya bazi Android surumlerinde donanim filtreleri
    // Scan Response'u yutar. Bu yuzden tarama tum yayinlara acik yapilir (withServices bos), eslesme Dart'ta yapilir.
    final StreamSubscription<DiscoveredDevice> subscription = _ble
        .scanForDevices(
          withServices: const <Uuid>[],
          scanMode: ScanMode.lowLatency,
          requireLocationServicesEnabled: false,
        )
        .listen(
          (DiscoveredDevice device) {
            final String name = device.name.trim();
            final bool hasMatchingName = isBleProvisionDeviceName(name);
            final bool hasMatchingService = device.serviceUuids.contains(
              _serviceUuid,
            );
            if (!hasMatchingName && !hasMatchingService) {
              return;
            }
            final String displayName = name.isNotEmpty
                ? name
                : (hasMatchingService
                      ? 'SmartKey/AHBU (${device.id})'
                      : device.id);
            devices[device.id] = BleProvisionDevice(
              id: device.id,
              name: displayName,
              rssi: device.rssi,
            );
          },
          onError: (Object error, StackTrace stackTrace) {
            scanError = error;
          },
        );

    await Future<void>.delayed(duration);
    await subscription.cancel();

    if (scanError != null) {
      throw BleProvisionException(_messageFromError(scanError!));
    }

    final List<BleProvisionDevice> values = devices.values.toList()
      ..sort(
        (BleProvisionDevice left, BleProvisionDevice right) =>
            right.rssi.compareTo(left.rssi),
      );
    return values;
  }

  Future<BleWifiState> connect(BleProvisionDevice device) async {
    await ensureReady();
    await disconnect();

    final Completer<void> completer = Completer<void>();
    _deviceId = device.id;
    _connectedDeviceName = device.name;
    _connectionSubscription = _ble
        .connectToDevice(
          id: device.id,
          servicesWithCharacteristicsToDiscover: <Uuid, List<Uuid>>{
            _serviceUuid: <Uuid>[
              _stateUuid,
              _commandUuid,
              _networksUuid,
              _resultUuid,
            ],
          },
          connectionTimeout: const Duration(seconds: 12),
        )
        .listen(
          (ConnectionStateUpdate update) {
            if (update.connectionState == DeviceConnectionState.connected &&
                !completer.isCompleted) {
              completer.complete();
            }
            if (update.connectionState == DeviceConnectionState.disconnected) {
              if (!completer.isCompleted) {
                completer.completeError(
                  const BleProvisionException(
                    'Cihaza baglanilamadi veya baglanti koptu.',
                  ),
                );
              }
              _deviceId = null;
              _connectedDeviceName = null;
            }
          },
          onError: (Object error, StackTrace stackTrace) {
            if (!completer.isCompleted) {
              completer.completeError(
                BleProvisionException(_messageFromError(error)),
              );
            }
            _deviceId = null;
            _connectedDeviceName = null;
          },
        );

    try {
      await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw const BleProvisionException(
          'Bluetooth baglantisi zaman asimina ugradi.',
        ),
      );
      try {
        await _ble.requestMtu(deviceId: device.id, mtu: 180);
      } catch (_) {
        // MTU arttirimi zorunlu degil.
      }

      // İsim eşleşmesi yeterli değildir: özel GATT durum karakteristiği okunmalı.
      return await readState();
    } catch (error) {
      await disconnect();
      if (error is BleProvisionException) rethrow;
      throw const BleProvisionException(
        'Cihazın kurulum servisine erişilemedi. Kurulum modunu açıp tekrar deneyin.',
      );
    }
  }

  Future<BleWifiState> readState() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_stateUuid),
    );
    // Kısaltılmış reklam adı veya BLE MAC adresi MQTT kimliği yerine geçmez.
    // Sahadaki firmware cihazUniqueId() ile 12 haneli eFuse UID yayınlar.
    final Match? advertisedUid = RegExp(
      r'^(?:AHBU|SmartKeyPass|SmartKey|SKP|ESP32|KAPI)[-_:]?([0-9A-F]{12})$',
      caseSensitive: false,
    ).firstMatch((_connectedDeviceName ?? '').trim());
    final String fallbackUid = advertisedUid?.group(1)?.toUpperCase() ?? '';
    final BleWifiState state = BleWifiState.fromPayload(
      utf8.decode(raw, allowMalformed: true),
      fallbackUid: fallbackUid,
    );
    if (state.deviceUid.isEmpty) {
      throw const BleProvisionException(
        'Cihaz kimliği okunamadı. Durumu yenileyip tekrar deneyin; Bluetooth adresi cihaz kimliği olarak kullanılamaz.',
      );
    }
    return state;
  }

  Future<BleWifiResult> readResult() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_resultUuid),
    );
    return BleWifiResult.fromPayload(utf8.decode(raw, allowMalformed: true));
  }

  Future<List<BleWifiNetwork>> readNetworks() async {
    final List<int> raw = await _ble.readCharacteristic(
      _qualifiedCharacteristic(_networksUuid),
    );
    final Map<String, dynamic> json = _decodeJsonMap(
      utf8.decode(raw, allowMalformed: true),
    );
    final List<dynamic> items =
        (json['networks'] as List<dynamic>?) ?? <dynamic>[];
    return items
        .whereType<Map<String, dynamic>>()
        .map(
          (Map<String, dynamic> item) => BleWifiNetwork(
            ssid: (item['ssid'] ?? '').toString(),
            rssi: (item['rssi'] as num?)?.toInt() ?? 0,
            secure: item['secure'] == true,
          ),
        )
        .where((BleWifiNetwork item) => item.ssid.isNotEmpty)
        .toList();
  }

  Future<List<BleWifiNetwork>> scanNetworks() async {
    await _ble.writeCharacteristicWithResponse(
      _qualifiedCharacteristic(_commandUuid),
      value: utf8.encode('{"action":"scan"}'),
    );

    BleWifiResult result = const BleWifiResult(status: 'idle', message: '');
    for (int index = 0; index < 20; index += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 350));
      result = await readResult();
      if (result.isFailure) {
        throw BleProvisionException(
          result.message.isEmpty ? 'Wi-Fi taramasi basarisiz.' : result.message,
        );
      }
      if (result.isScanComplete) {
        return readNetworks();
      }
    }

    throw const BleProvisionException('Wi-Fi taramasi zaman asimina ugradi.');
  }

  Future<BleWifiResult> provisionWifi({
    required String ssid,
    required String password,
    required Map<String, dynamic> mqttCredentials,
  }) async {
    if (ssid.trim().isEmpty) {
      throw const BleProvisionException('SSID secimi zorunludur.');
    }

    final String mqttHost = (mqttCredentials['mqtt_host'] ?? '').toString();
    final int mqttPort =
        (mqttCredentials['mqtt_port'] as num?)?.toInt() ?? 8883;
    final String mqttUsername = (mqttCredentials['mqtt_username'] ?? '')
        .toString();
    final String mqttPassword = (mqttCredentials['mqtt_password'] ?? '')
        .toString();

    if (mqttHost.isEmpty || mqttUsername.isEmpty || mqttPassword.isEmpty) {
      throw const BleProvisionException(
        'MQTT cihaz kimligi hazir degil. Once cihazi sirket hesabina kaydedin.',
      );
    }

    final String payload = jsonEncode(<String, Object>{
      'ssid': ssid.trim(),
      'password': password,
      'mqtt_host': mqttHost,
      'mqtt_port': mqttPort,
      'mqtt_username': mqttUsername,
      'mqtt_password': mqttPassword,
    });
    await _ble.writeCharacteristicWithResponse(
      _qualifiedCharacteristic(_commandUuid),
      value: utf8.encode(payload),
    );

    BleWifiResult result = const BleWifiResult(status: 'idle', message: '');
    for (int index = 0; index < 28; index += 1) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        result = await readResult();
      } catch (_) {
        return const BleWifiResult(
          status: 'restarting',
          message:
              'Wi-Fi bilgileri cihaza yazildi. Cihaz yeniden baslatiliyor.',
        );
      }
      if (result.isProvisionAccepted) {
        return BleWifiResult(
          status: result.status,
          message: result.message.isEmpty
              ? 'Wi-Fi bilgileri cihaza yazildi. Cihaz yeniden baslatiliyor.'
              : result.message,
        );
      }
      final BleWifiState state = await readState();
      if (state.wifiConnected) {
        return BleWifiResult(
          status: 'connected',
          message: result.message.isEmpty
              ? 'Wi-Fi baglantisi kaydedildi.'
              : result.message,
        );
      }
      if (result.isFailure) {
        throw BleProvisionException(
          result.message.isEmpty
              ? 'Wi-Fi baglantisi kurulamadi.'
              : result.message,
        );
      }
    }

    throw const BleProvisionException('Wi-Fi baglantisi zaman asimina ugradi.');
  }

  Future<void> disconnect() async {
    await _connectionSubscription?.cancel();
    _connectionSubscription = null;
    _deviceId = null;
    _connectedDeviceName = null;
  }

  Future<void> dispose() async {
    await disconnect();
  }

  QualifiedCharacteristic _qualifiedCharacteristic(Uuid characteristicUuid) {
    final String? deviceId = _deviceId;
    if (deviceId == null) {
      throw const BleProvisionException('Once Bluetooth cihazina baglanin.');
    }

    return QualifiedCharacteristic(
      serviceId: _serviceUuid,
      characteristicId: characteristicUuid,
      deviceId: deviceId,
    );
  }

  String _messageFromError(Object error) {
    final String message = error.toString();
    if (message.isEmpty) {
      return 'Bluetooth islemi basarisiz oldu.';
    }
    return message;
  }
}
