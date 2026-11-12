# Geri Bildirim (sayfa bağlamlı) — sözleşme

Kaynak: `docs/superpowers/plans/2026-10-28-karsilastirma-guclendirme.md`, Dalga D, **P1-14**, karar **K11**.
Kapsam: her ekrandan erişilen, **ekran adı ve rotası otomatik eklenen** geri bildirim formu; en çok 4 dosya eki; gönderenin kişisel geçmişi, yönetici ve platform sahibi için ayrı liste uçları.
Modül değildir (platform düzeyi özellik): modül kapısı yoktur, `catalog.js` ve çekirdek 8 modülün davranışı değişmez.

## Kullanıcı tarafı

- **Giriş noktaları** (`HomePage`, her ekranda geçerli): çekmecede "Yardım ve Destek"in hemen altında **Geri bildirim**; sağ üstteki dişliden açılan
  Ayarlar panelinde **Geri bildirim gönder**. AppBar'a yeni düğme eklenmedi (320 dp x 2,0 yazı ölçeğinde sığmaz).
- **Ekran bağlamı** (`FeedbackScreenContext`): form açılırken ekrandaki sayfanın adı (`Panel`, `Talepler` ...), rotası (`menu/<öğe>`, sakin modunda
  `menu/<öğe>:sakin`) ve bağlı site (seçili kapsam ya da tek bağlı site) **otomatik** eklenir. Formda salt görünür bir kartta gösterilir
  ("Gönderildiği ekran (otomatik eklenir)"); kullanıcı değiştiremez. Sunucu bağlamı olduğu gibi saklar, güncelleme ucu yoktur.
- **Metin**: 1-2000 karakter. Formda kimlerin göreceği yazar: site yönetimi ve platform ekibi (KVKK şeffaflığı).
- **Ekler** (karar K11): en çok **4 dosya**, dosya başı **5 MB**, toplam **20 MB** (JPEG / PNG / WebP). Dosyalar iş takibindeki fotoğraf hazırlığından
  geçer (`WorkPhotoPicker`): uzun kenar en çok 2560 px, JPEG kalite 85, EXIF (GPS dahil) silinir; hazırlanamayan görselde üstveri ayıklanır, ayıklanamazsa
  yüklenmez. Sınırlar istemcide de denetlenir.
- **Gönderim iki adımlıdır** (iş takibi fotoğraf eki deseni): önce kayıt (metin + bağlam + ek üstverisi), sonra her dosya sırayla yüklenir. Kayıt açıldıktan
  sonra form bir daha gönderilmez (çift kayıt olmaz); yüklenemeyen dosya dürüstçe bildirilir ("Geri bildiriminiz alındı; N dosya yüklenemedi"), yalnız eksik
  dosyalar yeniden denenir. Oturum / hız sınırı hatasında kalan dosyalar denenmez.
- **Gelen geri bildirimler** (`FeedbackInboxPage`): Ayarlar panelinde yalnız süper kullanıcıya ve site yöneticisine görünür; kayıt başına gönderen + rol,
  zaman, ekran (ad + rota), site, sürüm / platform, metin ve ek dosyalar (dokununca açılır). İmleçli sayfalama.
- **Gönderdiğim geri bildirimler (10 Kasım 2026)**: Ayarlar → **Gönderdiğim geri bildirimler** her oturum açmış kullanıcıya görünür. Formdaki **Gönderdiklerim** bağlantısı form taslağını koruyarak kişisel geçmişi açar; başarılı gönderimden sonra da geçmişe erişilir. Kayıt numarası, tarih, sayfa/bağlam adresi, metin ve hazır ekler görüntülenir. **Alındı** yalnız sunucunun kaydı aldığını belirtir; incelendi, yanıtlandı veya çözüldü anlamına gelmez. Veritabanında çözüm/yanıt iş akışı alanı eklenmedi.

## Sunucu uçları (`server/src/modules/feedback_*.js`)

