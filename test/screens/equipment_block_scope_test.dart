import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/services/equipment_api.dart';
import 'package:site_kapi_kontrol/ui/views/equipment_view.dart';
import 'people_fixtures.dart';

class ScopeService extends EquipmentService {
  ScopeService() : super(authService: PeopleFakeAuth());
  int? blockId = 34;
  int loads = 0;
  int listLoads = 0;
  final List<Map<String, Object?>> updates = [];
  final List<Map<String, Object?>> creates = [];
  @override
  Future<List<EquipmentItem>> list(int site) async {
    listLoads++;
    return [];
  }

  @override
  Future<List<MaintenancePlan>> due(int site) async => [];
  @override
  Future<List<EquipmentQuote>> quotes(int site) async => [];
  @override
  Future<List<QuoteRequest>> quoteRequests(int site) async => [];
  @override
  Future<void> create(int site, Map<String, Object?> body) async =>
      creates.add(body);
  @override
  Future<List<PickOption>> blocks(int site) async => const [
    PickOption(34, 'A Blok'),
    PickOption(35, 'B Blok'),
  ];
  @override
  Future<EquipmentDetail> detail(int site, int id) async {
    loads++;
    return EquipmentDetail(
      item: EquipmentItem(
        id: id,
        kind: 'asansor',
        name: 'Asansör',
        blockId: blockId,
        blockName: blockId == 34 ? 'A Blok' : null,
      ),
      plans: const [],
      logs: const [],
      expenseIds: const [],
    );
  }

  @override
  Future<EquipmentWorkHistory> workHistory(
    int site,
    int id, {
    int? beforeId,
  }) async => const EquipmentWorkHistory();
  @override
  Future<void> update(int site, int id, Map<String, Object?> body) async {
    updates.add(body);
    blockId = body['block_id'] as int?;
  }
}

void main() {
  for (final selectedBlock in [false, true]) {
    testWidgets(
      'ekipman ekleme ${selectedBlock ? 'seçilen gerçek bloğu' : 'isteğe bağlı site genelini'} taşır',
      (t) async {
        final service = ScopeService();
        t.view.physicalSize = const Size(400, 1000);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        await t.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: EquipmentView(
                  authService: service.authService,
                  service: service,
                  sites: const [EquipmentSite(code: 11, name: 'Gül')],
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
        await t.tap(find.text('Ekipman ekle'));
        await t.pumpAndSettle();
        await t.enterText(
          find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == 'Ad *',
          ),
          'A Blok Asansörü',
        );
        if (selectedBlock) {
          await t.tap(find.text('Site geneli / Ortak alan'));
          await t.pumpAndSettle();
          await t.tap(find.text('B Blok').last);
          await t.pumpAndSettle();
        }
        await t.tap(find.text('Kaydet'));
        await t.pumpAndSettle();
        expect(service.creates.single['block_id'], selectedBlock ? 35 : null);
        expect(service.creates.single['name'], 'A Blok Asansörü');
        expect(service.listLoads, 2);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'mevcut asansör blok kapsamı temizlenir ve kayıttan sonra canlı yenilenir',
    (t) async {
      final service = ScopeService();
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EquipmentDetailSheet(
              service: service,
              site: const EquipmentSite(code: 11, name: 'Gül'),
              itemId: 71,
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(find.text('Blok: A Blok'), findsOneWidget);
      await t.tap(find.text('Blok / kapsam'));
      await t.pumpAndSettle();
      await t.tap(find.text('A Blok').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Site geneli / Ortak alan').last);
      await t.pumpAndSettle();
      await t.tap(find.text('Kaydet'));
      await t.pumpAndSettle();
      expect(service.updates.single, {'block_id': null});
      expect(service.loads, 2);
      expect(find.text('Kapsam: Site geneli / Ortak alan'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('saltokuyan ekipman kapsamını görebilir ama değiştiremez', (
    t,
  ) async {
    final service = ScopeService();
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EquipmentDetailSheet(
            service: service,
            site: const EquipmentSite(code: 11, name: 'Gül', canWrite: false),
            itemId: 71,
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Blok: A Blok'), findsOneWidget);
    expect(find.text('Blok / kapsam'), findsNothing);
    expect(service.updates, isEmpty);
  });
}
