// Acil durum akışı (sunucu 107) uçları: sitelerin adresi + asansör bakım firması ve yöneticinin firma kaydı. Kurallar diğer modül uçlarıyla
// aynı: mutasyon yeniden denenmez, 401 oturum bitişidir. Telefon numarası günlüğe YAZILMAZ.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:site_kapi_kontrol/models/emergency_models.dart';
import 'package:site_kapi_kontrol/models/emergency_alarm_models.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/auth_service.dart';

class EmergencyService {
  EmergencyService({required this.authService, http.Client? client})
    : _client = client ?? http.Client();

  final AuthService authService;
  final http.Client _client;

  String get _base => authService.api.baseUrl.replaceAll(RegExp(r'/+$'), '');

  Future<List<EmergencySite>> listAlarmSites() async {
    final json = await _send('GET', '/app/emergency/sites');
    return [
      for (final row
          in json['sites'] is List ? json['sites'] as List : const [])
        if (row is Map<String, dynamic>) EmergencySite.fromJson(row),
    ];
  }

  Future<List<EmergencyElevator>> listElevators(int siteCode) async {
    final json = await _send('GET', '/app/emergency/sites/$siteCode/elevators');
    final raw = json['elevators'];
    if (raw is! List ||
        raw.any(
          (row) =>
              row is! Map<String, dynamic> ||
              EmergencyElevator.fromJson(row).id <= 0,
        )) {
      throw ApiException(
        'Asansör listesi doğrulanamadı. Yeniden deneyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
    return [
      for (final row in raw)
        if (row is Map<String, dynamic>) EmergencyElevator.fromJson(row),
    ];
  }

  Future<List<EmergencyLocation>> listLocations(int siteCode) async {
    final json = await _send('GET', '/app/emergency/sites/$siteCode/locations');
    final raw = json['locations'];
    if (raw is! List ||
        raw.isEmpty ||
        raw.any(
          (row) =>
              row is! Map<String, dynamic> ||
              !RegExp(r'^(site|block:[1-9][0-9]*)$').hasMatch('${row['id']}'),
        )) {
      throw ApiException(
        'Yangın konumları doğrulanamadı. Yeniden deneyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
    return [
      for (final row in raw)
        if (row is Map<String, dynamic>) EmergencyLocation.fromJson(row),
    ];
  }

  Future<EmergencyAlarmReceipt> createAlarm({
    required int siteCode,
    required String kind,
    int? equipmentId,
    String? locationId,
    required String idempotencyKey,
  }) async {
    final receipt = EmergencyAlarmReceipt.fromJson(
      await _send(
        'POST',
        '/app/emergency/alarms',
        body: {
          'site_code': siteCode,
          'kind': kind,
          'equipment_id': ?equipmentId,
          'location_id': ?locationId,
          'idempotency_key': idempotencyKey,
        },
      ),
    );
    if (receipt.alarm.id <= 0 ||
        receipt.alarm.siteCode != siteCode ||
        receipt.alarm.kind != kind) {
      throw ApiException(
        'Sunucunun alarm kaydı doğrulanamadı. Aynı bildirimi tekrar deneyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
    return receipt;
  }

  Future<EmergencyAlarmFeed> alarmFeed() async {
    final data = await _send('GET', '/app/emergency/alarms');
    if (data['alarms'] is! List ||
        data['can_receive'] is! bool ||
        data['can_sound'] is! bool) {
      throw ApiException(
        'Alarm listesi doğrulanamadı. Bağlantıyı yenileyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
    return EmergencyAlarmFeed.fromJson(data);
  }

  Future<void> acknowledgeAlarm(int id) async {
    await _alarmAction(id, 'ack');
  }

  Future<EmergencyAlarmHistoryPage> alarmHistory({int? beforeId}) async {
    final data = await _send(
      'GET',
      '/app/emergency/alarms/history${beforeId == null ? '' : '?before_id=$beforeId'}',
    );
    if (data['alarms'] is! List || data['has_more'] is! bool) {
      throw ApiException(
        'Alarm geçmişi doğrulanamadı. Yeniden deneyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
    return EmergencyAlarmHistoryPage(
      alarms: [
        for (final row in data['alarms'] as List)
          if (row is Map<String, dynamic>) EmergencyAlarm.fromJson(row),
      ].where((a) => a.id > 0).toList(),
      hasMore: data['has_more'] == true,
    );
  }

  Future<void> noteAlarmReceived(int id) async {
    await _alarmAction(id, 'received');
  }

  Future<void> noteAlarmPlayed(int id) async {
    await _alarmAction(id, 'played');
  }

  Future<void> _alarmAction(int id, String action) async {
    final data = await _send(
      'POST',
      '/app/emergency/alarms/$id/$action',
      body: {},
    );
    if (data['ok'] != true) {
      throw ApiException(
        'Alarm işlemi doğrulanamadı. Tekrar deneyin.',
        code: 'ALARM_RESULT_UNCERTAIN',
      );
    }
  }

  Future<Map<String, dynamic>> responders(int siteCode) =>
      _send('GET', '/manager/sites/$siteCode/emergency/responders');
  Future<void> saveResponders(
    int siteCode,
    List<Map<String, dynamic>> rows,
  ) async {
    await _send(
      'PUT',
      '/manager/sites/$siteCode/emergency/responders',
      body: {'responders': rows},
    );
  }

  void close() => _client.close();

  /// Çağıranın bağlı olduğu sitelerin acil durum bilgisi (kapsam sunucuda hesaplanır).
  Future<List<EmergencySite>> listSites() async {
    final json = await _send('GET', '/app/emergency');
    final raw = json['sites'];
    if (raw is! List) return const <EmergencySite>[];
    return <EmergencySite>[
      for (final entry in raw)
        if (entry is Map<String, dynamic>) EmergencySite.fromJson(entry),
    ];
  }

  /// Yönetici: asansör bakım firmasını YERİNE yazar. İkisi de boşsa kayıt silinir. Dönüş: sunucunun temizleyip sakladığı değerler.
  Future<({String? name, String? phone})> saveElevatorFirm(
    int siteCode, {
    String? name,
    String? phone,
  }) async {
    final json = await _send(
      'PUT',
      '/manager/sites/$siteCode/emergency',
      body: <String, dynamic>{
        'elevator_firm_name': name,
        'elevator_firm_phone': phone,
      },
    );
    String? text(Object? value) =>
        value is String && value.trim().isNotEmpty ? value.trim() : null;
    return (
      name: text(json['elevator_firm_name']),
      phone: text(json['elevator_firm_phone']),
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = authService.session?.token;
    if (token == null) throw ApiException('Oturum açmanız gerekmektedir.');
    final request = http.Request(method, Uri.parse('$_base$path'))
      ..headers.addAll(<String, String>{
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      });
    if (body != null) request.body = jsonEncode(body);
    final http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on Exception {
      throw ApiException(
        'Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edip tekrar deneyin.',
      );
    }
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) payload = decoded;
    } on FormatException {
      // JSON olmayan gövde (araya giren katman): aşağıda genel hata.
    }
    if (response.statusCode == 200 || response.statusCode == 201) {
      return payload;
    }
    final message = payload['error'];
    final error = ApiException(
      message is String && message.trim().isNotEmpty
          ? message
          : 'İşlem başarısız (${response.statusCode}).',
      statusCode: response.statusCode,
      code: payload['code'] is String ? payload['code'] as String : null,
      payload: payload.isEmpty ? null : payload,
    );
    if (error.invalidatesSession) {
      unawaited(authService.refreshSession(force: true));
    }
    throw error;
  }
}
