import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/termination_preview_model.dart';
import 'package:site_kapi_kontrol/ui/helpers/termination_meter_input.dart';

void main() {
  const meter = TerminationMeter(
    id: 7,
    kind: 'water',
    serialNo: 'SU7',
    lastReadingValue: 40,
  );
  test(
    'isteğe bağlı boş okuma atlanır, ondalık virgül ve ISO tarih korunur',
    () {
      final readings = terminationMeterReadings(
        meters: [
          meter,
          const TerminationMeter(id: 8, kind: 'heat', serialNo: 'ISI8'),
        ],
        values: {7: '42,75', 8: ' '},
        readingDate: DateTime(2026, 11, 12),
      );
      expect(readings, [
        {'meterId': 7, 'readingValue': 42.75, 'readingDate': '2026-11-12'},
      ]);
    },
  );
  for (final value in ['abc', 'NaN', 'Infinity', '-1', '39']) {
    test('hatalı veya geriye giden endeks sessizce atlanmaz: $value', () {
      expect(
        () => terminationMeterReadings(
          meters: [meter],
          values: {7: value},
          readingDate: DateTime(2026, 11, 12),
        ),
        throwsFormatException,
      );
    });
  }
}
