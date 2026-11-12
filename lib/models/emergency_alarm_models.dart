// Site içi alarm sözleşmesi. Telefon rehberi modellerinden ayrı tutulur.
int _number(Object? value) =>
    value is num ? value.toInt() : int.tryParse('$value') ?? 0;
String? _text(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

class EmergencyElevator {
  const EmergencyElevator({
    required this.id,
    required this.name,
    this.location,
    this.blockId,
    this.blockName,
  });
  factory EmergencyElevator.fromJson(Map<String, dynamic> json) =>
      EmergencyElevator(
        id: _number(json['id']),
        name: _text(json['name']) ?? 'Asansör',
        location: _text(json['location']),
        blockId: json['block_id'] == null ? null : _number(json['block_id']),
        blockName: _text(json['block_name']),
      );
  final int id;
  final String name;
  final String? location;
  final int? blockId;
  final String? blockName;
}

class EmergencyLocation {
  const EmergencyLocation({required this.id, required this.name});
  factory EmergencyLocation.fromJson(Map<String, dynamic> json) =>
      EmergencyLocation(
        id: _text(json['id']) ?? '',
        name: _text(json['name']) ?? 'Konum',
      );
  final String id;
  final String name;
  int? get blockId => id.startsWith('block:')
      ? int.tryParse(id.substring('block:'.length))
      : null;
}

class EmergencyAlarm {
  const EmergencyAlarm({
    required this.id,
    required this.siteCode,
    required this.kind,
    this.siteName = '',
    this.equipmentName,
    this.location,
    this.createdByName,
    this.scope,
    this.createdAt,
    this.status = 'open',
    this.soundEnabled = false,
  });
  factory EmergencyAlarm.fromJson(Map<String, dynamic> json) => EmergencyAlarm(
    id: _number(json['id']),
    siteCode: _number(json['site_code']),
    kind: _text(json['kind']) ?? '',
    siteName: _text(json['site_name']) ?? '',
    equipmentName: _text(json['equipment_name']),
    location: _text(json['location']),
    createdByName: _text(json['created_by_name']),
    scope: _text(json['scope']),
    createdAt: DateTime.tryParse('${json['created_at']}'),
    status: _text(json['status']) ?? 'open',
    soundEnabled: json['sound_enabled'] == true,
  );
  final int id;
  final int siteCode;
  final String kind;
  final String siteName;
  final String? equipmentName;
  final String? location;
  final String? createdByName;
  final String? scope;
  final DateTime? createdAt;
  final String status;
  final bool soundEnabled;
  String get title =>
      kind == 'elevator' ? 'Asansör: ${equipmentName ?? 'Asansör'}' : 'Yangın';
}

class EmergencyAlarmFeed {
  const EmergencyAlarmFeed({
    this.alarms = const [],
    this.canReceive = false,
    this.canSound = false,
  });
  factory EmergencyAlarmFeed.fromJson(Map<String, dynamic> json) =>
      EmergencyAlarmFeed(
        alarms: [
          for (final row
              in json['alarms'] is List ? json['alarms'] as List : const [])
            if (row is Map<String, dynamic>) EmergencyAlarm.fromJson(row),
        ].where((a) => a.id > 0).toList(),
        canReceive: json['can_receive'] == true,
        canSound: json['can_sound'] == true,
      );
  final List<EmergencyAlarm> alarms;
  final bool canReceive;
  final bool canSound;
}

class EmergencyAlarmReceipt {
  const EmergencyAlarmReceipt({
    required this.alarm,
    this.securityAssigned = 0,
    this.serviceAssigned = 0,
    this.managerNotified = 0,
    this.residentAssigned = 0,
    this.warnings = const [],
  });
  factory EmergencyAlarmReceipt.fromJson(Map<String, dynamic> json) {
    final delivery = json['delivery'] is Map<String, dynamic>
        ? json['delivery'] as Map<String, dynamic>
        : const <String, dynamic>{};
    return EmergencyAlarmReceipt(
      alarm: EmergencyAlarm.fromJson(
        json['alarm'] is Map<String, dynamic>
            ? json['alarm'] as Map<String, dynamic>
            : const {},
      ),
      securityAssigned: _number(delivery['security_assigned']),
      serviceAssigned: _number(delivery['service_assigned']),
      managerNotified: _number(delivery['manager_notified']),
      residentAssigned: _number(delivery['resident_assigned']),
      warnings: [
        for (final value
            in delivery['warnings'] is List
                ? delivery['warnings'] as List
                : const [])
          if (value is String) value,
      ],
    );
  }
  final EmergencyAlarm alarm;
  final int securityAssigned;
  final int serviceAssigned;
  final int managerNotified;
  final int residentAssigned;
  final List<String> warnings;
  List<String> get warningMessages => warnings
      .map(
        (code) => switch (code) {
          'NO_SECURITY_ACCOUNT' => 'Güvenlik için alarm alıcısı atanmamış.',
          'NO_SERVICE_ACCOUNT' ||
          'NO_ELEVATOR_SERVICE_ACCOUNT' ||
          'NO_ELIGIBLE_SERVICE_ACCOUNT' =>
            'Anlaşmalı asansör servisi için uygulama hesabı atanmamış.',
          'NO_ELEVATOR_VENDOR' =>
            'Asansör için anlaşmalı servis firması bulunamadı. Yönetim firma ve sözleşme kaydını kontrol etmeli.',
          'NO_MANAGER_ACCOUNT' => 'Yönetici bildirim hesabı bulunamadı.',
          'NO_RESIDENT_ACCOUNT' =>
            'Seçilen kapsamda alarm atanabilen daire hesabı bulunamadı.',
          'MANAGER_PUSH_UNAVAILABLE' || 'PUSH_UNAVAILABLE' =>
            'Yönetici telefon bildirimi kullanılamıyor; uygulama içi kayıt korunur.',
          _ =>
            'Bazı alıcılara bildirim atanamadı. Yönetim alarm alıcılarını kontrol etmeli.',
        },
      )
      .toSet()
      .toList();
}

class EmergencyAlarmHistoryPage {
  const EmergencyAlarmHistoryPage({
    this.alarms = const [],
    this.hasMore = false,
  });
  final List<EmergencyAlarm> alarms;
  final bool hasMore;
}
