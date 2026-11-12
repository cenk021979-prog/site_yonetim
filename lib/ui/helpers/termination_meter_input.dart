import 'package:site_kapi_kontrol/models/termination_preview_model.dart';
import 'package:site_kapi_kontrol/models/vehicle_record.dart' show crmDateParam;

/// Boş okuma isteğe bağlıdır; girilmiş hatalı bir endeks sessizce atılmaz.
List<Map<String, dynamic>> terminationMeterReadings({
  required List<TerminationMeter> meters,
  required Map<int, String> values,
  required DateTime readingDate,
}) {
  final readings = <Map<String, dynamic>>[];
  for (final meter in meters) {
    final text = (values[meter.id] ?? '').trim();
    if (text.isEmpty) continue;
    final value = double.tryParse(text.replaceAll(',', '.'));
    if (value == null || !value.isFinite || value < 0) {
      throw FormatException(
        '${meter.kindLabel}: geçerli, sıfır veya daha büyük bir son endeks girin.',
      );
    }
    if (meter.lastReadingValue != null && value < meter.lastReadingValue!) {
      throw FormatException(
        '${meter.kindLabel}: son endeks önceki okumadan küçük olamaz.',
      );
    }
    readings.add({
      'meterId': meter.id,
      'readingValue': value,
      'readingDate': crmDateParam(readingDate),
    });
  }
  return readings;
}
