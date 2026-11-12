// Site başvurusu sırasında da hazırlanabilir; sunucuya ve mevcut sakin verisine erişmez.
import 'package:site_kapi_kontrol/models/bulk_import.dart';
import 'package:site_kapi_kontrol/services/bulk_export_renderer.dart';
import 'package:site_kapi_kontrol/services/bulk_xlsx_writer.dart';

RenderedFile buildBlankSiteSetupTemplate() => RenderedFile(
  fileName: 'site_kurulum_bos_sablon.xlsx',
  mimeType: ExportFormat.xlsx.mimeType,
  format: ExportFormat.xlsx,
  bytes: buildXlsx([
    XlsxSheet(
      name: ImportKind.allInOne.sheetName,
      columns: [
        const XlsxColumn('Blok*', format: XlsxFormat.text, width: 16),
        const XlsxColumn('Daire No*', format: XlsxFormat.text, width: 14),
        const XlsxColumn('Ad Soyad', format: XlsxFormat.text, width: 28),
        const XlsxColumn('Telefon', format: XlsxFormat.text, width: 22),
        XlsxColumn(
          'Plaka',
          format: XlsxFormat.text,
          width: 34,
          inputPrompt: XlsxInputPrompt(
            title: 'Araç plakaları (isteğe bağlı)',
            message:
                'Birden fazla plakayı virgülle ayırın. Her sakin için en çok 5 plaka yazılabilir.',
          ),
        ),
        XlsxColumn(
          'İlişki',
          format: XlsxFormat.text,
          width: 18,
          listValidation: XlsxListValidation(
            choices: const ['Malik', 'Kiracı', 'Aile Üyesi', 'Sakin'],
            promptTitle: 'İlişki (isteğe bağlı)',
            prompt:
                'Kiracı ve malik ayrımı aidatın doğru kişiye yazılması için önemlidir. Boş bırakılabilir.',
            error: 'Listeden Malik, Kiracı, Aile Üyesi veya Sakin seçin.',
          ),
        ),
      ],
      rows: const [],
      validationLastRow: 5001,
    ),
    XlsxSheet(
      name: 'Açıklama',
      freezeHeader: false,
      columns: const [
        XlsxColumn('Konu', format: XlsxFormat.wrap, width: 26),
        XlsxColumn('Açıklama', format: XlsxFormat.wrap, width: 88),
      ],
      rows: const [
        [
          'Boş şablon',
          'Hepsi bir arada sayfasında yalnız başlıklar bulunur. İlk satırı değiştirmeden altına kendi kayıtlarınızı yazın.',
        ],
        [
          'Her satır',
          'Bir daire sakini için bir satır kullanın. Aynı dairede birden fazla kişi varsa blok ve daire numarasını tekrar yazın.',
        ],
        [
          'Blok ve daire',
          'Blok ve Daire No zorunludur. Blok adları onaylı sitenizdeki bloklarla aynı olmalıdır. Daire numaralarının başındaki sıfırlar metin biçimiyle korunur.',
        ],
        [
          'Sakin bilgileri',
          'Daireye sakin eklemek için Ad Soyad girin. Telefon ve araç plakaları isteğe bağlıdır. Boş daireler site kurulumunda tanımlanır; bu şablona eklemeniz gerekmez.',
        ],
        [
          'Birden fazla araç',
          'Aynı kişinin plakalarını tek Plaka hücresine virgülle ayırarak yazın (en çok 5). Plaka girmek kendiliğinden kapı geçiş izni vermez.',
        ],
        [
          'Malik / kiracı',
          'İlişki isteğe bağlıdır. Biliniyorsa Malik veya Kiracı seçerek finans hesaplarının doğru kişiye bağlanmasına yardımcı olun.',
        ],
        [
          'Başvuru onayı',
          'Bu dosya site oluşturmaz veya başvuru onayını atlamaz. Başvurunuz onaylandıktan sonra sitenizde Kişiler > Toplu Yükle > Hepsi bir arada bölümünden yükleyin.',
        ],
        [
          'Kontrol ve onay',
          'Dosya yüklenince sütunları ve önizlemeyi inceleyin. Kayıtlar yalnız son onayınızdan sonra sisteme işlenir.',
        ],
        [
          'Kullanıcı hesapları',
          'Kullanıcı adlarını sistem otomatik oluşturur. Başlangıç şifresi mevcut toplu yükleme akışıyla atanır; ilk girişte şifre değişimi zorunludur.',
        ],
      ],
    ),
  ]),
);
