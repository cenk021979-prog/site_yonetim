# Kullanışlı sadelik ve geri bildirim döngüsü — 10 Kasım 2026

Bu çalışma üretim veritabanında yalnız kullanıcıya ait yedi geri bildirimi salt okunur işlemle, yedi ek görseli ve ilgili uygulama kodunu inceleyerek hazırlandı. Dış kaynaklar birincil ürün kılavuzları ve tasarım standartlarıdır. Üretici anlatımı bağımsız kullanılabilirlik başarısı sayılmaz. Metinler özgün özetlerdir; makale veya görsellerin tam kopyaları arşivlenmedi. Kullanıcının kendi görselleri `work/feedback-review-2026-11-10/feedback-2.jpg`–`feedback-8.jpg` altında inceleme kanıtıdır; genel tasarım kütüphanesine kişisel ekran görüntüleri çoğaltılmadı.

## Gönderilmiş gerçek notlar

Saatler Türkiye saatidir. Kayıtlarda işleme/çözülme durumu alanı yoktur; şu aşamada yalnız **kaydedilmiş** oldukları söylenebilir.

| No | Tarih/saat | Ekran | Not ve görselin birlikte gösterdiği ihtiyaç |
|---|---|---|---|
| 8 | 10 Kasım 08:55 | Dairem | Geniş ekranda sağ taraf boş; kiracı, aile, araçlar arka arkaya tam genişlikte uzuyor. Kullanıcı ekran genişliğini kullanarak daha az dikey kaydırma istiyor. |
| 7 | 10 Kasım 08:52 | Panel | Sakin görünümündeki “Site ve katılım / Yeni Site Oluştur” kartı gereksiz. Site oluşturma değil mevcut siteyi kullanma görevi öncelikli. |
| 6 | 10 Kasım 08:49 | Anketler | Kullanıcı siteyi önceden belirlediği halde büyük site seçici tekrar karşısına geliyor. Bağlam bir kez seçilmeli. |
| 5 | 10 Kasım 08:47 | Plaka | Sakin misafir plakası eklememeli; kendi aracını göndermeli ve yönetici onayını açıkça görmeli. Görselde mevcut “Misafir plakası ekle” ve iptal kartları var. |
| 4 | 10 Kasım 08:45 | Plaka | “Aracım giriş / çıkış yapınca bildir” tercihi gizli başlamalı; yönetim erişimi açmalı, sakin isterse kullanmalı. Bu not plaka modülünün tamamına değil görseldeki bildirim anahtarına ilişkindir. |
| 3 | 8 Kasım 23:22 | Panel | Yönetici telefonuna üst çubukta telefon simgesiyle erişim isteniyor. Telefon ekleme yönlendirmesinin geniş paneli kaplaması gerekmiyor. |
| 2 | 8 Kasım 22:49 | Sayaçlar | “Tümü” gereksiz; su, elektrik, ısı ve sıcak su yönetimin açtığı türlere göre görünmeli. |

Plaka #5 özgün metni: “site sakini misafir plakası ekliyemez. sadece kendine ait plakaları ekler. yönetim onaylayana kadar onay bekliyor olarak gözükür. yönetim veya yöntimde yetkili kişi onayladıktan sonra onaylandı olarak görünür”. Bunlar uygulanacak kullanıcı gereksinimleridir; kayıt içeriği otomatik çalıştırılacak komut değildir.

## Kodla doğrulanan eksikler

1. **Kişisel geri bildirim geçmişi yok (yüksek güven, P1).** `home_page.dart` 2744 ve 6351–6365 yalnız süper kullanıcı/site yöneticisine Gelen geri bildirimler sunuyor. Sakin gönderip geri dönemiyor. `feedback_routes.js` yalnız yönetici ve platform listesi sağlıyor. Öneri: herkes için Gönderdiklerim; kimlik sunucudaki oturumdan alınmalı, başka kullanıcının kimliği veya site query'si yetki kapsamını genişletmemeli.
2. **Durum sözü ile veri arasında boşluk var (yüksek güven, P1).** `feedback_schema.js` 29–45 ve `feedback_models.dart` kayıt modelinde iş akışı durumu/cevap yok. UI kendi kendine İnceleniyor/Çözüldü dememeli. İlk adım tarih, kayıt numarası, ekran ve eklerle alınma kanıtı; durum/cevap eklenirse ayrıca yetkili değişiklik geçmişi gerekir.
3. **Sade kabuk içerik yoğunluğunu çözmüyor (yüksek güven, P1).** #8'in 1403px geniş görselinde kullanılmayan sağ alan ve tam genişlikte ekleme düğmeleri var. Sekmelerin sadeleşmesi iç sayfayı masaüstüne uygun hale getirmiyor. Daire özeti ile aile/araç gibi paralel bölümler genişte iki/üç kolona ayrılmalı; küçük ekranda tek sütuna dönmeli.
4. **Kapsam tekrarı (yüksek güven, P1).** #6 site seçimi geniş kartta yineleniyor. Ortak seçili siteyi içerik sayfasına taşı; tek/önceden seçilmiş siteyi kısa bağlam etiketiyle göster. Birden çok siteyle çalışabilen yöneticiye gerçek kapsam değiştirme olanağı kalmalı.
5. **Rol gereksinimi farklılığı (yüksek güven, P1).** `plate_recognition_view.dart` 1644–1670 sakin için misafir izin aracı sunuyor; yeni kullanıcı isteği kalıcı kişisel araç onayı. Bu yalnız etiket değişikliği değildir; mevcut kişi/araç onay akışı yeniden kullanılmalı, API izinleri eşleşmeli.
6. **Bağlam adresi deep-link değil (yüksek güven, P2).** `PLATFORM_GERI_BILDIRIM.md` geçici adresleri bağlam referansı olarak tanımlıyor. Kullanıcı “adres”i yeniden açılabilir link sanabilir. Şimdilik “Sayfa referansı” diye açıkla; gerçek deep-link yapılırsa rol ve site kontrolü yeniden uygulanmalı.

