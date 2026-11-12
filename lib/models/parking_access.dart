import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmInt;

List<Map<String, dynamic>> parkingRows(Object? raw) => [
  if (raw is List)
    for (final r in raw)
      if (r is Map) Map<String, dynamic>.from(r),
];

class ParkingOverview {
  const ParkingOverview({
    this.enabled = false,
    this.capacity,
    this.photoEnabled = false,
    this.total = 0,
    this.apartments = const [],
    this.reservations = const [],
    this.notice = '',
  });
  factory ParkingOverview.fromJson(Map<String, dynamic> json) {
    final policy = json['policy'] is Map ? json['policy'] as Map : const {};
    return ParkingOverview(
      enabled: policy['enabled'] == true,
      capacity: policy['capacity'] == null ? null : crmInt(policy['capacity']),
      photoEnabled: policy['registration_photo_enabled'] == true,
      total: crmInt(json['total']),
      apartments: parkingRows(json['apartments']),
      reservations: parkingRows(json['reservations']),
      notice: json['notice']?.toString() ?? '',
    );
  }
  final bool enabled;
  final int? capacity;
  final bool photoEnabled;
  final int total;
  final List<Map<String, dynamic>> apartments;
  final List<Map<String, dynamic>> reservations;
  final String notice;
}
