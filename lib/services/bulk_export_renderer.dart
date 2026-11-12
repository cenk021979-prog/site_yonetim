// `ExportEnvelope` -> CSV / XLSX dosyası (Platform Faz 2b). Biçimlendirme ve formül kaçışı TEK yerdedir
// (sözleşme Karar 13); Faz 4b finans raporları aynı üreticiyi kullanır.
//
// CSV: UTF-8 + BOM, ayırıcı `;`, satır sonu CRLF, sayı ondalık VİRGÜL ve binlik ayırıcısız, tarih `GG.AA.YYYY`,
// boş = boş hücre, ilk satır başlık, metin hücreler formül kaçışlı. XLSX: bkz. bulk_xlsx_writer.dart.
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/api_exception.dart';
import 'package:site_kapi_kontrol/services/bulk_cell_safety.dart';
import 'package:site_kapi_kontrol/services/bulk_csv_codec.dart';
import 'package:site_kapi_kontrol/services/bulk_formatting.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

/// Kullanıcıya verilecek hazır dosya.
class RenderedFile {
  const RenderedFile({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.format,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final ExportFormat format;
}

/// Metin sütunları: Excel'in sayıya çevirmemesi için XLSX'te metin biçimli (`@`) tanımlanır.
const Set<String> kTextFormattedKeys = <String>{
  'telefon',
  'plaka',
  'blok',
  'daire_no',
};

const String _fallbackBase = 'dosya';

/// Dosya adı gövdesini güvenli ASCII yapar: Türkçe harfler katlanır, diğer her şey `_` olur, en çok 80 karakter.
String safeFileBase(String base) {
  const from = 'ÇĞİÖŞÜçğıöşü';
  const to = 'CGIOSUcgiosu';
  final out = StringBuffer();
  for (final rune in base.runes) {
    final ch = String.fromCharCode(rune);
    final i = from.indexOf(ch);
    final mapped = i >= 0 ? to[i] : ch;
    if (RegExp(r'^[A-Za-z0-9._-]$').hasMatch(mapped)) {
      out.write(mapped);
    } else {
      out.write('_');
    }
  }
  var s = out
      .toString()
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^[._-]+|[._-]+$'), '');
  if (s.length > 80) s = s.substring(0, 80);
  return s.isEmpty ? _fallbackBase : s;
}

/// Zarfı [format] dosyasına çevirir.
RenderedFile renderExport(
  ExportEnvelope envelope,
  ExportFormat format, {
  String? sheetName,
}) {
  final base = safeFileBase(envelope.filenameBase);
  switch (format) {
    case ExportFormat.csv:
      return RenderedFile(
        bytes: _renderCsv(envelope),
        fileName: '$base.csv',
        mimeType: format.mimeType,
        format: format,
      );
    case ExportFormat.xlsx:
      return RenderedFile(
        bytes: _renderXlsx(envelope, sheetName: sheetName ?? envelope.kind),
        fileName: '$base.xlsx',
        mimeType: format.mimeType,
        format: format,
      );
  }
}

/// Büyük zarfları (20.000 satıra kadar) arayüzü dondurmamak için ayrı isolate'ta üretir; küçükler satır içi.
Future<RenderedFile> renderExportAsync(
  ExportEnvelope envelope,
  ExportFormat format, {
  String? sheetName,
  int inlineLimit = 1500,
}) {
  if (envelope.rowCount <= inlineLimit) {
    return Future<RenderedFile>.value(
      renderExport(envelope, format, sheetName: sheetName),
    );
  }
  return compute(_renderEntry, (envelope, format, sheetName));
}

RenderedFile _renderEntry((ExportEnvelope, ExportFormat, String?) args) =>
    renderExport(args.$1, args.$2, sheetName: args.$3);

// --- CSV --------------------------------------------------------------------------------------

String csvCellText(ExportColumn column, Object? value) {
  if (value == null) return '';
  switch (column.type) {
    case ExportColumnType.number:
      final text = formatPlainNumber(value, scale: column.scale);
      return text.isEmpty ? escapeCsvFormula('$value') : text;
    case ExportColumnType.date:
      return formatTurkishDate(value) ?? escapeCsvFormula('$value');
    case ExportColumnType.money:
      return formatMoneyMinor(value) ?? escapeCsvFormula('$value');
    case ExportColumnType.text:
      if (value is bool) return value ? 'Evet' : 'Hayır';
      return escapeCsvFormula('$value');
  }
}

Uint8List _renderCsv(ExportEnvelope envelope) {
  final rows = <List<String>>[
    <String>[for (final c in envelope.columns) escapeCsvFormula(c.label)],
    for (final row in envelope.rows)
      <String>[
        for (var i = 0; i < envelope.columns.length; i++)
          csvCellText(envelope.columns[i], row[i]),
      ],
  ];
  return csvBytes(rows);
}

// --- XLSX -------------------------------------------------------------------------------------

Uint8List _renderXlsx(ExportEnvelope envelope, {required String sheetName}) {
  return buildXlsx(<XlsxSheet>[_xlsxSheet(envelope, sheetName)]);
}

/// One Excel worksheet with independently headed column groups. Records keep
/// their own row; blank groups never imply a relationship between unrelated data.
/// Existing single-table CSV/XLSX exports keep their original contract.
const int maxExportWorkbookRows = 100000;
const int maxExportWorkbookBytes = 64 * 1024 * 1024;

/// Check before allocating XML/archive buffers. This counts UTF-8 cell text
/// without constructing a second byte array; nothing is truncated on overflow.
void validateExportWorkbookSize(
  List<ExportEnvelope> envelopes, {
  int maxRows = maxExportWorkbookRows,
  int maxTextBytes = maxExportWorkbookBytes,
}) {
  if (envelopes.fold<int>(0, (total, sheet) => total + sheet.rowCount) >
      maxRows) {
    throw ApiException(
      'Tek Excel dosyası en çok $maxRows satır içerebilir. Dosya hazırlanmadı.',
    );
  }
  var bytes = 0;
  void add(Object? value) {
    if (value == null) return;
    for (final rune in value.toString().runes) {
      bytes += rune <= 0x7f
          ? 1
          : rune <= 0x7ff
          ? 2
          : rune <= 0xffff
          ? 3
          : 4;
      if (bytes > maxTextBytes) {
        throw ApiException(
          'Birleşik Excel verisi çok büyük. Dosya hazırlanmadı; hiçbir kayıt eksik aktarılmadı.',
        );
      }
    }
  }

  for (final envelope in envelopes) {
    for (final column in envelope.columns) {
      add(column.label);
    }
    for (final row in envelope.rows) {
      for (final value in row) {
        add(value);
      }
    }
  }
}

RenderedFile _checkWorkbookBytes(RenderedFile file) {
  if (file.bytes.length > maxExportWorkbookBytes) {
    throw ApiException(
      'Birleşik Excel dosyası 64 MB sınırını aştı. Dosya kaydedilmedi.',
    );
  }
  return file;
}

RenderedFile renderExportWorkbook(
  List<ExportEnvelope> envelopes, {
  required List<String> sheetNames,
  String filenameBase = 'site_kayitlari',
}) {
  validateExportWorkbookSize(envelopes);
  return _checkWorkbookBytes(
    _buildExportWorkbook(
      envelopes,
      sheetNames: sheetNames,
      filenameBase: filenameBase,
    ),
  );
}

RenderedFile _buildExportWorkbook(
  List<ExportEnvelope> envelopes, {
  required List<String> sheetNames,
  required String filenameBase,
}) {
  if (envelopes.isEmpty || envelopes.length != sheetNames.length) {
    throw ArgumentError('Her dışa aktarma bölümü için bir başlık gerekir.');
  }
  final columns = <XlsxColumn>[
    const XlsxColumn('Kayıt Türü', format: XlsxFormat.text),
  ];
  final rows = <List<Object?>>[];
  for (var section = 0; section < envelopes.length; section++) {
    final envelope = envelopes[section];
    final offset = columns.length;
    columns.addAll([
      for (final column in envelope.columns)
        _xlsxColumn(column, label: '${sheetNames[section]} · ${column.label}'),
    ]);
    for (final row in envelope.rows) {
      rows.add([
        sheetNames[section],
        ...List<Object?>.filled(offset - 1, null),
        for (var i = 0; i < envelope.columns.length; i++)
          _xlsxValue(envelope.columns[i], row[i]),
      ]);
    }
  }
  return RenderedFile(
    bytes: buildXlsx([
      XlsxSheet(
        name: 'Site Kayıtları',
        columns: columns,
        rows: rows,
        autoFilter: true,
      ),
    ]),
    fileName: '${safeFileBase(filenameBase)}.xlsx',
    mimeType: ExportFormat.xlsx.mimeType,
    format: ExportFormat.xlsx,
  );
}

Future<RenderedFile> renderExportWorkbookAsync(
  List<ExportEnvelope> envelopes, {
  required List<String> sheetNames,
  String filenameBase = 'site_kayitlari',
}) {
  validateExportWorkbookSize(envelopes);
  if (envelopes.fold<int>(0, (total, sheet) => total + sheet.rowCount) <=
      1500) {
    return Future.value(
      renderExportWorkbook(
        envelopes,
        sheetNames: sheetNames,
        filenameBase: filenameBase,
      ),
    );
  }
  return compute(_renderWorkbookEntry, (
    envelopes,
    sheetNames,
    filenameBase,
  )).then(_checkWorkbookBytes);
}

RenderedFile _renderWorkbookEntry(
  (List<ExportEnvelope>, List<String>, String) input,
) => _buildExportWorkbook(
  input.$1,
  sheetNames: input.$2,
  filenameBase: input.$3,
);

XlsxSheet _xlsxSheet(ExportEnvelope envelope, String sheetName) {
  final columns = <XlsxColumn>[
    for (final c in envelope.columns) _xlsxColumn(c),
  ];
  final rows = <List<Object?>>[];
  for (final row in envelope.rows) {
    rows.add(<Object?>[
      for (var i = 0; i < envelope.columns.length; i++)
        _xlsxValue(envelope.columns[i], row[i]),
    ]);
  }
  return XlsxSheet(name: sheetName, columns: columns, rows: rows);
}

XlsxColumn _xlsxColumn(ExportColumn column, {String? label}) => XlsxColumn(
  label ?? column.label,
  format: switch (column.type) {
    ExportColumnType.text =>
      kTextFormattedKeys.contains(column.key)
          ? XlsxFormat.text
          : XlsxFormat.general,
    ExportColumnType.number =>
      (column.scale ?? 0) > 0 ? XlsxFormat.decimal : XlsxFormat.general,
    ExportColumnType.date => XlsxFormat.date,
    ExportColumnType.money => XlsxFormat.money,
  },
  scale: column.scale ?? 2,
);

Object? _xlsxValue(ExportColumn column, Object? value) {
  if (value == null) return null;
  switch (column.type) {
    case ExportColumnType.number:
      if (value is num) return value;
      return num.tryParse('$value'.trim().replaceAll(',', '.')) ?? '$value';
    case ExportColumnType.date:
      return parseIsoDate(value) != null ? value : '$value';
    case ExportColumnType.money:
      return formatMoneyMinor(value) != null ? XlsxMoney(value) : '$value';
    case ExportColumnType.text:
      return value is String ? value : '$value';
  }
}

// --- Hata raporu ------------------------------------------------------------------------------

/// Satır sorunları raporu (CSV: satır;alan;kod;ileti). Hücre DEĞERİ eklenmez; sunucu iletisi en çok 40 karakterlik
/// değer yankılayabilir, bu yüzden her hücre formül kaçışından geçer.
RenderedFile renderIssueReport(
  List<ImportIssue> issues,
  ImportKind kind, {
  Map<String, String> fieldLabels = const <String, String>{},
  DateTime? now,
}) {
  final stamp = _stamp(now ?? DateTime.now());
  final rows = <List<String>>[
    <String>['Satır', 'Alan', 'Kod', 'İleti'],
    for (final issue in issues)
      <String>[
        '${issue.n}',
        escapeCsvFormula(fieldLabels[issue.field] ?? issue.field ?? ''),
        escapeCsvFormula(issue.code),
        escapeCsvFormula(issue.message),
      ],
  ];
  return RenderedFile(
    bytes: csvBytes(rows),
    fileName: 'hata_raporu_${kind.apiValue}_$stamp.csv',
    mimeType: ExportFormat.csv.mimeType,
    format: ExportFormat.csv,
  );
}

String _stamp(DateTime now) {
  final u = now.toUtc().add(const Duration(hours: 3));
  return '${u.year.toString().padLeft(4, '0')}${u.month.toString().padLeft(2, '0')}${u.day.toString().padLeft(2, '0')}';
}
