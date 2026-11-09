# 🍓 Raspberry Pi 5 Geliştirme ve Canlı Çalıştırma Kılavuzu

Bu kılavuz, `site_yonetim` projesini var olan hiçbir özelliği (Windows, Web, Android, ESP32) bozmadan **Raspberry Pi 5 (Linux ARM64)** üzerinde doğrudan çalıştırmak, test etmek ve VS Code üzerinden canlı hata ayıklama (Hot Reload) yapmak için hazırlanmıştır.

---

## 🚀 1. Windows Geliştirici Tarafı (Tek Tıklama Kurulum)

Windows bilgisayarınızdaki VS Code veya Flutter cihaz seçicisine (`Available Devices`) Raspberry Pi 5'i eklemek için:

1. PowerShell'de şu betiği çalıştırın:
   ```powershell
   .\tools\rpi\enable_rpi5_device.ps1
   ```
2. VS Code durum çubuğundaki (sağ alt köşe) cihaz seçicide **`Raspberry Pi 5 (linux-arm64)`** cihazının belirdiğini göreceksiniz.
3. Çalıştırmak için cihazı seçip `F5` tuşuna basmanız yeterlidir.

*(Eğer Raspberry Pi'nizin IP adresi `raspberrypi.local` yerine farklı bir IP ise, `.\tools\rpi\enable_rpi5_device.ps1 -RpiHost 192.168.1.xxx` şeklinde çalıştırabilirsiniz).*

---

## 🖥️ 2. Raspberry Pi 5 Tarafı (Tek Seferlik Ortam Hazırlığı)

Raspberry Pi 5 üzerinde (Raspberry Pi OS 64-bit Bookworm):

1. Depodaki kurulum betiğini çalıştırın:
   ```bash
   chmod +x tools/rpi/setup_rpi5.sh
   ./tools/rpi/setup_rpi5.sh
   ```
2. Bu betik:
   - GTK3, EGL, Mesa ve DRM/GBM grafik kütüphanelerini kurar.
   - GPIO (`libgpiod`) ve video donanım hızlandırma yetkilerini verir.
   - SSH servisini hazır hale getirir.

---

## ⚡ 3. Canlı Hot Reload ve Hata Ayıklama

- Windows üzerinden `F5` (veya `flutter run -d raspberry-pi-5`) dendiğinde uygulama Raspberry Pi'ye aktarılır ve tam ekran çalıştırılır.
- Kodda değişiklik yapıp `r` tuşuna basıldığında (Hot Reload), Raspberry Pi ekranındaki arayüz **1 saniyede** güncellenir.
- `R` tuşu ile tam baştan başlatma (Hot Restart) yapılabilir.

---

## 🛡️ 4. Geriye Dönük Uyumluluk Güvencesi (Kural 2 ve Kural 3)

- **Mevcut Sahayı Etkilemez:** Windows uygulaması, mobil istemciler ve sahada aktif olan ESP32-C3 / ESP32-WROOM cihazları bağımsız donanım hedefleridir (`hardware_target`).
- **İzole Platform Kontrolü:** Kod içerisindeki platform ayrımı (`Platform.isLinux` vs `Platform.isWindows`) sayesinde Windows tarafındaki D3D11VA GPU hattı olduğu gibi korunur; Linux tarafında ise GTK3 ve DRM pencereleri kullanılır.
