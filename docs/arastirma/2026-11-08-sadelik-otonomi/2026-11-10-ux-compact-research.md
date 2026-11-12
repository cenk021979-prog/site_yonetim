# İşlevli sadelik ve ekran alanı — 10 Kasım 2026

Durum: araştırma ve mevcut uygulama incelemesi. Bu rapor kendi başına bir kod değişikliği, yayın veya kullanılabilirlik testi sonucu değildir. Kod bulguları 10 Kasım inceleme anını, PNG'ler 9 Kasım son yayın doğrulamasını temsil eder. Sonraki kod değişikliklerinde satırlar yeniden doğrulanmalıdır.

Sonraki uygulama, geri bildirim bazlı sonuç ve yayın kanıtları ayrı [10 Kasım uygulama kaydında](2026-11-10-feedback-design-record.json) ve [görsel katalogda](modern-sade-kaporta-katalog.html#compact-feedback-20261110) tutulur. Aşağıdaki ilk inceleme bulguları tarihçe olarak korunmuştur.

## Sonuç

Mevcut Sade görünüm işlemleri konuya ayırıyor; ancak geniş ekranı hâlâ uzun bir telefon listesi gibi kullanıyor. Kutucuk görünümünde de her alt kategori yeni bir satır/grup açtığından kullanılabilir yatay alan boş kalıyor. Gerekli adım yazıyı küçültmek değil; aynı bilgiyi üç kez başlıklandırmayı azaltmak, işlemleri daha iyi yerleştirmek ve bağlama ait bilgiyi işin yanında göstermektir.

Kullanıcının “mümkün olduğunca kaydırmadan” hedefi normal masaüstünde ölçülebilir bir hedef olmalı. 320 piksel ve büyütülmüş yazıda her şeyi tek ekrana zorlamak bilgi kesmeye veya dokunma alanlarını küçültmeye yol açar. O durumda okunabilir dikey akış korunmalıdır. Bu, kullanıcının hedefinden vazgeçmek değil, hedefi ekran kapasitesine göre uygulamaktır.

## Gerçek uygulamada gözlenenler

| Bulgu | Kanıt | Öneri |
|---|---|---|
| Evim kutucuklarında dört işlem üç ayrı kategori sırasına dağılıyor. 1100 genişlikte ekranın sağında büyük boşluk kalıyor. | `lib/ui/widgets/simple_navigation.dart:64` kategori başına `_SimpleActions`; `:110` kolon hesabı. `simple-apartmentOwner-1100-light-home-tiles.png` doğrudan incelendi. | Tek uyarlanır ızgara; kategori küçük kart etiketi veya seçilebilir süzgeç. Kategori sayısı kadar boş satır üretme. |
| Kutucukların içerik alanı en az 88, dış dolgusu toplam 32 piksel; az içerikli kart da yaklaşık 120 piksel yüksekliğinde. | `simple_navigation.dart:117`. Aynı Evim PNG'si. | İçeriğe göre büyüyen daha kısa kart; sabit yüksekliğe metin sıkıştırma yok. Normal yazıda 80–96 civarı görev kartı bir prototip hedefi olabilir, norm değildir. |
| Liste görünümü 1100 genişliğin tamamını tek kısa metin + uzaktaki ok için kullanıyor; 850 yüksekliğinde yalnız birkaç tam işlem görülebiliyor. | `simple_navigation.dart:100` ListTile dikey 8 dolgu. Yönetim/Site liste PNG'leri doğrudan incelendi. | Masaüstünde iki kolon kompakt görev listesi; mobilde bir kolon. Görev sırası klavye ve ekran okuyucu için görsel sırayla tutarlı kalsın. |
| Aynı seçili bölüm app bar, seçili sekme ve gövde başlığında tekrar ediyor. Başlık ve alt başlık aralıkları toplam yüksekliği artırıyor. | `simple_navigation.dart:50`, `:60`, `:65`. Tüm incelenen PNG'ler. | Tek güçlü içerik başlığı; sekme satırına bağlanan görünüm denetimi. Kullanıcının hangi bölümde olduğunu anlaması korunurken ayrı yüksek başlık bandını azalt. |
| Bugün sakin görünümü yalnız “Bildirim özeti henüz alınamadı” ve yönlendirici açıklama gösterebiliyor. Ekran boş fakat yararlı bir karar sağlamıyor. | `simple_navigation.dart:48–54`, `:136` sonrası; `simple-apartmentOwner-1100-light-today.png`. Bu PNG bir test durumudur; canlıda herkesin bu durumu gördüğü iddia edilmiyor. | Var olan gerçek veriyle kısa durum özeti. Bilgi alınamadıysa açık hata/yenileme; diğer sekmelerin işlem kartlarını yeniden çoğaltma. Sahte sıfır borç veya “her şey yolunda” üretme. |
| Masaüstü gövde genişliği 1100 ile sınırlı; geniş monitörde görev alanı bundan yararlanmıyor. | `lib/ui/pages/home_page.dart:6878` maxWidth1100. | Yalnız Sade görev panosuna uygun daha geniş sınır veya esnek kolonlar değerlendirilsin; formlar ve uzun metinler kontrolsüz genişletilmesin. |
| Yönetim birçok ilgisiz işi tek ana konuda topluyor. Konular korununca dahi keşfedilebilirlik için ikinci seviye hafif bir düzen gerekiyor. | `lib/ui/helpers/simple_navigation.dart:15–23`, varsayılan tüm diğer öğeler Yönetim. | Konu içinde hızlı arama ve kısa kategori süzgeci; tüm işlemler erişilebilir kalsın. Arama/süzgeç yalnız zaten yetkili öğeler üzerinde çalışsın. |

İncelenen altı gerçek Flutter görseli: `simple-apartmentOwner-1100-light-home-tiles.png`, `simple-siteManager-1100-light.png`, `simple-apartmentOwner-320-light.png`, `simple-apartmentOwner-1100-light-today.png`, `simple-siteManager-1100-light-tiles.png`, `simple-apartmentOwner-1100-light.png`. Hepsi `work/simple-navigation-refinement-2026-11-09/` altındadır. Telefonda fiziksel etkileşim veya canlı kullanıcı testi yapılmadı.

## Kaynaklar ve yeniden kullanım

Kütüphanede kaynakların tam metni veya yeniden dağıtılan görsel paketi bulunmaz. Bağlantılar, özgün kısa özetler ve öneriler saklandı. Üç resmi görsel yalnız yerel araştırma incelemesi için `work/ux-compact-2026-11-10/` altına alındı ve `view_image` ile fiilen incelendi; ürün varlığına veya dağıtım paketine katılmadı. Görsel sayfalara erişmek telifli ekranı üründe kullanma hakkı vermez. JSON eşlikçisi kalıcı UXC kimliklerini içerir.

| Kimlik | Birincil kaynak | Projeye çıkarım |
|---|---|---|
| UXC-01 | [Microsoft Fluent 2 — Layout](https://fluent2.microsoft.design/layout) | Geniş alanda dikey parçaları yatay düzenlemek ve boşlukları ekran boyuna göre ayarlamak, üstte daha fazla yararlı bilgi gösterebilir. Tutarlı boşluk ilişkileri korur; gereksiz genişlik veya aşırı sıkışıklık amaç değildir. Sayfadaki Reposition/Reflow örnekleri görsel referanstır. |
| UXC-02 | [IBM Carbon — Data table](https://www.carbondesignsystem.com/building-blocks/core/components/data-table/guidelines) | Yoğunluk, satır/araç çubuğu ölçülerinin tutarlı seçimi ve gerekli ayrıntının açılabilmesiyle yönetilir. Tablo için verilen küçük ölçüler dokunmatik modül kartına aynen taşınmamalı. Sayfadaki geniş/dar/yoğun grid örnekleri karşılaştırılabilir. |
| UXC-03 | [NN/g — Aesthetic and Minimalist Design](https://www.nngroup.com/articles/aesthetic-minimalist-design/) | Sadelik gerekli işlevlerin bulunabilirliğini korumalı; görsel olarak boş olmak yeterli değil. Gürültü azaltılırken kullanıcı görevi tamamlayabilmeli. Araştırmacının birincil rehberidir; bizim uygulamamızın başarı testi değildir. |
| UXC-04 | [NN/g — Scrolling and Attention](https://www.nngroup.com/articles/scrolling-and-attention/) | 2018 göz izleme çalışması ilk ekranın önemini destekler; çalışmadaki oranlar bu uygulamanın ölçümü değildir. En sık işlerin üstte kalması mantıklı; “insanlar hiç kaydırmaz” sonucu çıkarılamaz. |
| UXC-05 | [Linear — Display options](https://linear.app/docs/display-options) | Aynı kayıtlar liste/pano ve kişisel görünüm tercihleriyle sunulabilir. Görüntülenen özellik sayısı ile kayıt filtresi ayrı konulardır. Bizde liste/kutucuk ve kullanıcı tercihi korunmalı; arama işlevi görünüm tercihiyle karıştırılmamalı. |
| UXC-06 | [Android — Canonical layouts](https://developer.android.com/develop/ui/views/layout/canonical-layouts) | Geniş ekran liste ve ayrıntıyı yan yana, dar ekran sıralı gösterebilir. Gelecekte geri bildirim kutusu, daire/kişi ve talepler için uygulanabilir. Yeni bir tasarım, kayıt seçimini ve form durumunu ekran boyu değişince kaybetmemeli. |
| UXC-07 | [W3C — Reflow](https://www.w3.org/WAI/WCAG22/Understanding/reflow.html) | Daraltma/büyütmede bilgi ve işlev kaybı olmamalı. Normal metni iki yönde kaydırmaya zorlamak önlenmeli. Tek ekran amacı büyütmede içerik kesme gerekçesi değildir. Bu açıklama belgesi tek başına tüm WCAG uygunluğu belgesi değildir. |
| UXC-08 | [W3C — Target Size Minimum](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html) | WCAG2.2 AA'nın istisnalı 24 CSS px asgari hedefi, rahat mobil tasarım hedefiyle aynı değildir. Bu projede önemli dokunma kontrolleri için 48 Flutter mantıksal piksel hedefi korunmalı; boşluk azaltmak hedefleri küçültmek anlamına gelmesin. |
| UXC-09 | [Linear — A calmer interface for a product in motion](https://linear.app/now/behind-the-latest-design-refresh) | 12 Mart 2026 tasarım yenilemesi, yoğun bilgiyi korurken gezinmenin görsel ağırlığını azaltmayı ve eylemlerin yerini tutarlı kılmayı açıklıyor. Üreticinin tasarım süreci anlatımıdır, bağımsız başarı ölçümü değildir. |

Fiilen incelenen dış görsellerden alınacak ilkeler:

- Linear başlık şemasında uygulama konumu ile görünüm işlemleri ayrı ve öngörülebilir satırlarda. Projede genel site/hesap seçimi ile yerel arama/liste ayarları karıştırılmamalı; fakat aynı başlık üçüncü kez tekrarlanmamalı.
- Linear eski/yeni sekme karşılaştırmasında yeni sekmeler içerikleri kadar yer tutuyor, aktif öğe ayırt ediliyor. Projede dört konu ortalı ve içerik genişliğinde kalabilir; örneğin ikon-only sekmelerini ise acemi kullanıcıya aynen aktarmamalıyız.
- Fluent modular-grid diyagramında yatay ve dikey hücreler ortak hizaya oturuyor. Projede birbirinden kopuk kategori satırları yerine ortak kolon çizgileri ve tutarlı aralıklar kullanılabilir. Bu bir gerçek ürün ekranı değil, düzen şemasıdır.

Bu kaynaklar tasarım sistemi rehberleri, üreticinin kendi ürün belgesi ve doğrudan araştırmadır. Linear, Microsoft veya Carbon için “en başarılı tasarım” sıralaması yapılmadı. Güzel ekranın görev başarısını kanıtlamadığı ayrıca dikkate alındı.

## Uygulanabilir tasarım çerçevesi

1. Dört ana konu korunur. Bir modülün bir ana konusu vardır; arama/süzgeç bu yetkili kümede çalışır. Acil alarm görünürlüğü ve rol sınırları korunur.
2. Konu üst alanı tek kompakt araç satırında başlık, isteğe bağlı işlem arama ve etiketli liste/kutucuk denetimi taşır. Normal masaüstünde dikey yüksekliği sınırlar; dar ekranda Wrap ile büyür.
3. Kutucuklar tek gridde sırayla yerleşir; kategori bilgisi kartta hafif etiket olabilir. Metin, küçük işlev ikonu, bekleyen durum sayısı ve odak sınırı yeterlidir. Dekoratif resim kartın işini bastırmaz.
4. Liste bir satırda iş adı, anlamlı kısa açıklama ve durum sayısı sunar. Büyük ekranda iki kolon; küçük/büyük yazıda bir kolon. Açıklamalar önemli farkları açıklıyorsa gelişigüzel kaldırılmaz.
5. Daire/kişi, tahsilat ve geri bildirim gibi kayıt ekranları daha sonra geniş ekranda liste–ayrıntı düzeniyle geliştirilebilir. Bu rapor bu iş mantıklarının uygulanmış olduğunu söylemez.
6. Boş/yükleniyor/hata durumları kısa, dürüst ve bağlamlıdır. Geri bildirim gönderme ile kişinin eski notlarını görmesi aynı özellik değildir; görünür bir “Geri bildirimlerim” erişimi değerlidir. Bu son madde bağımsız geri bildirim akışı incelemesiyle kesinleştirilmelidir.

## Kabul ölçütleri

- 1366×768 ve 1440×900, normal yazı: aynı rol/veri ile önce/sonra görünen tam işlem sayısı ve ilk işin dikey konumu ölçülsün. İşe yarayan alan artışı sayı olarak raporlansın; varsayımsal yüzde verilmesin.
- Örnek Evim dört işlemi normal masaüstünde tek grid satırına veya kısa iki kolon listeye sığabilsin. Yönetim için tüm yetkili modüller kaybolmadan keşfedilsin; 48 öğeyi her koşulda tek ekrana sığdırma sözü verilmesin.
- 390×844 normal yazı ve 320 genişlikte 2× yazı: kesilen başlık, yatay içerik taşması, erişilemeyen son işlem olmasın. Dikey kaydırma gerektiğinde çalışsın.
- Kutu/liste seçimi saklansın; değiştirildiğinde yetki, rozet, hedef ekran ve kayıt sayısı aynı kalsın. Klavye odağı görünür, işlem alanı yeterli olsun.
- Sayısal alarm/bildirim/borç durumu yalnız mevcut gerçek veriden gelsin; hata başarı gibi gösterilmesin. Yenileme ve site değişiminde önceki kapsam verisi karışmasın.
- En az üç gerçek görevde (gönderdiğim notu bulma, aidat ekranına erişme, asansör/yetkili alarm akışını bulma) doğru hedefe gitme adımı ve kullanıcı yardımı gereksinimi ölçülsün. Ekran görüntüsü bu testlerin yerine geçmez.

Yeniden kullanım örneği: “UXC-01, UXC-05 ve UXC-07 ilkeleriyle geri bildirim kutusunu masaüstünde liste–ayrıntı, telefonda okunabilir tek kolon olarak planlayalım.”
