# ==============================================================================
# Raspberry Pi 5 Flutter Custom-Device Kurulum Betiği
# ==============================================================================
# Bu betik, Windows geliştirici bilgisayarınızda Flutter custom-devices özelliğini
# etkinleştirir ve Raspberry Pi 5'i (Linux ARM64) VS Code cihaz seçicisine ekler.
# ==============================================================================

param(
    [string]$RpiHost = "raspberrypi.local",
    [string]$RpiUser = "pi"
)

Write-Host "🍓 Raspberry Pi 5 Flutter Custom-Device Kurulumu Başlatılıyor..." -ForegroundColor Cyan

# 1. Flutter Custom-Devices özelliğini aç
Write-Host "1. Flutter Custom-Devices özelliği açılıyor..." -ForegroundColor Yellow
flutter config --enable-custom-devices

# 2. AppData yolu ve JSON dosyasını hazırla
$appData = [System.Environment]::GetFolderPath([System.Environment+SpecialFolder]::ApplicationData)
$configPath = Join-Path $appData ".flutter_custom_devices.json"

Write-Host "2. Hedef yapılandırma dosyası: $configPath" -ForegroundColor Yellow

$rpiConfig = @{
    id = "raspberry-pi-5"
    label = "Raspberry Pi 5"
    sdkNameAndVersion = "Raspberry Pi OS (Bookworm ARM64)"
    platform = "linux-arm64"
    enabled = $true
    ping = @("ping", "-n", "1", "-w", "500", "127.0.0.1")
    pingSuccessRegex = "[<=]\d+ms"
    postBuild = $null
    install = @("scp", "-r", "-o", "BatchMode=yes", '${localPath}', "$RpiUser@$RpiHost`:/tmp/`$appName")
    uninstall = @("ssh", "-o", "BatchMode=yes", "$RpiUser@$RpiHost", "rm -rf /tmp/`$appName")
    runDebug = @("ssh", "-o", "BatchMode=yes", "$RpiUser@$RpiHost", "/tmp/`$appName/`$appName")
    forwardPort = @("ssh", "-o", "BatchMode=yes", "-o", "ExitOnForwardFailure=yes", "-L", '127.0.0.1:${hostPort}:127.0.0.1:${devicePort}', "$RpiUser@$RpiHost", "echo 'Port forwarding success'; read")
    forwardPortSuccessRegex = "Port forwarding success"
    screenshot = $null
    readLogs = $null
}

$rootObj = @{
    "custom-devices" = @($rpiConfig)
}

$jsonContent = $rootObj | ConvertTo-Json -Depth 10
Set-Content -Path $configPath -Value $jsonContent -Encoding UTF8

Write-Host "3. Cihaz listesi doğrulanıyor..." -ForegroundColor Yellow
flutter devices

Write-Host "`n✅ Raspberry Pi 5 başarıyla eklendi!" -ForegroundColor Green
Write-Host "VS Code sağ altındaki cihaz seçiciden 'Raspberry Pi 5'i seçip F5 ile doğrudan çalıştırabilirsiniz." -ForegroundColor Cyan
