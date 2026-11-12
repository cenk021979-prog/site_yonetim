# Acil durum: sakinlerin site içi alarm ekranı

8 Kasım 2026 kullanıcı kararıyla önceki 112/telefon rehberi tasarımı değiştirildi. Güncel Acil ekranında yalnız **Asansör** ve **Yangın** eylemleri vardır. Güncel ve bağlayıcı uygulama/API sözleşmesi: [PLATFORM_ACIL_ALARM.md](PLATFORM_ACIL_ALARM.md).

- Sakin Asansör'e dokunur, sitede kayıtlı aktif asansörlerin adları/konumları gelir; seçimi alarm oluşturur.
- Sakin Yangın'a dokunur, kayıtlı blok veya Ortak alan seçer; seçilen konumla alarm oluşturulur.
- Yönetici modunda alarm başlatma yoktur. Görevli veya servis hesabı, atanmış alarmı alabilir; bu atama kişiyi sakin yapmaz.
- Güvenlik ve varsa ilgili asansörün anlaşmalı servisi açık uygulamada sesli alarm alır. Site/apartman yöneticisi uygulama içi bildirim ve varsa sessiz mobil bildirim alır; alarm sesi almaz.
- Yönetici Ekipman ve Bakım içindeki Alarm alıcıları bölümünden aktif güvenlik personelini ve mevcut servis uygulama hesabını atar. Firma adı/telefonu tek başına dijital alıcı değildir. Servise genel site/kapı yetkisi verilmez.
- Kayıt, cihazın veriyi alması, ses oynatma raporu, insanın Gördüm eylemi ve olayın kapanması ayrı durumlardır. Alıcı yokluğu/bağlantı/ses engeli dürüstçe gösterilir.
- Windows/web/mobil açık uygulamada yaklaşık 5 saniyelik yoklama ve paketli ses kullanılır. Kapalı uygulama/arka plan/işletim sistemi veya tarayıcı engeli altında ses garantisi verilmez.

## Eski istemci uyumluluğu

Eski `GET /app/emergency` ve `PUT /manager/sites/:siteCode/emergency` uçları ile `site_emergency_info` tablosu (migration107) korunur. Bunlar eski uygulamaların site adresi ve bakım firması telefonunu okuması/düzenlemesi içindir; yeni alarm alıcısı ataması veya alarm teslimi anlamına gelmez.

Yeni alarm akışı migration128 ile ayrı ekleyici tablolar ve `/app/emergency/sites`, `/app/emergency/alarms`, yönetici `/emergency/responders` uçlarını kullanır. Yeni uçların yetkileri, hata kodları, testleri ve dağıtım notları güncel sözleşmede ayrıntılıdır.

Kişi kartları gibi diğer ekranlardaki telefon arama bileşenleri bu çalışmada kaldırılmaz; Acil alarm ekranına geri eklenmez. Bu çalışma 112, SMS, WhatsApp veya otomatik telefon araması entegrasyonu yapmaz.
