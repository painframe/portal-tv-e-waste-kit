<#
  Path 1 helper: HDMI capture card on the host.
  PowerShell mirror of portal-hdmi-capture.sh. Pure ASCII.

  Single-purpose: prove the host sees the HDMI-to-USB capture card as a standard
  UVC device and writes a short smoke test to ./stream.mkv so the user can
  confirm the pipeline end-to-end before plugging it into OBS / Zoom / Meet.

  Usage:
    .\portal-hdmi-capture.ps1                  auto-detect by host OS
    .\portal-hdmi-capture.ps1 -Device <name>   pick a specific capture card by name
    .\portal-hdmi-capture.ps1 -Out <path>      output file (default: .\stream.mkv)
    .\portal-hdmi-capture.ps1 -Duration <sec>  smoke test length (default: 5)
    .\portal-hdmi-capture.ps1 -Help            this help

  Exit codes:
    0 = capture card enumerated; stream written
    1 = no capture card found
    2 = ffmpeg missing
#>

[CmdletBinding()]
param(
    [string]$Device = '',
    [string]$Out = 'stream.mkv',
    [int]$Duration = 5,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

if ($Help) {
    Write-Host 'Path 1 helper: HDMI capture card on the host.'
    Write-Host ''
    Write-Host '  .\portal-hdmi-capture.ps1                  auto-detect by host OS'
    Write-Host '  .\portal-hdmi-capture.ps1 -Device <name>   pick a specific capture card by name'
    Write-Host '  .\portal-hdmi-capture.ps1 -Out <path>      output file (default: .\stream.mkv)'
    Write-Host '  .\portal-hdmi-capture.ps1 -Duration <sec>  smoke test length (default: 5)'
    Write-Host '  .\portal-hdmi-capture.ps1 -Help            this help'
    Write-Host ''
    Write-Host 'Exit codes: 0 = card enumerated and smoke test written; 1 = no card found; 2 = ffmpeg missing.'
    exit 0
}

function Step($msg)  { Write-Host "==> " -NoNewline -ForegroundColor Cyan; Write-Host $msg }
function Ok($msg)    { Write-Host "  + " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Die($msg)   { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

# ----- resolve ffmpeg ---------------------------------------------------------
# Resolve ffmpeg. The bash twin exits 2 here; match that contract.
if (-not $Ffmpeg) {
    Write-Host 'ERROR: ' -ForegroundColor Red -NoNewline
    Write-Host 'ffmpeg not found on PATH; install it and re-run.'
    exit 2
}

# ----- pick host-OS framing --------------------------------------------------
# Portable host-OS detection that works on PowerShell 5.1 too ($IsLinux /
# $IsMacOS are 6+ automatic variables and are $null on 5.1).
if ($PSVersionTable.PSVersion.Major -ge 6) {
    if     ($IsLinux) { $HostKind = 'Linux' }
    elseif ($IsMacOS) { $HostKind = 'macOS' }
    else              { $HostKind = 'Windows' }
} elseif ($env:OS -eq 'Windows_NT') {
    $HostKind = 'Windows'
} else {
    Die "Unsupported host OS: $($env:OS)"
}

# ----- enumerate the capture card --------------------------------------------
switch ($HostKind) {
    'Linux' {
        Step 'Linux detected - enumerating /dev/video* and checking v4l2-ctl'
        $V4l2 = Get-Command v4l2-ctl -ErrorAction SilentlyContinue
        if ($V4l2) {
            & v4l2-ctl --list-devices 2>&1 | ForEach-Object { Write-Host "  $_" }
        } else {
            Warn 'v4l2-ctl not installed; install v4l-utils for device names'
        }
        $VideoDevs = Get-ChildItem /dev/video* -ErrorAction SilentlyContinue
        if (-not $VideoDevs) {
            Die 'no /dev/video* present. Connect the HDMI capture card and re-run. See docs/keeping-portal-alive.md#hdmi-troubleshooting'
        }
        $Pick = if ($Device) { $Device } else { $VideoDevs[0].FullName }
        Ok "capture device picked: $Pick"
        $FfmpegInput = @('-f', 'v4l2', '-i', $Pick)
    }
    'macOS' {
        Step 'macOS detected - enumerating AVFoundation video devices'
        & ffmpeg -f avfoundation -list_devices true -i '' 2>&1 |
            Select-String -Pattern '^[\["][^"]*\]' -CaseSensitive:$false |
            ForEach-Object { Write-Host "  $_" }
        $Pick = if ($Device) { $Device } else { 'USB Camera' }
        Ok "capture device picked: $Pick"
        $FfmpegInput = @('-f', 'avfoundation', '-i', $Pick)
    }
    'Windows' {
        Step 'Windows detected - enumerating dshow video devices'
        & ffmpeg -f dshow -list_devices true -i dummy 2>&1 |
            Select-String -Pattern '"[^"]+"' -CaseSensitive:$false |
            ForEach-Object { Write-Host "  $_" }
        $Pick = if ($Device) { $Device } else { 'USB Camera' }
        Ok "capture device picked: $Pick"
        $FfmpegInput = @('-f', 'dshow', '-i', "video=$Pick")
    }
}

# ----- enumerate + smoke grab -------------------------------------------------
# Inline-capture stderr so the user sees ffmpeg's own enumerate output, then
# fall through to a clean smoke-test grab.
Step "Enumerating the capture card at $Pick"
$enumArgs = $FfmpegInput + @('-t', '0.1', '-f', 'null', '-')
$enumOut  = & ffmpeg @enumArgs 2>&1 | Out-String
Write-Host ($enumOut -split "`r?`n" | Select-Object -Last 20 | ForEach-Object { "  $_" })
# 255 = SIGINT (Ctrl+C) which is OK if the user wanted to abort
if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne 255) {
    Die 'capture card did not respond to ffmpeg. Try another USB port; see docs/keeping-portal-alive.md#hdmi-troubleshooting'
}
Ok 'capture card enumerated'

Step "Writing $Duration-second smoke test to $Out (Ctrl+C to abort)"
$grabArgs = $FfmpegInput + @('-t', "$Duration")
$grabProc = Start-Process -FilePath ffmpeg -ArgumentList $grabArgs -NoNewWindow -RedirectStandardError 'grab.log' -PassThru -Wait
if ($grabProc.ExitCode -eq 0) {
    Ok "smoke test written: $Out"
} else {
    Warn "ffmpeg exited non-zero (code $($grabProc.ExitCode)); the capture may still be usable - inspect $Out"
}

Ok 'Done. Open the output in VLC or an OBS Media Source to confirm. Then point OBS / Zoom at the capture device directly.'
