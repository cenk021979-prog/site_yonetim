# Canlı sunucu dağıtımı (AGENTS.md kural 8)

VPS: `178.210.161.55` (SSH portu `22667`, kullanıcı `salihceylan`, **anahtarla giriş**), uygulama dizini `/var/www/site_kapi_kontrol/server`, PM2 süreç adı `kapi-api` (`npm start`), veritabanı Docker kapsayıcısı `site_kapi_kontrol_postgres`. Sunucuda başka projeler de çalışır (ev-api, teklif-pro-api, dijitarla…): yalnız `kapi-api` ve bu dizine dokunulur.

Betikler sır içermez. Parola/anahtar yazılmaz; `.env` dosyası dağıtım paketine GİRMEZ.

## SSH erişimi ve başarısız bağlantıda durma (2026-11-10 doğrulandı)

- Doğrulanan SSH kullanıcısı **`salihceylan`**, yöntem **mevcut SSH anahtarıyla giriş**tir. Canlı oturumda `id` çıktısı bu hesabı doğruladı.
- `cenkgude`, 2026-11-10 kontrolünde sunucunun kullanıcı kayıtlarında bulunmadı (`getent passwd cenkgude` sonuç vermedi). Uygulama kullanıcı adları SSH hesabı değildir; `cenkgude`, `cenk` veya `root` gibi alternatif hesaplarla giriş denemesi yapmayın.
- İlk erişim kontrolünü tek bağlantıyla, parola geri dönüşü kapalı olarak yapın:

  ```powershell
  ssh -o BatchMode=yes -o PreferredAuthentications=publickey -o IdentitiesOnly=yes -o ConnectionAttempts=1 -o ConnectTimeout=12 -p 22667 salihceylan@178.210.161.55 "id -un; hostname"
  ```

  Beklenen kullanıcı çıktısı `salihceylan` olmalıdır. Anahtar yeni bilgisayarda hazır değilse parola veya hesap tahminiyle devam etmeyin; yetkili SSH anahtarının kurulumunu doğrulayın. Anahtarın kendisini depoya koymayın.
- **İlk başarısız girişte durun.** `Permission denied`, `Connection reset` veya zaman aşımından sonra aynı işlemi döngüyle, paralel oturumlarla ya da başka kullanıcı/parola kombinasyonlarıyla tekrarlamayın. Önce istemci anahtarını ve sunucu konsolundan SSH/Fail2ban durumunu doğrulayın; neden giderildiğinde tek kontrol yapın. `Connection reset` tek başına parola hatasını veya IP engelini kanıtlamaz.
- Canlı kontrolde Fail2ban `sshd` engel süresi **3600 saniye (1 saat)** çıktı; önceki bağlantının dış IP'si engel listesindeydi. Bu, 2026-11-10 tarihli durumdur; ayar değişebilir. Kesin süre ve engel durumu, erişim varsa salt okunur `sudo -n fail2ban-client get sshd bantime` ve `sudo -n fail2ban-client status sshd` ile kontrol edilir.
- SSH girişi ile **sudo yetkilendirmesi ayrıdır**. Genel yönetim işlemleri sudo parolası isteyebilir; mevcut NOPASSWD sarmalayıcılar kendi kapsamlarında kalır. Gerekiyorsa anahtarla etkileşimli oturum (`ssh -tt -o BatchMode=yes -p 22667 salihceylan@178.210.161.55`) açıp `sudo -v` kullanın; yetkili parolayı yalnız gizli isteme girin ve ilk başarısız sudo doğrulamasında durun. Parolaları proje notlarına, komut satırına, betiklere veya günlüklere yazmayın. İş bitince `sudo -k` ile sudo yetki önbelleğini kapatın.

## Adımlar

1. **Yerel doğrulama:** `cd server && npm test && npm run lint` (hepsi geçmeli).
2. **Paket (yerelde, Git Bash):**
   ```bash
   cd server
   TS=$(date +%Y%m%d_%H%M%S)
   tar czf /tmp/kapi_deploy_$TS.tgz src scripts migrations package.json package-lock.json ecosystem.config.cjs .env.example
   sha256sum /tmp/kapi_deploy_$TS.tgz
   ```
   (`tar` Windows yolundaki `C:` önekini uzak sunucu sanır: `/c/...` biçimini kullanın veya `--force-local` verin.)
3. **Yükleme:**
   ```bash
   scp -P 22667 /tmp/kapi_deploy_$TS.tgz salihceylan@178.210.161.55:/home/salihceylan/
   scp -P 22667 deploy/remote_deploy.sh salihceylan@178.210.161.55:/home/salihceylan/kapi_remote_deploy_$TS.sh
   ssh -p 22667 salihceylan@178.210.161.55 "sha256sum /home/salihceylan/kapi_deploy_$TS.tgz"   # yereldeki özetle aynı olmalı
   ```
