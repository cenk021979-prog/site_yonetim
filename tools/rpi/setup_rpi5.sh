#!/usr/bin/env bash
# ==============================================================================
# Raspberry Pi 5 (Debian 12 Bookworm ARM64) Ortam Hazırlık Betiği
# ==============================================================================
# Bu betik Raspberry Pi 5 üzerinde Flutter Linux ve donanım hızlandırma
# kütüphanelerini kurar, kullanıcı izinlerini ayarlar.
# ==============================================================================

set -e

echo "🍓 [1/4] Raspberry Pi 5 Paket Listesi Güncelleniyor..."
sudo apt update

echo "🍓 [2/4] Flutter Linux GTK3 ve Grafik Kütüphaneleri Kuruluyor..."
sudo apt install -y \
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  liblzma-dev \
  libstdc++-12-dev \
  libegl1-mesa-dev \
  libgles2-mesa-dev \
  libdrm-dev \
  libgbm-dev \
  libgpiod-dev \
  gpiod \
  openssh-server \
  curl \
  git

echo "🍓 [3/4] Kullanıcı İzinleri Ayarlanıyor (video, render, gpio)..."
sudo usermod -aG video,render,dialout "$USER" || true

echo "🍓 [4/4] SSH Servisi Kontrol Ediliyor..."
sudo systemctl enable --now ssh

echo ""
echo "✅ Raspberry Pi 5 ortamı başarıyla hazırlandı!"
echo "IP Adresiniz:"
hostname -I | awk '{print $1}'
echo "Geliştirici bilgisayarınızdan bu IP ile F5 yaparak uygulamayı doğrudan burada çalıştırabilirsiniz."