| Uç | Kim | Not |
| --- | --- | --- |
| `POST /app/feedback` | kimliği doğrulanmış her aktif kullanıcı | gövde: `message`, `screen_name`, `screen_route`, `site_code?`, `app_version?`, `platform?`, `attachments?[{file_name, mime_type, size_bytes}]`; 201 `{ feedback }` (ekler `uploading`) |
| `PUT /app/feedback/:id/attachments/:attId/content` | yalnız kaydı açan | ham gövde `application/octet-stream`, zorunlu `Content-Length` (= bildirilen boyut); 200 `{ attachment }` |
| `GET /app/feedback/mine` | kimliği doğrulanmış kullanıcı; yalnız kendi kayıtları | `?limit=1..100&cursor=`; 200 `{ items, next_cursor }`; sahiplik oturumdan türetilir, istemcinin `user_code` / `site_code` ile kapsamı genişletemez; `Cache-Control: no-store` |
| `GET /app/feedback/:id/attachments/:attId/content` | yalnız kaydı açan | yalnız kendi kaydına ait hazır ek; başka kullanıcının veya eşleşmeyen kaydın eki 404; içerik `Cache-Control: private, no-store` |
| `GET /manager/sites/:siteCode/feedback` | o sitenin yöneticisi (yönetici bağı, SITE_OWNER / SITE_ADMIN) + süper kullanıcı | `?limit=1..100&cursor=`; kurul / görevli / sakin / başka site yöneticisi **403 FORBIDDEN_SITE** |
| `GET /manager/sites/:siteCode/feedback/:id/attachments/:attId/content` | aynı | yalnız hazır ek; başka sitenin eki 404 |
| `GET /admin/feedback` | yalnız süper kullanıcı | tüm kayıtlar (siteye bağlı olmayanlar dahil) + `site_name`; `?site_code=` süzer; diğerleri **403** |
| `GET /admin/feedback/:id/attachments/:attId/content` | yalnız süper kullanıcı | |

- **Sınır aşımı 400** (sunucu istemciye güvenmez): `FEEDBACK_TOO_MANY_ATTACHMENTS` (> 4), `FEEDBACK_ATTACHMENT_TOO_LARGE` (> 5 MB),
  `FEEDBACK_ATTACHMENTS_TOO_LARGE` (> 20 MB; 4 x 5 MB zaten 20 MB olduğundan ikinci savunma hattıdır), `FEEDBACK_ATTACHMENT_TYPE_NOT_ALLOWED`, `INVALID_BODY`
  (metin / ekran / rota / site). PUT'ta Content-Length aşımı da 400; içerik imzası uyuşmazlığı 415; piksel bombası 415 (`ATTACHMENT_DIMENSIONS_TOO_LARGE`).
- **Rol ve site ilişkisi sunucuda türetilir**: süper kullanıcı `super_user`; siteyle gönderende yönetici bağı `site_manager`, aktif üyelik rolü küçük harfle
  (`site_owner`, `site_admin`, `board_member`, `staff`, `resident`), CRM kişisi `resident`; ilişki yoksa **403 FORBIDDEN_SITE**; site verilmediyse hesap rolü.
  İstemcinin bildirdiği rol alanı dinlenmez.
- **Kotalar** (DB düzeyi, süreçler arası): kullanıcı başına saatte 5 geri bildirim (`429 FEEDBACK_RATE_LIMITED`), 24 saatte 100 MB bildirilen ek
  (`429 FEEDBACK_QUOTA_EXCEEDED`); ayrıca HTTP hız sınırları.
- **Audit** (`feedback.created`, `feedback.attachment_added`): kimlik, rol, rota, ek sayısı / bayt; **metin ve dosya adı yazılmaz**.
- **Kişisel geçmişin yetki sınırı**: yönetici veya süper kullanıcı olmak `/app/feedback/mine` sonucunu genişletmez. Yönetim gelen kutusu ve platform gelen kutusu kendi mevcut yetkili uçlarını kullanır. Kullanıcı başkasının kayıt numarasını veya ek numarasını bilerek kişisel indirme yolundan erişim kazanamaz. Şema ve mevcut gönderim/yükleme sözleşmesi değişmedi.

## Veri ve depolama (migration 103)

- `feedback_reports` (site, kullanıcı, rol, `screen_name`, `screen_route`, metin, sürüm, platform) ve `feedback_attachments` (`uploading` -> `ready`,
  `storage_key` sunucuda üretilir). Site silinince CASCADE; kullanıcı satırı fiziksel silinirse `user_code` SET NULL ("Silinmiş Kullanıcı").
