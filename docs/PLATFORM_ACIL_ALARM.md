# Site içi Acil: Asansör ve Yangın

8 Kasım 2026 kullanıcı kararı: Acil ekranı sakinlerin site içi alarm oluşturduğu ekrandır. İki eylem vardır: **Asansör** ve **Yangın**. Telefon rehberi veya 112 arama akışı bu ekranın parçası değildir. Firmware, kapı açma ve mevcut telefon bileşenleri değiştirilmez.

## Kullanıcı akışı

- Asansör: kullanıcının bağlı olduğu site → Ekipman ve Bakım'daki aktif, `kind=asansor` kayıtlarının adları ve konumları → seçim anında alarm kaydı. Kayıtlı asansör yoksa bu açıkça belirtilir.
- Yangın: bağlı site → kayıtlı bloklar veya **Ortak alan** → konum seçimi sonrası alarm. Sunucu konum adını veritabanından alır. Başka sitenin bloğu ve konumsuz yangın alarmı reddedilir.
- Başlatma yalnız gerçek aktif sakin/daire bağıyla mümkündür. Sadece global kullanıcı rolü, kapı için verilmiş ek izin, görevli veya yönetici kaydı sakin sayılmaz. Yönetici modunda başlatma eylemi gösterilmez; yönetici ayrıca gerçek sakin bağı varsa sakin modunda kullanabilir.
- Ağ yanıtı belirsizse aynı işlem anahtarı korunur. Aynı anahtar ve içerik tek alarmı döndürür; anahtar farklı içerikte tekrar kullanılırsa `409 IDEMPOTENCY_CONFLICT` döner.

## Kim hangi bildirimi alır?

| Alıcı | Ön koşul | Davranış |
| --- | --- | --- |
| Güvenlik | Yönetici tarafından açık alarm ataması + o sitede güncel aktif `STAFF` üyeliği + aktif uygulama hesabı | Açık uygulamada sesli alarm |
| Asansör servisi | Açık site/firma/hesap ataması + asansörün `vendor_id` eşleşmesi + aynı sitede aktif asansör firması ve tarihleri geçerli aktif asansör sözleşmesi | Yalnız o firmanın asansör alarmında, açık uygulamada sesli alarm |
| Site/apartman yöneticisi | Güncel `site_manager_sites` veya aktif `SITE_OWNER` / `SITE_ADMIN` bağı | Kalıcı uygulama içi bildirim, varsa ikincil sessiz mobil push; alarm sesi yok |

Tüm personel güvenlik sayılmaz. Firma adı ve telefonu uygulama hesabı bağlantısı değildir. Yönetici, Ekipman ve Bakım → **Alarm alıcıları** bölümünde güvenliği mevcut personelden seçer; anlaşmalı servisi mevcut uygulama kullanıcı adı ve firmayla açıkça eşleştirir. Kullanıcı hesabı oluşturulmaz ve servise genel site, kapı, kişi, dosya veya finans yetkisi verilmez. Servis hesabı normal oturum açar; genel site listesinde o site bulunmasa da oturum kapsamındaki alarm alıcısı feed'i çalışır.

Aynı sitenin yöneticisi sesli alıcı atanamaz. Atama sonrasında yöneticiliğe geçerse sesli erişim güncel yetki denetimiyle kesilir. Yetki, personel ataması, firma/sözleşme ve asansör–firma bağı her feed ve işlem isteğinde yeniden denetlenir. Kaldırılan atama veya feshedilen/sona eren sözleşme eski alıcı kaydından kalıcı erişim sağlamaz.

Hesabın aktif/silinmemiş olmasının yanında e-posta doğrulaması tamamlanmış, onayı bekleyen/reddedilmiş olmaması gerekir; global süper kullanıcı alarm alıcısı sayılmaz. Aynı SQL uygunluk kuralı atama, alıcı seçimi, uygunluk göstergesi, feed, ACK ve ikincil mobil bildirimde kullanılır. İlk girişte zorunlu parola değiştirme mekanizması değiştirilmez. Gecikmiş bir GET yanıtı, bu sırada başarıyla verilmiş kişisel ACK'i geri alamaz veya alarm sesini yeniden başlatamaz.

