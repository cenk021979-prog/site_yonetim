// Kişiler ekranındaki toplu yükleme / dışa aktarma giriş noktaları (Platform Faz 2b).
//
// Düğmeler yalnız yazma yetkisi olanda (site yöneticisi / süper kullanıcı) görünür; kurul GÖRMEZ. Sihirbaz
// kapanınca görünen sekme yeniden çekilir, diğerleri bayatlar; «Kişilere git» / «Araçlara git» sekmeye geçirir.
// Boş Kişiler listesinde «Excel'den yükle» sihirbazı «Hepsi bir arada» önseçili açar. Bu girişte seçilebilen
// türler yalnız «Hepsi bir arada» ve «Araçlar»dır (Daireler / Kişiler klasik listeden kaldırıldı).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/people_nav.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/user_role.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/bulk_api.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/ui/helpers/people_scope.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_controller.dart';
import 'package:site_kapi_kontrol/ui/views/bulk_import_view.dart';
import 'package:site_kapi_kontrol/ui/views/people_view.dart';
import 'package:site_kapi_kontrol/ui/widgets/bulk_export_sheet.dart';
import 'package:site_kapi_kontrol/services/bulk_file_picker.dart';

import '../bulk_fakes.dart';
import '../bulk_test_support.dart' show specJson;
import 'dialog_layout_harness.dart' show settleFor;
import 'list_fixtures.dart';
import 'people_fixtures.dart';

/// Sahte sunucu şeması: gerçek sunucudaki gibi «all_in_one» türü de vardır (Kişiler sütunlarıyla).
ImportSpec _spec() {
  final json = specJson();
  final kinds = Map<String, dynamic>.from(json['kinds'] as Map);
  kinds['all_in_one'] = Map<String, dynamic>.from(kinds['people'] as Map);
  json['kinds'] = kinds;
  return ImportSpec.fromJson(json);
}

class _Bulk {
  _Bulk({FakeBulkApi? api}) : api = (api ?? FakeBulkApi())..spec = _spec();
  final FakeBulkApi api;
  final FakeDelivery delivery = FakeDelivery();
  String fileName = 'kisiler.csv';
  String csv = kPeopleCsv;
  int controllersBuilt = 0;
  ImportKind? lastInitialKind;

  void install() {
    BulkService.debugApiFactory = (_) => api;
    ExportSheet.debugDeliveryFactory = () => delivery;
    BulkImportViewState.debugControllerFactory = (PeopleScope scope) {
      controllersBuilt++;
      return BulkImportController(
        service: BulkService(authService: scope.authService, api: api),
        siteCode: scope.siteCode,
        siteName: scope.siteName,
        delivery: delivery,
        purgePickerCache: () async {},
        parseRunner: inlineParse,
        picker: () async {
          final bytes = utf8Bytes(csv);
          return PickedBulkFile(name: fileName, size: bytes.length, readBytes: () async => bytes);
        },
      );
    };
    addTearDown(() {
      BulkService.debugApiFactory = null;
      ExportSheet.debugDeliveryFactory = null;
      BulkImportViewState.debugControllerFactory = null;
    });
  }
}

class _ScopedExportApi extends FakeBulkApi {
  final scopes = <({String token, int siteCode, String kind})>[];

  @override
  Future<ExportEnvelope> exportData({
    required String token,
    required int siteCode,
    required String kind,
    BulkExportFilters filters = const BulkExportFilters(),
    bool includeNotes = false,
    ExportFormat format = ExportFormat.xlsx,
    String pathPrefix = '',
  }) async {
    scopes.add((token: token, siteCode: siteCode, kind: kind));
    final envelope = await super.exportData(token: token, siteCode: siteCode, kind: kind,
      filters: filters, includeNotes: includeNotes, format: format, pathPrefix: pathPrefix);
    if (kind == 'vehicles') {
      return const ExportEnvelope(
        kind: 'vehicles', filenameBase: 'araclar',
        columns: [ExportColumn(key: 'plaka', label: 'Plaka')],
        rows: [['34 ABC 123'], ['34 DEF 456']],
      );
    }
    return envelope;
  }
}

class _TeamExportAuth extends PeopleFakeAuth {
  _TeamExportAuth() {
    final seed = PeopleFakeAuth.seeded();
    peopleJson.addAll(seed.peopleJson);
    apartmentsJson.addAll(seed.apartmentsJson);
    vehiclesJson.addAll(seed.vehiclesJson);
  }

