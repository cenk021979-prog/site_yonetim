import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/plate_statistics.dart';
import 'package:site_kapi_kontrol/services/plate_recognition_api.dart';
import 'package:site_kapi_kontrol/ui/dialogs/plate_statistics_dialog.dart';

class _Service extends Fake implements PlateRecognitionService {
  int? requestedGate;
  String? requestedAnchor;
  bool fail = false;
  @override
  Future<PlateStatistics> statistics(
    int site, {
    int? gateId,
    String? anchor,
  }) async {
    requestedGate = gateId;
    requestedAnchor = anchor;
    if (fail) throw StateError('offline');
    final selected = DateTime.parse(anchor ?? '2026-11-08');
    final day = DateTime.utc(selected.year, selected.month, selected.day);
    final week = day.subtract(Duration(days: day.weekday - 1));
    final month = DateTime.utc(selected.year, selected.month);
    final bounds = {
      'day': [day, day.add(const Duration(days: 1))],
      'week': [week, week.add(const Duration(days: 7))],
      'month': [month, DateTime.utc(selected.year, selected.month + 1)],
    };
    return PlateStatistics.fromJson({
      'server_time': '2026-11-08T12:00:00Z',
      'gate_id': gateId,
      'periods': {
        for (final period in bounds.entries)
          period.key: {
            'entries': 137,
            'exits': 8,
            'unknown': 2,
            'starts_at': period.value[0]
                .subtract(const Duration(hours: 3))
                .toIso8601String(),
            'ends_at': period.value[1]
                .subtract(const Duration(hours: 3))
                .toIso8601String(),
          },
      },
    });
  }
}

void main() {
  test(
    'istemcinin ileri/geri duvar saati yerine sunucu saati ve monoton süre kullanılır',
    () {
      var elapsed = Duration.zero;
      final start = DateTime.parse('2040-01-01T21:00:00Z');
      final end = DateTime.parse('2040-01-02T21:00:00Z');
      final day = PlatePeriodStatistics(
        entries: 137,
        exits: 8,
        unknown: 0,
        startsAt: start,
        endsAt: end,
      );
      // Deliberately years away from the device clock: today still means server day.
      final stats = PlateStatistics(
        periods: {'day': day},
        serverTime: end.subtract(const Duration(seconds: 1)),
        elapsed: () => elapsed,
      );
      expect(stats.today?.entries, 137);
      expect(stats.untilMidnight, const Duration(seconds: 1));
      elapsed = const Duration(milliseconds: 999);
      expect(stats.today?.entries, 137);
      elapsed = const Duration(seconds: 1);
      expect(stats.today, isNull);
      expect(stats.untilMidnight, isNull);
      final past = PlateStatistics(
        periods: {
          'day': PlatePeriodStatistics(
            entries: 1,
            exits: 0,
            unknown: 0,
            startsAt: DateTime.utc(2000),
            endsAt: DateTime.utc(2000, 1, 2),
          ),
        },
        serverTime: DateTime.utc(2000, 1, 1, 12),
      );
      expect(past.today?.entries, 1);
    },
  );
  test(
    'gün sınırı UTC bilgisayar saat diliminden bağımsız yarı-açık aralıktır',
    () {
      final day = PlatePeriodStatistics.fromJson({
        'entries': 137,
        'exits': 8,
        'unknown': 0,
        'starts_at': '2026-11-07T21:00:00Z',
        'ends_at': '2026-11-08T21:00:00Z',
      });
      expect(day.contains(DateTime.parse('2026-11-07T20:59:59.999Z')), isFalse);
      expect(day.contains(DateTime.parse('2026-11-08T00:00:00+03:00')), isTrue);
      expect(day.contains(DateTime.parse('2026-11-08T20:59:59.999Z')), isTrue);
      expect(
        day.contains(DateTime.parse('2026-11-09T00:00:00+03:00')),
        isFalse,
      );
    },
  );
  testWidgets(
    'raporlar dar ekranda büyük yazıyla aralık/yön/açıklama gösterir ve yenilenir',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 568));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final service = _Service();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlateStatisticsDialog(
                  context,
                  service: service,
                  siteCode: 1,
                  gateId: 10,
                  gateName: 'Çok uzun kapı adı ile seçili geçiş noktası',
                ),
                child: const Text('Aç'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(service.requestedGate, 10);
      expect(find.text('Hafta'), findsOneWidget);
      expect(find.text('Giriş: 137'), findsOneWidget);
      expect(find.text('02.11.2026 – 08.11.2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Önceki dönem'));
      await tester.pumpAndSettle();
      expect(service.requestedAnchor, '2026-11-01');
      expect(find.text('26.10.2026 – 01.11.2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Sonraki dönem'));
      await tester.pumpAndSettle();
      expect(service.requestedAnchor, '2026-11-02');
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ay').last);
      await tester.pumpAndSettle();
      expect(find.text('01.11.2026 – 30.11.2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Önceki dönem'));
      await tester.pumpAndSettle();
      expect(service.requestedAnchor, '2026-10-31');
      expect(find.text('01.10.2026 – 31.10.2026'), findsOneWidget);
      await tester.tap(find.byTooltip('Sonraki dönem'));
      await tester.pumpAndSettle();
      expect(service.requestedAnchor, '2026-11-01');
      expect(tester.takeException(), isNull);
      service.fail = true;
      await tester.tap(find.byTooltip('Yenile'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Rapor yüklenemedi'), findsOneWidget);
      expect(find.text('Giriş: 0'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
