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
Write-Host ''
Write-Host '  M2Y Kurulum - Yesil Donusum Muhendisi - M2Y' -ForegroundColor Cyan
Write-Host '  BYD Seal U DM-i (kablosuz ADB acik arac) icin'
Write-Host ''

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

# 3) uygulama listesi ve ozetler (SHA256SUMS.txt: "<sha256>  <dosya>")
$sums = @{}
(Invoke-WebRequest -UseBasicParsing ($base + 'SHA256SUMS.txt')).Content -split "`n" | ForEach-Object {
    if ($_ -match '^([0-9a-fA-F]{64})\s+\*?(\S+\.apk)\s*$') { $sums[$Matches[2]] = $Matches[1].ToLower() }
}
$files = @($sums.Keys | Sort-Object)
if (-not $files) { throw 'Indirme listesi alinamadi.' }
Write-Host ''
for ($n = 0; $n -lt $files.Count; $n++) { Write-Host ("  {0}) {1}" -f ($n + 1), $files[$n]) }
$pick = Read-Host '  Kurulacaklar (ornek 1,3 - bos birakirsaniz hepsi)'
$chosen = if ($pick.Trim()) {
    $pick -split '[,\s]+' | Where-Object { $_ } | ForEach-Object {
        $k = 0
        if (-not [int]::TryParse($_, [ref]$k) -or $k -lt 1 -or $k -gt $files.Count) { throw "Gecersiz secim: $_ (1-$($files.Count) arasi bir sayi yazin)" }
        $files[$k - 1]
    }
} else { $files }
$ProgressPreference = 'SilentlyContinue' # the progress bar makes Invoke-WebRequest many times slower

# 4) indir, SHA-256 ile dogrula, kur
foreach ($f in $chosen) {
    $dest = Join-Path $work $f
    Write-Host ''
    Write-Host "  $f indiriliyor..."
    Invoke-WebRequest -UseBasicParsing ($base + $f) -OutFile $dest
    $stream = [System.IO.File]::OpenRead($dest)
    try { $hash = -join ([System.Security.Cryptography.SHA256]::Create().ComputeHash($stream) | ForEach-Object { $_.ToString('x2') }) }
    finally { $stream.Close() }
    if ($hash -ne $sums[$f]) { Remove-Item $dest; throw "$f dogrulanamadi (SHA-256 uyusmuyor), kurulmadi." }
    Write-Host '  SHA-256 dogru, kuruluyor...'
    $ErrorActionPreference = 'Continue' # adb reports failures on stderr; read them instead of aborting
    $out = (& $adb -s $ip install -r $dest 2>&1 | Out-String)
    $ErrorActionPreference = 'Stop'
    if ($out -notmatch 'Success') {
        Write-Host "  $f kurulamadi: $($out.Trim())" -ForegroundColor Red
        if ($out -match 'VERSION_DOWNGRADE') { Write-Host '  Aractaki surum bu dosyadan daha yeni; guncelleme gerekmiyor.' -ForegroundColor Yellow }
        if ($out -match 'UPDATE_INCOMPATIBLE') { Write-Host '  Aractaki kopya baska bir anahtarla imzali; once onu kaldirin.' -ForegroundColor Yellow }
        continue
    }
    Write-Host '  Kuruldu.' -ForegroundColor Green
    if ($f -like 'M2YBoard*') {
        & $adb -s $ip shell ime enable com.m2y.board/helium314.keyboard.latin.LatinIME | Out-Null
        & $adb -s $ip shell ime set com.m2y.board/helium314.keyboard.latin.LatinIME | Write-Host
    }
    if ($f -like 'M2YEQ*') {
        Write-Host '  M2Y EQ: uygulamayi bir kez acin ve BYD Otomatik Baslatma listesinde izin verin.' -ForegroundColor Yellow
    }
    if ($f -like 'M2YBYD*') {
        & $adb -s $ip shell pm grant com.m2y.byd android.permission.ACCESS_FINE_LOCATION | Out-Null
        Write-Host '  M2Y BYD: konum izni verildi. Yolculuk kaydini acarsaniz BYD Otomatik Baslatma listesinde izin verin.' -ForegroundColor Yellow
    }
}

& $adb disconnect $ip | Out-Null
Write-Host ''
Write-Host '  Tamamlandi. Baglanti kapatildi.' -ForegroundColor Green