  final teamSites = <int>[];

  @override
  Future<TeamData> getTeam(int siteCode) {
    teamSites.add(siteCode);
    return super.getTeam(siteCode);
  }
}

Future<GlobalKey<PeopleViewState>> _pump(
  WidgetTester t,
  PeopleFakeAuth auth, {
  double width = 400,
  double height = 1600,
  double scale = 1.0,
  bool dark = false,
  bool manage = true,
  List<PeopleSite> readOnly = const <PeopleSite>[],
}) async {
  final key = GlobalKey<PeopleViewState>();
  await pumpList(
    t,
    PeopleView(key: key, authService: auth, manageSites: manage, readOnlySites: readOnly),
    width: width,
    height: height,
    scale: scale,
    dark: dark,
  );
  await settleFor(t, 100);
  await settleFor(t, 100);
  return key;
}

Future<void> _tap(WidgetTester t, String key) async {
  if (key.startsWith('people_tab_')) {
    await selectPeopleSection(t, int.parse(key.substring('people_tab_'.length)));
    return;
  }
  final f = find.byKey(ValueKey<String>(key));
  expect(f, findsOneWidget, reason: key);
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
  await settleFor(t, 350);
}

Future<void> _ackAndSubmit(WidgetTester t) async {
  final ack = find.byKey(const ValueKey<String>('bulk_confirm_ack'));
  await t.ensureVisible(ack);
  await t.pump();
  await t.tap(ack);
  await t.pump();
  await t.tap(find.byKey(const ValueKey<String>('bulk_confirm_submit')));
  await settleFor(t, 400);
}

