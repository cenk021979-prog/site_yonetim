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
    'worksheets retain independent sheets with proper columns and rows without offset clutter',
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
      expect(reader.sheets.map((s) => s.name), ['Kişiler', 'Daireler', 'Araçlar', 'Kadro']);
      final peopleSheet = reader.readSheet(reader.sheets[0]);
      expect(peopleSheet.rows, hasLength(2));
      expect(peopleSheet.rows[0].cells, ['Ad Soyad', 'Telefon']);
      expect(peopleSheet.rows[1].cells, ['=SUM(A1)', '05320000000']);

      final aptSheet = reader.readSheet(reader.sheets[1]);
      expect(aptSheet.rows, hasLength(2));
      expect(aptSheet.rows[0].cells, ['Blok', 'Daire No']);
      expect(aptSheet.rows[1].cells, ['A', '001']);

      final vehicleSheet = reader.readSheet(reader.sheets[2]);
      expect(vehicleSheet.rows, hasLength(2));
      expect(vehicleSheet.rows[0].cells, ['Plaka']);
      expect(vehicleSheet.rows[1].cells, ['34 ABC 123']);

      final archive = ZipDecoder().decodeBytes(file.bytes);
      final xml = utf8.decode(
        archive.findFile('xl/worksheets/sheet1.xml')!.content as List<int>,
      );
      expect(xml, isNot(contains('<f>')));
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