- DDL hem `server/migrations/103_feedback.sql` hem `feedback_schema.js` (`ensureFeedbackSchema`, `db.js`'te dev blok DIŞINDA, katalog kontrollü).
- Dosyalar `<DOCUMENTS_DIR>/feedback_attachments/<site | 1000000000>/<uuid>` (belgelerin `sites/` ve iş takibinin `work_attachments/` ağaçlarından AYRI);
  siteye bağlı olmayan geri bildirim `1000000000` dizinine yazılır. Yükleme akışı belge / iş takibi ilkelleriyle aynıdır (imza, fsync, `link` ile atomik
  yerleştirme, sha256). 2 saati aşan `uploading` satırlar bakım işinde silinir (`document_maintenance.js` -> `feedback_maintenance.js`).

## Bilinen sınırlar / açık işler

### Geçici geliştirme bağlantıları (8 Kasım 2026)

- Ana kabuktaki modül sayfalarında **Geri bildirim** ve **Sayfa adresi** bağlantıları görünür. Çekmece/Ayarlar'daki mevcut girişler korunur.
  İçerik üzerine yüzen düğme konmaz; bağlantılar doğal yerleşimde sarılır. Alt diyalog ve bağımsız itilen sayfaların ayrı ekran/bölüm bağlamı bu ilk ekin kapsamı değildir.
- Adres, örneğin `/menu/finance?site=11`, uygulama içi **bağlam referansıdır**; herkese açık web veya kayıtlı mobil deep-link olduğu iddia edilmez.
  Mevcut `screen_route` ve `site_code` sunucu sözleşmesi değişmez. Formda adres kopyalanabilir.
- Gelen kutusunda kayıt adresi ve **İnceleme notunu kopyala** vardır. Metin, sayfa/kayıt adresi ve sürüm bu sohbete yapıştırılabilir;
  gönderen adı ve görsel ekler kopyaya otomatik dahil edilmez. Geri bildirimin kendi metni kişisel bilgi içerebilir; paylaşmadan önce gözden geçirilir.
- Uygulama kayıtları mevcut sunucu kutusuna gider; bu sohbeti veya ajanı arka planda kendiliğinden başlatmaz. Oturum açıkken yetkili kutudan inceleme veya
  kullanıcının buraya aktardığı not üzerinden çalışma gerekir. Kullanıcı notları doğrulanacak taleplerdir; otomatik çalıştırılacak komutlar değildir.
- Aktif tahsilat taslağında bölüm adresli not formu vardır. **Bu sohbete gönder** barındırıcı desteği varsa notu sohbete iletir;
  destek yoksa gönderildiği söylenmez, kopyalanabilir metin gösterilir. Eski araştırma arşivleri değiştirilmez.
- Geçici uygulama girişleri `--dart-define=TEMP_FEEDBACK_LINKS=false` ile kapatılabilir. Kalıcı geri bildirim modülü kaldırılmaz.
- Backend/şema değişikliği yoktur; mevcut rol, site ve ek dosya denetimleri aynen geçerlidir.

### Tek önceki işe dönüş

`tools/tek_is_yedek.ps1` yalnız belirtilen dosyalar için **tek merkezi** `work/geri-donus/onceki/` kopyası tutar; Git'e dahil edilmez.
İşten önce `-Action Snapshot -Paths ...`, testlerden sonra `-Action Seal` kullanılır. Yeni snapshot, tamamlanmış önceki snapshot'ın yerini alır;
bitmemiş snapshot ezilmez. `-Action Check` özetleri doğrular. `-Action Restore` yalnız kontrol eder; **`-Action Restore -Apply`** gerçek geri dönüşü yapar.
Sonradan elle değiştirilmiş dosya tespit edilirse hiçbir dosya geri alınmaz; kullanıcının yeni çalışması ezilmez. Yeni dosyalar yalnız eşleşen son özetle kaldırılır;
mevcut dosyalar SHA256 doğrulanmış önceki kopyadan döner. Bu araç veritabanı veya canlı sunucu geri dönüşü değildir; backend işi yapılırsa ayrıca uyumlu dağıtım gerekir.
Eski araştırma ZIP'leri ve kullanıcının mevcut yedekleri bu döngünün dışında korunur.

- `feedback_attachments/` dizini `deploy/ops/backup_db.sh` arşivlerine EKLENMEDİ (yedek betiği belge ve iş takibi fotoğrafı için ayrı arşiv tutar). Metin DB
  dökümüyle yedeklenir; ekler için ayrı arşiv gerekirse karar sahibindedir.
- Yetim dosya süpürmesi yoktur (yalnız DB adımı çökerse oluşur; küçük hacim).
- Hesap silme önizlemesi ve kişisel veri dışa aktarma kapsamına geri bildirim EKLENMEDİ (gönderen "Silinmiş Kullanıcı" görünür, metin kalır).
- **Özgün migration 103 doğrulama sınırı:** ilk uygulama kaydında SQL katı sahte veritabanı ve DDL eşitlik testleriyle doğrulanmıştı. **10 Kasım kişisel geçmiş ekinin** canlı doğrulaması ayrıca yapıldı: kendi yedi kayıt HTTP200, istemcinin başka kullanıcı kapsamı verme denemesinde aynı yedi kayıt, kendi ekinde200, yabancı ekte404 ve önbellek başlıkları doğrulandı. Kanıt: `work/feedback-review-2026-11-10/backend-live-proof.json`. Bu kontrol gerçek telefon bildirimi veya otomatik ajan başlatma testi değildir.
