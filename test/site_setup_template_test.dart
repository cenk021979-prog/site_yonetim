import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_header_mapper.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_reader.dart';
import 'package:site_kapi_kontrol/services/site_setup_template.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'boş XLSX başlıkları mevcut gerçek Hepsi bir arada sözleşmesiyle eşleşir',
    () {
      final file = buildBlankSiteSetupTemplate();
      expect(file.fileName, endsWith('.xlsx'));
      final reader = XlsxReader.open(file.bytes);
      expect(reader.sheets.map((s) => s.name), [
        ImportKind.allInOne.sheetName,
        'Açıklama',
      ]);
      final table = reader.readSheet(reader.sheets.first);
      expect(
        table.rows,
        hasLength(1),
      ); // Örnek kişi ve ön-doldurulmuş daire YOK.
      expect(table.rows.single.cells, [
        'Blok*',
        'Daire No*',
        'Ad Soyad',
        'Telefon',
        'Plaka',
        'İlişki',
      ]);
      final spec = ImportSpec.fromJson(
        jsonDecode(
              File('test/fixtures/bulk/server_spec.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final kind = spec.of(ImportKind.allInOne)!;
      final mapping = detectHeader(table, kind)!.mapping;
      expect(mapping.canProceed(kind), isTrue);
      expect(mapping.assignment['blok'], 0);
      expect(mapping.assignment['daire_no'], 1);
      expect(mapping.assignment['ad_soyad'], 2);
      expect(mapping.assignment['telefon'], 3);
      expect(mapping.assignment['plaka'], 4);
      expect(mapping.assignment['iliski'], 5);
      expect(extractImportRows(table, mapping, kind).rows, isEmpty);

      final archive = ZipDecoder().decodeBytes(file.bytes);
      final sheet = XmlDocument.parse(
        utf8.decode(archive.findFile('xl/worksheets/sheet1.xml')!.content),
      );
      final formats = XmlDocument.parse(
        utf8.decode(archive.findFile('xl/styles.xml')!.content),
      );
      expect(
        formats.toXmlString(),
        contains('numFmtId="49"'),
      ); // Telefon/daire/plaka metin.
      final list = sheet
          .findAllElements('dataValidation')
          .firstWhere((e) => e.getAttribute('type') == 'list');
      expect(list.getAttribute('sqref'), 'F2:F5001');
      expect(list.getElement('formula1')!.innerText, contains('Kiracı'));
    },
  );

  test(
    'Excelde doldurulan Türkçe kayıt ve birden fazla plaka gerçek okuyucudan sunucu satırına geçer',
    () {
      final file = buildBlankSiteSetupTemplate();
      final source = ZipDecoder().decodeBytes(file.bytes);
      final archive = Archive();
      for (final entry in source.files) {
        if (entry.name != 'xl/worksheets/sheet1.xml') {
          archive.addFile(
            ArchiveFile(entry.name, entry.content.length, entry.content),
          );
          continue;
        }
        final xml = XmlDocument.parse(utf8.decode(entry.content));
        final row = XmlElement(XmlName.parts('row'), [
          XmlAttribute(XmlName.parts('r'), '2'),
        ]);
        final values = [
          'Ç Blok',
          '05',
          'Şule Öztürk',
          '05321234567',
          '34 ABC 123, 06 XY 789',
          'Kiracı',
        ];
        for (var i = 0; i < values.length; i++) {
          row.children.add(
            XmlElement(
              XmlName.parts('c'),
              [
                XmlAttribute(
                  XmlName.parts('r'),
                  '${String.fromCharCode(65 + i)}2',
                ),
                XmlAttribute(XmlName.parts('t'), 'inlineStr'),
              ],
              [
                XmlElement(XmlName.parts('is'), [], [
                  XmlElement(XmlName.parts('t'), [], [XmlText(values[i])]),
                ]),
              ],
            ),
          );
        }
        xml.findAllElements('sheetData').single.children.add(row);
        final bytes = utf8.encode(xml.toXmlString());
        archive.addFile(ArchiveFile(entry.name, bytes.length, bytes));
      }
      final reader = XlsxReader.open(
        Uint8List.fromList(ZipEncoder().encode(archive)),
      );
      final table = reader.readSheet(reader.sheets.first);
      final spec = ImportSpec.fromJson(
        jsonDecode(
              File('test/fixtures/bulk/server_spec.json').readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      final kind = spec.of(ImportKind.allInOne)!;
      final result = extractImportRows(
        table,
        detectHeader(table, kind)!.mapping,
        kind,
      ).rows.single;
      expect(result.cells['blok'], 'Ç Blok');
      expect(result.cells['daire_no'], '05');
      expect(result.cells['ad_soyad'], 'Şule Öztürk');
      expect(result.cells['telefon'], '05321234567');
      expect(result.cells['plaka'], '34 ABC 123, 06 XY 789');
      expect(result.cells['iliski'], 'Kiracı');
    },
  );
}
