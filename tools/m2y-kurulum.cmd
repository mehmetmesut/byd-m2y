@echo off
rem M2Y Kurulum - BYD Seal U DM-i icin M2Y uygulamalarini kablosuz ADB ile kurar.
rem Copyright (C) 2026 Yesil Donusum Muhendisi - M2Y. GPL-3.0. https://byd.mehmetmesut.com
chcp 65001 >nul
title M2Y Kurulum
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = Get-Content -Raw -Encoding UTF8 -LiteralPath '%~f0'; $i = $s.LastIndexOf('#M2Y-PS#'); Invoke-Expression $s.Substring($i + 8)"
echo.
pause
exit /b
#M2Y-PS#
$ErrorActionPreference = 'Stop'
$base = 'https://byd.mehmetmesut.com/indir/'
$work = Join-Path $env:LOCALAPPDATA 'M2Y'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$ProgressPreference = 'SilentlyContinue' # the progress bar makes Invoke-WebRequest many times slower
# Arac hazirligi: BYD'nin stok yukleyicisi aracta acilan her APK'yi durdurur. Kilitsiz yukleyici BYD imzalidir,
# bu site barindirmaz; herkese acik topluluk deposundan indirilir ve SHA-256 ile dogrulanir.
$unlocked = @{ Name = 'PackageInstallerUnlocked.apk'; Sha = 'd16175120b0aa051fc396a73510dc1fd43465e1c23e62f7f920af09ef6b276e9'
    Url = 'https://raw.githubusercontent.com/ahmada3mar/BYD/main/PackageInstaller.apk' }
$obtainium = @{ Name = 'Obtainium_1.7.2_arm64-v8a.apk'; Sha = 'f6c83f6e948a701746a0fd7fb52e6ee485b3ca952e719f7cfa3d80567a1e2f13'
    Url = 'https://github.com/ImranR98/Obtainium/releases/download/v1.7.2/app-arm64-v8a-release.apk' }
Write-Host ''
Write-Host '  M2Y Kurulum - Yesil Donusum Muhendisi - M2Y' -ForegroundColor Cyan
Write-Host '  BYD Seal U DM-i (kablosuz ADB acik arac) icin'
Write-Host ''