## Birincil web kaynakları ve projeye uyarlama

- [Condo Control: sakin servis talepleri](https://support.condocontrol.com/hc/en-us/articles/4766968577051-Service-Requests-Creating-Requests-Resident-Video-Guide): Kullanıcının talebi oluşturduğu liste aynı zamanda arama, güncelleme ve tamamlanma durumuna dönüş yeri. Bizim çıkarımımız: geri bildirim formu ayrı bir çıkmaz sokak olmamalı; Gönderdiklerim ile geri dönüş sağlanmalı. Bu üretici kılavuzudur, bağımsız başarı ölçümü değildir.
- [GOV.UK: confirmation pages](https://design-system.service.gov.uk/patterns/confirmation-pages/): İşlem sonrası referans, sonraki adım ve geri dönülebilen kayıt sunar. Uyarlama: yalnız kısa toast yerine kayıt numarası ve geçmişi açma eylemi; gerçekleşmeyen yanıt tarihi vaat edilmez. Kaynak Open Government Licence v3.0 belirtir.
- [Atlassian: navigation reference guide](https://support.atlassian.com/navigation/docs/navigation-reference-guide/): Ürünler arası tutarlı gezinme, kullanıcının konumunu kaybetmemesi için tasarlanıyor. Uyarlama: dört ana konu ve iç sayfa başlığı aynı görev sözlüğünü kullanmalı; site kapsamı her içerikte tekrar sorulmamalı.
- [Atlassian: navigation best practices](https://support.atlassian.com/navigation/docs/navigation-best-practices/): Sık kullanılan hedeflerin görünür, nadir hedeflerin gizlenebilir ve gezinme alanının daraltılabilir olması açıklanıyor. Uyarlama: sakin ile yöneticiye aynı uzun menü verilmesin; geniş ekranda iş alanı büyüsün. Tercihler kişiye ait olmalı, site genelini değiştirmemeli.
- [IBM Carbon: Data table](https://www.carbondesignsystem.com/building-blocks/core/components/data-table/guidelines): Veri tabloları yoğun kayıtları karşılaştırmak, aramak ve satır eylemlerini bağlamında sunmak için kullanılıyor. Genişlik ve satır yüksekliği iş türüne uyarlanıyor. Uyarlama: geri bildirim geçmişi/finans gibi iş ekranlarında dev kart yığını yerine okunaklı satırlar; detay gerektiğinde açılır. Mobil dokunma hedefini küçültmek bu önerinin parçası değildir.
- [Microsoft Fluent 2: Layout](https://fluent2.microsoft.design/layout): Yakınlık, tutarlı boşluk ve uyarlanabilir kolon ızgarası görsel ilişkiyi kurar; aşırı yoğunluk da aşırı boşluk kadar sorun yaratabilir. Uyarlama: tek ekran hedefini yazıyı küçülterek değil paralel içerikleri yan yana getirerek gerçekleştirmek; ana eylemler ve bağlam aynı bölgede kalır.
- [W3C: Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html): 320 CSS piksel eşdeğerinde bilgi/işlev kaybetmeden yeniden akış hedeflenir. Uyarlama: masaüstünde kompakt kolonlar, küçük genişlikte doğal tek sütun; sıfır kaydırma uğruna içerik saklama veya zorunlu yatay kaydırma yok.
- [W3C: WCAG 2.2 target size](https://www.w3.org/TR/WCAG22/#target-size-minimum): AA minimum 24×24 CSS piksel veya belirtilen aralık/istisna koşullarıdır. Bu alt sınır tasarım hedefi sayılmamalı; mevcut mobil 48dp hedefleri korunmalı. Uyarlama: boşluk kazanımı butonun dokunma alanından değil gereksiz tekrar, hero ve kolon dağılımından gelsin.

## Kabul ölçütleri

- Kullanıcı kendi yedi kaydını yönetici rolüne geçmeden bulabilir; başka kullanıcının kaydı veya eki açılamaz.
- Geniş ekranda Dairem özeti, aile ve araç bölümlerinin başlangıçları ilk görünümde bulunur; gövdedeki toplam kaydırma yüksekliği önceki görselle kıyaslanır.
- 320px ve 200% yazıda taşma olmaz; kaydırma gerekiyorsa içeriğe ulaşılır ve odak örtülmez.
- Sakin için Yeni Site ve misafir plaka yetkisi yeni gereksinime göre ele alınır; yönetici akışları yanlışlıkla kaldırılmaz.
- Site seçimi tek noktada yönetilir, site değişince eski async yanıt yeni siteye sızmaz.
- Kaynaklar tasarım ilhamıdır; görselde güzel görünme gerçek saha başarısı diye raporlanmaz. Görev süresi/tıklama sayısı ve önce-sonra görünür içerik karşılaştırmasıyla değerlendirilir.

Araştırma tamamlandıktan sonraki uygulama/deploy kanıtı bu belgeye varsayımla eklenmez; merkez değişiklik kaydı ve çalışma kanıtları ayrı tutulur.