Alıcı yokluğu alarm kaydını engellemez. Yanıtta `NO_SECURITY_ACCOUNT`, `NO_ELEVATOR_VENDOR`, `NO_ELIGIBLE_SERVICE_ACCOUNT`, `NO_MANAGER_ACCOUNT` uyarıları döner. Kullanıcıya **kayıt oluşturuldu / alıcı atandı** denir; bu sayılar **teslim edildi / ses çaldı / görüldü** anlamına gelmez.

## Teslim ve müdahale durumları

1. `emergency_alarms`: sunucu alarmı ve o andaki alıcı atamasını aynı transaction'da kaydeder.
2. Alıcı feed'i oturumdaki kişiye ait, hâlâ yetkili olduğu, kişisel olarak ACK vermediği ve kapanmamış alarmları döndürür.
3. `received`: uygulama alarm verisini aldığını sunucuya bildirir. GET okuma tek başına teslim kaydı yazmaz.
4. `played`: uygulamanın ses oynatmayı başlattığına dair cihaz raporudur. Fiziksel hoparlörden ses çıktığı veya bir insanın duyduğu kanıtı değildir. Yönetici bu işlemi yapamaz.
5. `ack`: alıcı **Gördüm** eylemiyle kendi uyarısını susturur. Güvenlik/servis ACK'i genel durumu `acknowledged` yapar, diğer alıcıların alarmını susturmaz. Yöneticinin gördüm işlemi müdahale edildi sayılmaz.
6. `resolve`: yetkili alıcı olayı kapatır; tüm alıcılarda sesli uyarı sonlanır. ACK çözüm/kapanışla aynı şey değildir.

## Platform sınırları

- Windows, web ve mobilde açık/ön planda çalışan uygulama yaklaşık beş saniyede bir feed'i okur; paketli WAV sesini kullanır. Yeniden bağlantıda ACK verilmemiş kayıt tekrar görülebilir.
- Tarayıcı otomatik ses engeli kullanıcı etkileşimi gerektirebilir. **Sesi etkinleştir/sına** işlemi ve başarısız oynatma durumu görünür olmalıdır. Kullanıcı/işletim sistemi sesi kapatabilir.
- Kapalı uygulamada veya arka planda sürekli alarm sesi bu sürümde garanti edilmez. Push yapılandırması, cihaz bildirim izni, internet ve işletim sistemi kısıtları ayrıca geçerlidir.
- Yönetici push'u mevcut FCM altyapısı üzerinden en iyi çabadır; yeniden denemeli kalıcı push kuyruğu değildir. `emergency_info` Android kanalı düşük önem, sessiz ve titreşimsizdir; APNs içeriğinde `sound` bulunmaz. Push sağlayıcısının kabulü teslim/okundu/oynatıldı olarak kaydedilmez. Asıl kayıt uygulama içi alıcı tablosudur.
- Bu çalışma SMS, WhatsApp, otomatik telefon araması veya resmi yardım hattı entegrasyonu eklemez.

## API

Tüm uçlar kimlik doğrulaması ve hız sınırı kullanır; yanıtlarda `Cache-Control: no-store` vardır. Modül kapısı yoktur.

Deneme oturumunda yeni site parametreli listeler yalnız demo siteyle sınırlıdır; `can_create:false` döner. Global alarm feed'i alıcı veritabanını sorgulamadan sessiz boş döner (`can_receive:false`, `can_sound:false`). Alarm oluşturma/teslim raporu/ACK/kapatma ve gerçek uygulama hesabına alıcı atama yazmaları denemede kapalıdır. Önceki adres/firma rehberi GET ve izinli firma PUT davranışı değişmez.

