<#
  Path 2 helper: USB-C UVC external webcam on the Portal.
  PowerShell mirror of portal-uvc-external.sh. Pure ASCII.

  Single-purpose: prove the Portal TV enumerates a UVC webcam over its USB-C
  port. If the UVC camera is enumerated, optionally launches IP Webcam pointed
  at the external camera so the existing portal-tv-webcam pipeline picks it up.

  Usage:
    .\portal-uvc-external.ps1                  print V2 verdict; do NOT launch IP Webcam
    .\portal-uvc-external.ps1 -Launch          if V2 is READY, launch IP Webcam pointed at the external camera
    .\portal-uvc-external.ps1 -Device <serial> target a specific Portal
    .\portal-uvc-external.ps1 -Help            this help

  Exit codes:
    0 = V2 verdict reported
    1 = no Portal found / adb missing
#>

[CmdletBinding()]
param(
    [string]$Device = '',
    [switch]$Launch,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

if ($Help) {
    Write-Host 'Path 2 helper: USB-C UVC external webcam on the Portal.'
    Write-Host ''
    Write-Host '  .\portal-uvc-external.ps1                  print V2 verdict; do NOT launch IP Webcam'
    Write-Host '  .\portal-uvc-external.ps1 -Launch          if V2 is READY, launch IP Webcam pointed at the external camera'
    Write-Host '  .\portal-uvc-external.ps1 -Device <serial> target a specific Portal'
    Write-Host '  .\portal-uvc-external.ps1 -Help            this help'
    Write-Host ''
    Write-Host 'Exit codes: 0 = V2 verdict reported; 1 = no Portal found / adb missing.'
    exit 0
}

function Step($msg)  { Write-Host "==> " -NoNewline -ForegroundColor Cyan; Write-Host $msg }
function Ok($msg)    { Write-Host "  + " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Die($msg)   { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

# ----- resolve adb -----------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:ADB) {
    $BundledAdb = Join-Path $ScriptDir 'platform-tools/adb.exe'
    if (Test-Path $BundledAdb) {
        $env:ADB = $BundledAdb
    } elseif ($ResolvedAdb = Get-Command adb -ErrorAction SilentlyContinue) {
        $env:ADB = $ResolvedAdb.Path
    } else {
        Die 'platform-tools not found; install Android adb or set ADB=path\to\adb.exe'
    }
}
$Adb = $env:ADB

function A([string[]]$args) { & $Adb @args }

# ----- find Portal -----------------------------------------------------------
Step 'Looking for your Portal over USB'
$Found = $false
$DeviceSerial = ''
& $Adb start-server | Out-Null
for ($i = 0; $i -lt 15; $i++) {
    $line = (& $Adb devices 2>$null) | Where-Object { $_ -match '\bdevice\s*$' } | Select-Object -First 1
    if ($line) {
        if ($Device) {
            if ($line -match ("\b" + [regex]::Escape($Device) + "\b")) {
                $DeviceSerial = $Device
                $Found = $true
                break
            }
        } else {
            $DeviceSerial = ($line -split '\s+')[0]
            $Found = $true
            break
        }
    }
    Start-Sleep -Seconds 1
}
if (-not $Found) {
    Die 'no Portal found; check USB cable and ADB'
}
Ok "Portal connected: $DeviceSerial"

# ----- V2: UVC enumerate -----------------------------------------------------
Step 'V2: does the Portal see a UVC webcam over USB-C?'
Write-Host '  Plug the USB-C OTG adapter + UVC webcam NOW if you have not already.'
Write-Host '  Press Enter when the webcam is plugged, or Ctrl+C to skip.'
Read-Host
$UVD = (& $Adb -s $DeviceSerial shell 'ls /dev/video*' 2>$null) -join "`n" -replace "`r",''
if ($UVD) {
    Write-Host "  /dev/video* after plug: "
    $UVD -split "`n" | ForEach-Object { Write-Host "    $_" }
} else {
    Write-Host '  /dev/video* after plug:   <none>'
}

if (-not $UVD) {
    Warn 'V2 verdict: NO /dev/video* enumerated. USB-C host mode is likely disabled in firmware.'
    Warn 'Path 2 (UVC) is NOT VIABLE on this device.'
    exit 0
}

# Check if Camera2 sees it (Android's camera service)
$CmdList = (& $Adb -s $DeviceSerial shell 'cmd camera list' 2>$null) -join "`n" -replace "`r",''
if ($CmdList) {
    Write-Host '  cmd camera list:'
    $CmdList -split "`n" | ForEach-Object { Write-Host "    $_" }
}

Ok 'V2 verdict: /dev/video* enumerated; USB-C host mode + UVC is working on this device.'

# ----- optional: launch IP Webcam pointed at the external camera ------------
if ($Launch) {
    Step 'Launching IP Webcam on the Portal'
    $Installed = (& $Adb -s $DeviceSerial shell pm list packages 2>$null) -join "`n"
    if ($Installed -notmatch 'com\.pas\.webcam') {
        Warn 'IP Webcam (com.pas.webcam) is not installed on the Portal.'
        Warn 'Install it via the immortal App Store or by sideloading the APK from APKMirror,'
        Warn 'then re-run with -Launch. See docs/keeping-portal-alive.md#uvc.'
        exit 0
    }
    Ok 'IP Webcam is installed; launching com.pas.webcam/.Configuration'
    & $Adb -s $DeviceSerial shell am start -n com.pas.webcam/.Configuration
    Ok 'Done. Back on the Portal TV, accept the camera permission, choose External if prompted,'
    Ok 'then tap Start server. The existing portal-tv-webcam pipeline (USB tunnel to host) handles the rest.'
}
