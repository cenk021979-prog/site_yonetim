import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/styles/app_theme.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';
import '../bulk_fakes.dart';

const names = ['Kişiler', 'Daireler', 'Araçlar', 'Kadro'];
ExportEnvelope table(String name) => ExportEnvelope(
  kind: name,
  filenameBase: name,
  columns: [ExportColumn(key: 'ad', label: '$name başlığı')],
  rows: [
    ['$name kaydı'],
  ],
);

Future<void> open(
  WidgetTester t,
  List<ExportSource> sources,
  FakeDelivery delivery, {
  bool dark = false,
}) async {
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark() : AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(2)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExportSheet(
            sources: sources,
            combineSources: true,
            delivery: delivery,
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> save(WidgetTester t) async {
  final button = find.byKey(const ValueKey('export_save'));
  await t.ensureVisible(button);
  await t.tap(button);
  await t.pumpAndSettle();
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'combined file has no type/format choice and delivers all sections: dark=$dark',
      (t) async {
        final calls = <String>[];
        final delivery = FakeDelivery();
        await open(
          t,
          [
            for (final name in names)
              ExportSource(
                label: name,
                fetch: (format) async {
                  expect(format, ExportFormat.xlsx);
                  calls.add(name);
                  return table(name);
                },
              ),
          ],
          delivery,
          dark: dark,
        );
        expect(find.text('Ne aktarılsın?'), findsNothing);
        expect(find.text('Dosya biçimi'), findsNothing);
        expect(find.byType(ChoiceChip), findsNothing);
        await save(t);
        expect(calls, names);
        expect(delivery.files, hasLength(1));
        expect(
          XlsxReader.open(
            delivery.files.single.bytes,
          ).sheets.map((s) => s.name),
          ['Site Kayıtları'],
        );
        final reader = XlsxReader.open(delivery.files.single.bytes);
        final rows = reader.readSheet(reader.sheets.single).rows;
        expect(rows.first.cells.first, 'Kayıt Türü');
        expect(rows.skip(1).map((row) => row.cells.first), names);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('one failed section produces no partial successful file', (
    t,
  ) async {
    final delivery = FakeDelivery();
    await open(t, [
      for (final name in names)
        ExportSource(
          label: name,
          fetch: (_) async {
            if (name == 'Kadro') throw ApiException('Kadro okunamadı.');
            return table(name);
          },
        ),
    ], delivery);
    await save(t);
    expect(delivery.files, isEmpty);
    expect(find.text('Kadro okunamadı.'), findsOneWidget);
  });
  testWidgets(
    'account change during preparation never delivers the old account data',
    (t) async {
      var current = true;
      final gate = Completer<ExportEnvelope>();
      final delivery = FakeDelivery();
      await open(t, [
        ExportSource(
          label: 'Kişiler',
          isCurrent: () => current,
          fetch: (_) => gate.future,
        ),
      ], delivery);
      final button = find.byKey(const ValueKey('export_save'));
      await t.ensureVisible(button);
      await t.tap(button);
      await t.pump();
      current = false;
      gate.complete(table('Kişiler'));
      await t.pumpAndSettle();
      expect(delivery.files, isEmpty);
      expect(
        find.text('Oturum değişti. Dışa aktarmayı yeniden açın.'),
        findsOneWidget,
      );
    },
  );
}