void main() {
  group('düğmeler', () {
    testWidgets('site yöneticisi: Toplu Yükle ve Dışa Aktar görünür', (t) async {
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_bulk_export')), findsOneWidget);
      expect(find.text('Toplu Yükle'), findsOneWidget);
      expect(find.text('Dışa Aktar'), findsOneWidget);
    });

    testWidgets('süper kullanıcı: görünür', (t) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.superUser);
      await _pump(t, auth);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
    });

    testWidgets('kurul üyesi (salt okunur site): HİÇBİR toplu düğme görünmez', (t) async {
      final auth = PeopleFakeAuth.seeded(role: UserRole.apartmentOwner);
      await _pump(t, auth, manage: false, readOnly: const <PeopleSite>[PeopleSite(code: 11, name: 'Gül Sitesi')]);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsNothing);
      expect(find.byKey(const ValueKey<String>('people_bulk_export')), findsNothing);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsNothing);
    });

    for (final (w, h, scale) in const <(double, double, double)>[
      (320.0, 640.0, 2.0),
      (360.0, 640.0, 1.5),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: düğmeler taşmaz', (t) async {
          final auth = PeopleFakeAuth.seeded();
          await _pump(t, auth, width: w, height: h, scale: scale, dark: dark);
          expect(t.takeException(), isNull);
          expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
        });
      }
    }
  });

  group('sihirbaz girişi', () {
    testWidgets('Toplu Yükle sihirbazı açar; hiçbir şey yapılmadan dönülürse liste yeniden çekilmez', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      final callsBefore = auth.peopleCalls.length;
      await _tap(t, 'people_bulk_import');
      expect(find.text('Toplu Yükle'), findsWidgets);
      expect(find.byKey(const ValueKey<String>('bulk_step_title')), findsOneWidget);
      expect(find.text('Adım 1 / 5 · Tür'), findsOneWidget);
      expect(bulk.controllersBuilt, 1);
      await t.tap(find.byKey(const ValueKey<String>('bulk_back')));
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('people_bulk_import')), findsOneWidget);
      expect(auth.peopleCalls.length, callsBefore, reason: 'değişiklik yok: liste tazelenmez');
    });

    testWidgets('yükleme sonrası «Kişilere git»: görünen sekme yeniden çekilir, diğerleri bayatlar', (t) async {
      final bulk = _Bulk()..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      // Daireler sekmesini kur (bayatlama izlenebilsin).
      await _tap(t, 'people_tab_1');
      await _tap(t, 'people_tab_0');
      final people0 = auth.peopleCalls.length;
      final apts0 = auth.apartmentCalls.length;
      await _tap(t, 'people_bulk_import');
      await _tap(t, 'bulk_kind_all_in_one');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      expect(bulk.api.commitCalls.length, 1);
      await _tap(t, 'bulk_result_go');
      expect(auth.peopleCalls.length, greaterThan(people0), reason: 'Kişiler listesi yeniden çekildi');
      expect(auth.apartmentCalls.length, apts0, reason: 'görünmeyen sekme hemen çekilmez, bayatlar');
      await _tap(t, 'people_tab_1');
      expect(auth.apartmentCalls.length, greaterThan(apts0), reason: 'bayat sekme açılınca yenilenir');
    });

    testWidgets('«Araçlara git» Araçlar sekmesine geçirir', (t) async {
      final bulk = _Bulk()
        ..csv = 'Plaka;Blok;Daire No\n34 ABC 123;A;1\n'
        ..fileName = 'araclar.csv'
        ..install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await _tap(t, 'people_bulk_import');
      expect(find.byKey(const ValueKey<String>('bulk_kind_apartments')), findsNothing, reason: 'Daireler klasik listede yok');
      expect(find.byKey(const ValueKey<String>('bulk_kind_people')), findsNothing, reason: 'Kişiler klasik listede yok');
      await _tap(t, 'bulk_kind_vehicles');
      await _tap(t, 'bulk_kind_continue');
      await _tap(t, 'bulk_pick_file');
      await t.pump();
      await _tap(t, 'bulk_mapping_continue');
      await t.pump();
      await _tap(t, 'bulk_commit');
      await _ackAndSubmit(t);
      expect(bulk.api.commitCalls.single.kind, ImportKind.vehicles);
      await _tap(t, 'bulk_result_go');
      expect(auth.vehicleCalls, isNotEmpty);
      expect(selectedPeopleSection(t), 2);
    });
  });

  group('boş liste kısayolu', () {
    testWidgets('boş Kişiler: «Excel\'den yükle» sihirbazı «Hepsi bir arada» önseçili açar', (t) async {
      _Bulk().install();
      final auth = PeopleFakeAuth();
      await _pump(t, auth);
      expect(find.text('Henüz kişi kaydı yok.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsOneWidget);
      await _tap(t, 'people_empty_bulk_import');
      await settleFor(t);
      expect(find.byKey(const ValueKey<String>('bulk_template_card')), findsOneWidget, reason: 'tür önceden seçildi');
      expect(find.text('Seçili'), findsOneWidget);
    });

    for (final (w, h, scale) in const <(double, double, double)>[
      (320.0, 640.0, 2.0),
      (360.0, 640.0, 1.5),
      (640.0, 360.0, 2.0),
    ]) {
      for (final dark in const <bool>[false, true]) {
        testWidgets('boş Kişiler + kısayol ${w.toInt()}x${h.toInt()} x$scale ${dark ? 'koyu' : 'açık'}: taşmaz', (t) async {
          _Bulk().install();
          await _pump(t, PeopleFakeAuth(), width: w, height: h, scale: scale, dark: dark);
          expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsOneWidget);
          expect(find.text('Daire ve kişi bilgilerini şimdi toplu yükleyin.'), findsOneWidget);
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('süzgeçli boş sonuçta kısayol YOK', (t) async {
      _Bulk().install();
      final auth = PeopleFakeAuth.seeded();
      await _pump(t, auth);
      await t.enterText(find.byKey(const ValueKey<String>('people_search')), 'bulunmayan-ad');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      expect(find.text('Bu arama ve süzgeç için kişi bulunamadı.'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('people_empty_bulk_import')), findsNothing);
    });
  });

  group('dışa aktarma girişi', () {
    testWidgets('arama ve aktif filtresi dört kaynaklı tek Excel dosyasını daraltmaz', (t) async {
      final api = _ScopedExportApi();
      final bulk = _Bulk(api: api)..install();
      final auth = _TeamExportAuth();
      await _pump(t, auth);
      await t.enterText(find.byKey(const ValueKey<String>('people_search')), 'ayşe');
      await t.pump(const Duration(milliseconds: 400));
      await t.pump();
      await _tap(t, 'people_bulk_export');
      expect(find.byKey(const ValueKey<String>('export_filter_summary')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_source_0')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_format_csv')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_format_xlsx')), findsNothing);
      expect(find.textContaining('Tüm kayıtlar dahil edilir'), findsOneWidget);
      await _tap(t, 'export_save');
      expect(api.exportCalls.map((call) => call.kind), ['people', 'apartments', 'vehicles']);
      for (final call in api.exportCalls) {
        expect(call.filters.query, isNull);
        expect(call.filters.status, 'all');
        expect(call.filters.relation, isNull);
        expect(call.format, ExportFormat.xlsx);
        expect(call.includeNotes, isFalse);
      }
      expect(api.scopes.map((call) => call.siteCode), everyElement(11));
      expect(api.scopes.map((call) => call.token), everyElement(auth.session!.token));
      expect(auth.teamSites, [11]);
      expect(bulk.delivery.files.length, 1);
      final reader = XlsxReader.open(bulk.delivery.files.single.bytes);
      expect(reader.sheets.map((sheet) => sheet.name), ['Site Kayıtları']);
      final rows = reader.readSheet(reader.sheets.single).rows;
      final headers = rows.first.cells;
      expect(headers.first, 'Kayıt Türü');
      expect(headers, containsAll(['Kişiler · Ad Soyad', 'Daireler · Daire No', 'Araçlar · Plaka', 'Kadro · Görev']));
      final kinds = rows.skip(1).map((row) => row.cells.first).toList();
      expect(kinds.where((kind) => kind == 'Kişiler'), hasLength(2), reason: 'ayşe araması sunucudaki iki kişiyi daraltmaz');
      expect(kinds.where((kind) => kind == 'Daireler'), hasLength(3), reason: 'aktif kişi filtresi üç daireyi kaybettirmez');
      expect(kinds.where((kind) => kind == 'Araçlar'), hasLength(2));
      expect(kinds.where((kind) => kind == 'Kadro'), hasLength(1));
      expect(rows, hasLength(9), reason: 'sekiz kaynak kaydı, başlık ve mükerrer JOIN yok');
      for (final row in rows.skip(1)) {
        final kind = row.cells.first;
        for (var column = 1; column < headers.length; column++) {
          if (!headers[column].toString().startsWith('$kind · ')) {
            expect(column < row.cells.length ? row.cells[column] : null, isNull,
              reason: 'kayıt yalnız kendi bölüm sütunlarını doldurur');
          }
        }
      }
      final manager = rows.last.cells;
      expect(manager[headers.indexOf('Kadro · Ad Soyad')], 'Yönetici Kişi');
      expect(headers.where((header) => header.toString().startsWith('Kadro · ')),
        ['Kadro · Ad Soyad', 'Kadro · Görev', 'Kadro · İletişim Telefonu']);
    });

    testWidgets('Daireler görünümünden de bütün kaynaklar tek dosyada kaydedilir', (t) async {
      final api = _ScopedExportApi();
      final bulk = _Bulk(api: api)..install();
      final auth = _TeamExportAuth();
      await _pump(t, auth);
      await _tap(t, 'people_tab_1');
      await _tap(t, 'people_bulk_export');
      expect(find.byKey(const ValueKey<String>('export_source_1')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_filter_summary')), findsNothing);
      expect(find.byKey(const ValueKey<String>('export_format_csv')), findsNothing);
      await _tap(t, 'export_save');
      expect(api.exportCalls.map((call) => call.kind), ['people', 'apartments', 'vehicles']);
      expect(auth.teamSites, [11]);
      expect(api.scopes.map((call) => call.siteCode), everyElement(11));
      expect(api.scopes.map((call) => call.token), everyElement(auth.session!.token));
      expect(bulk.delivery.files, hasLength(1));
      expect(bulk.delivery.files.single.fileName.endsWith('.xlsx'), isTrue);
      final reader = XlsxReader.open(bulk.delivery.files.single.bytes);
      expect(reader.sheets.map((sheet) => sheet.name), ['Site Kayıtları']);
      final rows = reader.readSheet(reader.sheets.single).rows;
      expect(rows.first.cells.first, 'Kayıt Türü');
      expect(rows.first.cells, containsAll(['Kişiler · Ad Soyad', 'Daireler · Daire No', 'Araçlar · Plaka', 'Kadro · Görev']));
      expect(rows, hasLength(9));
      expect(rows.skip(1).map((row) => row.cells.first),
        ['Kişiler', 'Kişiler', 'Daireler', 'Daireler', 'Daireler', 'Araçlar', 'Araçlar', 'Kadro']);
    });
  });
}
