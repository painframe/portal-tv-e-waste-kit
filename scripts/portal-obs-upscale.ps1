<#
  Path 3 helper: OBS + NVIDIA RTX Super Resolution 2x upscale.
  PowerShell mirror of portal-obs-upscale.sh. Pure ASCII.

  Single-purpose: thin wrapper around the existing portal-tv-webcam script
  that ALSO installs the NVIDIA filter chain (Artefact Reduction -> Super
  Resolution 2x) on the camera source.

  Pre-requisites:
    - adb on PATH
    - obs.exe on PATH, OR OBS_STUDIO_BIN env var pointing at obs64.exe
    - The NVIDIA Broadcast / RTX Super Resolution plugin installed in OBS
      (https://github.com/Bemjo/OBS-RTX-SuperResolution)

  Usage:
    .\portal-obs-upscale.ps1                     arm tunnel + camera + OBS + filters
    .\portal-obs-upscale.ps1 -Scene <name>       apply filters to a specific scene
                                                 (default: first scene)
    .\portal-obs-upscale.ps1 -Source <name>      apply filters to a specific source
                                                 (default: PortalCam source)
    .\portal-obs-upscale.ps1 -Help               this help
#>

[CmdletBinding()]
param(
    [string]$Scene = '',
    [string]$Source = '',
    [switch]$Help
)

$ErrorActionPreference = 'Continue'

if ($Help) {
    Write-Host 'Path 3 helper: OBS + NVIDIA RTX Super Resolution 2x upscale of the existing 720p feed.'
    Write-Host ''
    Write-Host '  .\portal-obs-upscale.ps1                     arm tunnel + camera + OBS + filters'
    Write-Host '  .\portal-obs-upscale.ps1 -Scene <name>       apply filters to a specific scene'
    Write-Host '  .\portal-obs-upscale.ps1 -Source <name>      apply filters to a specific source'
    Write-Host '  .\portal-obs-upscale.ps1 -Help               this help'
    Write-Host ''
    Write-Host 'See docs/keeping-portal-alive.md#upscale for the recommended filter order.'
    exit 0
}

function Step($msg)  { Write-Host "==> " -NoNewline -ForegroundColor Cyan; Write-Host $msg }
function Ok($msg)    { Write-Host "  + " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Die($msg)   { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

# ----- pre-flight ------------------------------------------------------------
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Step 'Pre-flight checks'
if (-not $env:PORTAL_TV_WEBCAM) {
    $env:PORTAL_TV_WEBCAM = (Resolve-Path (Join-Path $ScriptDir '..\..\..\portal-tv-webcam')).Path
}
if (-not (Test-Path $env:PORTAL_TV_WEBCAM)) {
    Die "sibling repo portal-tv-webcam not found at $env:PORTAL_TV_WEBCAM - clone it next to this kit and re-run"
}
Ok "portal-tv-webcam: $env:PORTAL_TV_WEBCAM"

$ObsExe = $env:OBS_STUDIO_BIN
if (-not $ObsExe) { $ObsExe = $env:OBS_BIN }
if (-not $ObsExe) { $ObsExe = (Get-Command obs64.exe -ErrorAction SilentlyContinue).Path }
if (-not $ObsExe) { $ObsExe = (Get-Command obs.exe -ErrorAction SilentlyContinue).Path }
if (-not $ObsExe) {
    Die 'obs binary not on PATH and OBS_STUDIO_BIN is unset; install OBS Studio and re-run'
}
Ok "obs binary: $ObsExe"

$Adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $Adb) {
    Die 'adb not on PATH; install Android platform-tools and re-run'
}
Ok "adb: $($Adb.Path)"

# ----- arm the existing portal-tv-webcam pipeline ----------------------------
Step 'Arming the portal-tv-webcam pipeline (USB tunnel + camera + OBS)'
$Launcher = Join-Path $env:PORTAL_TV_WEBCAM 'scripts\start-portal-cam.ps1'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Launcher
if ($LASTEXITCODE -ne 0) {
    Warn "portal-tv-webcam launcher exited non-zero (code $LASTEXITCODE); inspect its output above."
}
# ----- apply the NVIDIA filter chain via OBS WebSocket ----------------------
Step 'Applying the NVIDIA filter chain (Artefact Reduction -> Super Resolution 2x)'
if (-not $Source) {
    $Source = 'PortalCam'
    Warn "-Source not set; defaulting to '$Source' (the typical portal-tv-webcam source)."
}
$Apply = Join-Path $ScriptDir 'portal-obs-upscale-apply.py'
if (-not (Test-Path $Apply)) {
    Die "missing $Apply - the kit's helper Python file disappeared"
}
$ObsHost     = if ($env:OBS_HOST)     { $env:OBS_HOST }     else { '127.0.0.1' }
$ObsPort     = if ($env:OBS_PORT)     { $env:OBS_PORT }     else { '4455' }
$ObsPassword = if ($env:OBS_PASSWORD) { $env:OBS_PASSWORD } else { '' }
Warn 'Prerequisites (not auto-installed):'
Warn '  - In OBS Studio -> Tools -> obs-websocket Settings: enable the server, copy the password'
Warn '  - The NVIDIA RTX Super Resolution plugin (Bemjo/OBS-RTX-SuperResolution) must be installed'
$argList = @($Apply, '--host', $ObsHost, '--port', $ObsPort, '--source', $Source)
if ($ObsPassword) { $argList += @('--password', $ObsPassword) }
if ($Scene)       { $argList += @('--scene', $Scene) }
& python3 @argList
if ($LASTEXITCODE -eq 0) {
    Ok 'filter chain applied.'
} else {
    Die "filter chain helper exited with code $LASTEXITCODE (source missing? obs-websocket not enabled? password wrong?)"
}
