import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/models/team.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/ui/widgets/crm_export_sources.dart';

void main() {
  test(
    'global preparation limit fails explicitly without trimming a section',
    () {
      const sheet = ExportEnvelope(
        kind: 'test',
        filenameBase: 'test',
        columns: [ExportColumn(key: 'ad', label: 'Ad')],
        rows: [
          ['ş😊'],
        ],
      );
      expect(
        () => validateExportWorkbookSize([sheet], maxTextBytes: 8),
        returnsNormally,
      );
      expect(
        () => validateExportWorkbookSize([sheet], maxTextBytes: 7),
        throwsA(isA<ApiException>()),
      );
      expect(
        () => validateExportWorkbookSize([sheet, sheet, sheet], maxRows: 2),
        throwsA(isA<ApiException>()),
      );
      final validLarge = [
        for (var i = 0; i < 3; i++)
          ExportEnvelope(
            kind: 'test',
            filenameBase: 'test',
            columns: sheet.columns,
            rows: List.filled(20000, const ['x']),
          ),
        sheet,
      ];
      expect(() => validateExportWorkbookSize(validLarge), returnsNormally);
    },
  );
  test(
    'one worksheet retains independent column groups, sparse cells and no invented relationship',
    () {
      final tables = [
        const ExportEnvelope(
          kind: 'people',
          filenameBase: 'people',
          columns: [
            ExportColumn(key: 'ad_soyad', label: 'Ad Soyad'),
            ExportColumn(key: 'telefon', label: 'Telefon'),
          ],
          rows: [
            ['=SUM(A1)', '05320000000'],
          ],
        ),
        const ExportEnvelope(
          kind: 'apartments',
          filenameBase: 'apartments',
          columns: [
            ExportColumn(key: 'blok', label: 'Blok'),
            ExportColumn(key: 'daire_no', label: 'Daire No'),
          ],
          rows: [
            ['A', '001'],
          ],
        ),
        const ExportEnvelope(
          kind: 'vehicles',
          filenameBase: 'vehicles',
          columns: [ExportColumn(key: 'plaka', label: 'Plaka')],
          rows: [
            ['34 ABC 123'],
          ],
        ),
        teamExportEnvelope(
          const TeamData(
            managers: [],
            duties: [],
            legacyRoles: [],
            contacts: [],
            directoryEnabled: true,
          ),
        ),
      ];
      final file = renderExportWorkbook(
        tables,
        sheetNames: ['Kişiler', 'Daireler', 'Araçlar', 'Kadro'],
      );
      expect(file.fileName, 'site_kayitlari.xlsx');
      final reader = XlsxReader.open(file.bytes);
      expect(reader.sheets.map((s) => s.name), ['Site Kayıtları']);
      final all = reader.readSheet(reader.sheets.single);
      expect(all.rows, hasLength(4));
      expect(all.rows[0].cells, [
        'Kayıt Türü',
        'Kişiler · Ad Soyad',
        'Kişiler · Telefon',
        'Daireler · Blok',
        'Daireler · Daire No',
        'Araçlar · Plaka',
        'Kadro · Ad Soyad',
        'Kadro · Görev',
        'Kadro · İletişim Telefonu',
      ]);
      expect(all.rows[1].cells.take(3), ['Kişiler', '=SUM(A1)', '05320000000']);
      expect(all.rows[2].cells.take(5), ['Daireler', null, null, 'A', '001']);
      expect(all.rows[3].cells.take(6), [
        'Araçlar',
        null,
        null,
        null,
        null,
        '34 ABC 123',
      ]);
      final archive = ZipDecoder().decodeBytes(file.bytes);
      final xml = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
      );
      expect(RegExp(r'<c r="').allMatches(xml), hasLength(17));
      expect(xml, contains('<c r="D3"'));
      expect(xml, contains('<c r="F4"'));
      expect(xml, isNot(contains('<c r="C3"')));
      expect(xml, isNot(contains('<f>')));
      expect(xml, contains('<autoFilter ref="A1:I4"/>'));
    },
  );

  test(
    'roster exports visible roles and public phones, never auth/invitation/contact notes',
    () {
      final data = TeamData.fromJson({
        'managers': [
          {
            'full_name': 'Yönetici',
            'email': 'private@example.invalid',
            'token': 'secret',
          },
        ],
        'duties': [
          {
            'person_id': 7,
            'full_name': 'Teknik',
            'duty': 'technical',
            'public_phone': '05320000000',
            'access': 'granted',
          },
        ],
        'legacy_roles': [
          {'user_code': 55, 'full_name': 'Kurul', 'role': 'BOARD_MEMBER'},
        ],
        'contacts': [
          {'id': 1, 'label': 'Firma', 'phone': '555', 'note': 'private-note'},
        ],
      });
      final envelope = teamExportEnvelope(data);
      expect(envelope.rows, [
        ['Yönetici', 'Site Yöneticisi', null],
        ['Teknik', 'Teknik görevli', '05320000000'],
        ['Kurul', 'Kurul Üyesi', null],
      ]);
      expect(envelope.columns.map((c) => c.key), [
        'ad_soyad',
        'gorev',
        'telefon',
      ]);
      expect(envelope.rows.toString(), isNot(contains('private')));
      expect(envelope.rows.toString(), isNot(contains('secret')));
    },
  );
}