4. **Hazırlık (canlıya dokunmaz):** `ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS prepare"` → yedek (`~/backups/kapi_$TS/server_code.tgz` [.env ve data dahil], `db.sql.gz`), `node --check`, aşamalı `npm ci --omit=dev`. Çıktı `PREPARE_OK` ile bitmeli.
4b. **Şema provası (canlıya dokunmaz; migration içeren her dağıtımdan önce):** `scp -P 22667 deploy/remote_rehearse_schema.sh salihceylan@178.210.161.55:/home/salihceylan/kapi_rehearse_$TS.sh` ardından `ssh ... "bash /home/salihceylan/kapi_rehearse_$TS.sh $TS"`. Yedeği geçici veritabanına yükler, yeni `ensureDbSchema()`'yı iki kez çalıştırır ve çıktının sonunda `PROVA_OK` bekler (035/036 ve 038–041 varlık kontrolleri + sema parmak izi idempotansı; ayrıntı: `docs/OPERASYON_YEDEK_IZLEME.md` bölüm 14).
5. **İsteğe bağlı kuru çalıştırma (ACL):** yeni kodun ürettiği MQTT ACL'ini canlı DB ile görmek için sunucuda hazırlık dizininden `node scripts/sync_mqtt_acl.js --dry-run` çalıştırın. **`.env` dosyasını `source` ETMEYİN** (satırlardaki boşluklu değerler komut olarak çalışır).
6. **Etkinleştirme:** `ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS activate"` → `COMPANY_API_KEY` yoksa üretir, kodu yerleştirir, `node_modules` değiştirir, `pm2 restart kapi-api --update-env`, `/health` bekler. Sağlık başarısızsa **otomatik geri alma** yapılır.
7. **MQTT ACL (cihaz konuları değiştiyse):** yedekten sonra `sudo -n /usr/local/bin/kapi-mqtt-sync` (NOPASSWD sarmalayıcı; ACL'yi DB'den üretir ve mosquitto'yu yeniden yükler).
8. **Doğrulama:** `ssh ... 'bash -s' < deploy/remote_verify.sh` ve `pm2 logs kapi-api --lines 40 --nostream`. `remote_verify.sh` ayrıca yeni tabloları, temel modüllerin (AGENTS.md Kural 25; betikteki `CORE_MODULES`) her sitede açık olduğunu (açık olmayan site `SORUNLU` basılır) ve seçmeli modüllerin açık site sayısını (bilgi; dağıtım öncesi/sonrası değişmemeli), yeni uçların kimliksiz 401 verdiğini, FCM hizmet hesabı dosyasının izninin 600 olduğunu (yol/içerik yazdırılmaz) ve belge dizininin (var/700/yazılır/boş alan) durumunu denetler; `SORUNLU` ile başlayan satırlar dağıtım tamamlanmadan açıklanmalıdır.

## Geri alma

`ssh ... "bash /home/salihceylan/kapi_remote_deploy_$TS.sh $TS rollback"` — yedekteki kodu (data hariç) geri yükler, eski `node_modules`'i (`node_modules.old_$TS`) geri koyar ve PM2'yi yeniden başlatır. Şema değişiklikleri ekleyici olduğundan veritabanı geri alınmaz (gerekirse `db.sql.gz` ile elle). Modül birleştirmeleri (083 Kart Ödemesi -> Aidat ve Finans, 084 Belgeler -> Dosya Deposu) eski `card_payments` / `documents` `site_modules` satırlarını bilerek SİLMEZ (katalog yok sayar): otomatik geri almada önceki sürüm Belgeler ve Kart Ödemesi'nin açık/kapalı bilgisini bu satırlardan okumaya devam eder. 082'nin yazdığı temel modül satırları (anket, komşu panosu, ekipman, faaliyet raporu, dosya deposu) geri alınmış önceki sürümde o modülleri her sitede açık gösterir.

## Notlar

- `.env` değişiklikleri (ör. `COMPANY_API_KEY`) elle ve sırlar yazdırılmadan yapılır; aynı anahtar `company_qr_tool/.env` içine konur.
- Uzak-yalnız artık dosyalar (`src/services/membership_routes.js`, `migrations/apply_020.js`, `scripts/trigger_ota_wroom.js`) silinmez.
- Canlı `JWT_SECRET` (≥32 karakter), `JWT_EXPIRES_IN` ve `NODE_ENV=production` kararları kullanıcıya aittir (`BEKLEYEN_ISLER.md`).