function Get-Verified([string]$url, [string]$name, [string]$sha) {
    $dest = Join-Path $work $name
    Write-Host ''
    Write-Host "  $name indiriliyor..."
    Invoke-WebRequest -UseBasicParsing $url -OutFile $dest
    $stream = [System.IO.File]::OpenRead($dest)
    try { $hash = -join ([System.Security.Cryptography.SHA256]::Create().ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
    finally { $stream.Close() }
    if ($hash -ne $sha) { Remove-Item $dest; throw "$name dogrulanamadi (SHA-256 uyusmuyor), kurulmadi." }
    Write-Host '  SHA-256 dogru, kuruluyor...'
    $dest
}

function Install-Apk([string]$path, [string]$name) {
    $ErrorActionPreference = 'Continue' # adb reports failures on stderr; read them instead of aborting
    $out = (& $adb -s $ip install -r $path 2>&1 | Out-String)
    $ErrorActionPreference = 'Stop'
    if ($out -match 'Success') { Write-Host '  Kuruldu.' -ForegroundColor Green; return $true }
    Write-Host "  $name kurulamadi: $($out.Trim())" -ForegroundColor Red
    if ($out -match 'VERSION_DOWNGRADE') { Write-Host '  Aractaki surum bu dosyadan daha yeni; guncelleme gerekmiyor.' -ForegroundColor Yellow }
    if ($out -match 'UPDATE_INCOMPATIBLE') { Write-Host '  Aractaki kopya baska bir anahtarla imzali; zorlamayin.' -ForegroundColor Yellow }
    $false
}

# 1) adb: PATH'te yoksa Google'in resmi platform-tools paketi indirilir
$adb = (Get-Command adb -ErrorAction SilentlyContinue).Source
if (-not $adb) {
    $adb = Join-Path $work 'platform-tools\adb.exe'
    if (-not (Test-Path $adb)) {
        Write-Host '  ADB araclari indiriliyor (dl.google.com)...'
        $zip = Join-Path $work 'platform-tools.zip'
        Invoke-WebRequest -UseBasicParsing 'https://dl.google.com/android/repository/platform-tools-latest-windows.zip' -OutFile $zip
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($zip, $work)
        Remove-Item $zip
    }
}

# 2) aracin adresi
$ip = Read-Host '  Aracin Wi-Fi IP adresi (ornek 192.168.1.50)'
if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}(:\d+)?$') { throw 'Gecersiz IP adresi.' }
if ($ip -notmatch ':') { $ip = "${ip}:5555" }
& $adb connect $ip | Write-Host
$state = (& $adb -s $ip get-state 2>$null)
if ($state -ne 'device') { throw "Araca baglanilamadi ($ip). Aracta kablosuz ADB acik mi, ayni agda misiniz?" }

# 3) arac hazirligi (bir kez): kilitsiz yukleyici + Obtainium; sonrasi aracta, bilgisayarsiz
Write-Host ''
Write-Host '  Arac hazirligi (bir kez): kilitsiz paket yukleyici + Obtainium.'
Write-Host '  Sonra M2Y uygulamalarini aracta Obtainium ile kurar ve guncellersiniz; bilgisayar gerekmez.'
$prep = Read-Host '  Araci hazirlayalim mi? (E/h)'
if ($prep.Trim() -notmatch '^[hHnN]') {
    $f = Get-Verified $unlocked.Url $unlocked.Name $unlocked.Sha
    if (Install-Apk $f $unlocked.Name) { Write-Host '  Geri almak icin: adb uninstall com.android.packageinstaller (fabrika yukleyicisine doner).' }
    else { Write-Host '  Kilitsiz yukleyici olmadan Obtainium bu aracta kurulum yapamaz; uygulamalari asagidan bu betikle kurun.' -ForegroundColor Yellow }
    $f = Get-Verified $obtainium.Url $obtainium.Name $obtainium.Sha
    if (Install-Apk $f $obtainium.Name) {
        & $adb -s $ip shell appops set dev.imranr.obtainium REQUEST_INSTALL_PACKAGES allow | Out-Null
        Write-Host '  Obtainium: bilinmeyen kaynak izni verildi. Arka planda guncelleme denetimi icin BYD Otomatik Baslatma listesinde izin verin.' -ForegroundColor Yellow
        Write-Host '  Aracta Cromite ile byd.mehmetmesut.com/#kurulum acin, "Tumunu Obtainium''a ekle" dugmesine dokunun.' -ForegroundColor Yellow
    }
}

# 4) uygulama listesi ve ozetler (SHA256SUMS.txt: "<sha256>  <dosya>")
$sums = @{}
(Invoke-WebRequest -UseBasicParsing ($base + 'SHA256SUMS.txt')).Content -split "`n" | ForEach-Object {
    if ($_ -match '^([0-9a-fA-F]{64})\s+\*?(\S+\.apk)\s*$') { $sums[$Matches[2]] = $Matches[1].ToLower() }
}
$files = @($sums.Keys | Sort-Object)
if (-not $files) { throw 'Indirme listesi alinamadi.' }
Write-Host ''
for ($n = 0; $n -lt $files.Count; $n++) { Write-Host ("  {0}) {1}" -f ($n + 1), $files[$n]) }
$pick = Read-Host '  Simdi buradan kurulacaklar (ornek 1,3 - bos birakirsaniz hepsi, 0 hicbiri)'
$chosen = if ($pick.Trim() -eq '0') { @() } elseif ($pick.Trim()) {
    $pick -split '[,\s]+' | Where-Object { $_ } | ForEach-Object {
        $k = 0
        if (-not [int]::TryParse($_, [ref]$k) -or $k -lt 1 -or $k -gt $files.Count) { throw "Gecersiz secim: $_ (1-$($files.Count) arasi bir sayi yazin)" }
        $files[$k - 1]
    }
} else { $files }

# 5) indir, SHA-256 ile dogrula, kur
foreach ($f in $chosen) {
    $dest = Get-Verified ($base + $f) $f $sums[$f]
    if (-not (Install-Apk $dest $f)) { continue }
    if ($f -like 'M2YTools*') {
        # M2Y Tools replaces M2Y Board and M2Y EQ
        & $adb -s $ip uninstall com.m2y.board 2>$null | Out-Null
        & $adb -s $ip uninstall com.m2y.eq 2>$null | Out-Null
        & $adb -s $ip shell ime enable com.m2y.tools/helium314.keyboard.latin.LatinIME | Out-Null
        & $adb -s $ip shell ime set com.m2y.tools/helium314.keyboard.latin.LatinIME | Write-Host
        Write-Host '  M2Y Tools: uygulamayi bir kez acin ve BYD Otomatik Baslatma listesinde izin verin (eski M2Y Board ve M2Y EQ kaldirildi).' -ForegroundColor Yellow
    }
    if ($f -like 'M2YBYD*') {
        & $adb -s $ip shell pm grant com.m2y.byd android.permission.ACCESS_FINE_LOCATION | Out-Null
        Write-Host '  M2Y BYD: konum izni verildi. Yolculuk kaydini acarsaniz BYD Otomatik Baslatma listesinde izin verin.' -ForegroundColor Yellow
    }
}

& $adb disconnect $ip | Out-Null
Write-Host ''
Write-Host '  Tamamlandi. Baglanti kapatildi.' -ForegroundColor Green