| Uç | Sözleşme |
| --- | --- |
| `GET /app/emergency/sites` | `{sites:[{site_code,site_name,address,city,district,can_create:true,can_edit:false}]}`; yalnız aktif sakin siteleri |
| `GET /app/emergency/sites/:siteCode/elevators` | `{elevators:[{id,name,location}]}`; aynı site sakin yetkisi + aktif asansörler |
| `GET /app/emergency/sites/:siteCode/locations` | `{locations:[{id:'site',name:'Ortak alan',block_id:null},{id:'block:34',name:'A Blok',block_id:34}]}` |
| `POST /app/emergency/alarms` | `{site_code,kind:'elevator',equipment_id,idempotency_key}` veya `{site_code,kind:'fire',location_id,idempotency_key}` |
| Alarm oluşturma yanıtı | `{alarm:{id,site_code,site_name,kind,equipment_id,equipment_name,location,status,created_at,sound_enabled:false},delivery:{security_assigned,service_assigned,manager_notified,warnings},replayed}`; sayılar alıcı kaydıdır |
| `GET /app/emergency/alarms` | `{alarms:[{...,sound_enabled,received_at,played_at}],can_receive,can_sound,has_more}`; en yeni 100 açık/ACK edilmemiş kayıt; `sound_enabled` her alarmın alıcısına göre hesaplanır |
| `POST /app/emergency/alarms/:id/received` | Kişisel ilk alınma zamanı, idempotent |
| `POST /app/emergency/alarms/:id/played` | Kişisel ilk oynatma raporu, idempotent; yönetici `403 ALARM_SOUND_FORBIDDEN` |
| `POST /app/emergency/alarms/:id/ack` | Kişisel görüldü; diğer alıcıları susturmaz |
| `POST /app/emergency/alarms/:id/resolve` | Alarmı kapatır; güncel alıcı yetkisi şart |
| `GET /manager/sites/:siteCode/emergency/responders` | `{responders:[{id,user_code,user_name,login_name,role,vendor_id,vendor_name,eligible}],security_candidates:[{user_code,user_name}],vendors:[{id,name,has_active_contract}]}`; yalnız yönetici/süper |
| `PUT /manager/sites/:siteCode/emergency/responders` | `{responders:[{role:'security',user_code},{role:'elevator_service',login_name,vendor_id}]}`; tüm liste yerine yazılır, boş liste atamaları kaldırır; en çok 30 hesap |

`idempotency_key`: 8–80 ASCII harf, rakam, `_` veya `-`. Kullanıcı başına yeni alarm sınırı: dakikada 6, saatte 60; aynı anahtarın yeniden okunması yeni alarm sayılmaz. Aynı kullanıcı için transaction kilidi sayım yarışını engeller. Atama değiştirme ve alarm alıcılarını seçme aynı site transaction kilidini kullanır. Kullanıcı metni, telefon ve ses içeriği audit ayrıntılarına yazılmaz; yalnız kimlik/tür/adet vardır.

## Şema, test ve dağıtım

Migration `128_emergency_alarms.sql`: `emergency_responders`, `emergency_alarms`, `emergency_alarm_recipients` ve indeksler; eski tabloları/satırları değiştirmez. Tek kaynak `server/src/modules/emergency_alarm_schema.js`; normal açılışta mevcut nesneler için DDL/kilit alınmaz. `db.js`, eski `ensureEmergencySchema` sonrasında yeni şemayı hazırlar. Kullanıcı ve site silme FK politikalarıyla temizlenir; kaynak asansör silinse bile ad/konum anlık görüntüsü kalır.

`node --test test/emergency.test.js test/emergency_alarms.test.js`: eski API, yeni girdi, route ve şema denetimleri. `EMERGENCY_PG_TEST=1 node --test test/emergency_alarms.test.js`: ayrı bağlantıda **geçici tablolarla** gerçek PostgreSQL doğrulaması; gerçek sitelere alarm veya bildirim göndermez. Test oturumu kapanınca geçici veriler kaldırılır.

Backend değişikliği birlikte VPS'e dağıtılır; migration, PM2, `/health`, veritabanı/MQTT ve kimliksiz alarm uçlarında 401 doğrulanır. Saha ses/duyulma kontrolü gerçek cihaz ve tarayıcıda ayrıca yapılır; sunucu testleri onun yerine geçmez.
