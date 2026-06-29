<#
  Portal TV four-verdict probe + optional Device-Owner claim.
  PowerShell 5.1+ mirror of portal-probe.sh. Pure ASCII (Windows PowerShell
  5.1 mis-decodes non-ASCII). Behaviour, contract, and exit codes are
  identical to the bash version:

    - 0 = probe ran; read the verdict block
    - 1 = no Portal / no adb / ADB not enabled
    - 2 = dpm set-device-owner attempt failed; slot state unchanged

  Usage:
    .\portal-probe.ps1                       auto-detect the first connected device
    .\portal-probe.ps1 -Device <serial>      target a specific device
    .\portal-probe.ps1 -Uvc                  V2 verification (needs a UVC webcam plugged in)
    .\portal-probe.ps1 -ClaimDeviceOwner     attempt the dpm claim (default off)
    .\portal-probe.ps1 -DryRunClaim          print the would-be dpm command without running it
                                             (combine with -ClaimDeviceOwner)
    .\portal-probe.ps1 -Help                 this help
#>

[CmdletBinding()]
param(
    [string]$Device = '',
    [switch]$Uvc,
    [switch]$ClaimDeviceOwner,
    [switch]$DryRunClaim,
    [switch]$Help
)

$ErrorActionPreference = 'Continue'  # probe continues past per-lead failures

# ----- CONFIG ---------------------------------------------------------------
# Mirror the bash version's ADB resolution order: $env:ADB -> bundled
# platform-tools -> PATH. Override $env:ADB if your adb.exe lives elsewhere.
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $env:ADB) {
    $BundledAdb = Join-Path $ScriptDir 'platform-tools/adb.exe'
    if (Test-Path $BundledAdb) {
        $env:ADB = $BundledAdb
    } elseif ($ResolvedAdb = Get-Command adb -ErrorAction SilentlyContinue) {
        $env:ADB = $ResolvedAdb.Path
    } else {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host "platform-tools not found; install Android adb or set ADB=path\to\adb.exe"
        exit 1
    }
}
$Adb = $env:ADB
if (-not (Test-Path $Adb)) {
    Write-Host "ERROR: " -ForegroundColor Red -NoNewline
    Write-Host "ADB=$Adb is not a valid path"
    exit 1
}

# ----- helpers --------------------------------------------------------------
function Step($msg)  { Write-Host "==> " -NoNewline -ForegroundColor Cyan; Write-Host $msg }
function Ok($msg)    { Write-Host "  + " -ForegroundColor Green -NoNewline; Write-Host $msg }
function Warn($msg)  { Write-Host "  ! " -ForegroundColor Yellow -NoNewline; Write-Host $msg }
function Die($msg)   { Write-Host "ERROR: " -ForegroundColor Red -NoNewline; Write-Host $msg; exit 1 }

function A([string[]]$args) { & $Adb @args }

if ($Help) {
    Get-Help $MyInvocation.MyCommand.Path -Full | Out-String | Write-Host
    exit 0
}

# ----- Dry-run fast path: preview the dpm claim without a device -----------
# `-DryRunClaim` alone is meaningless (no "claim" to dry-run), so we treat
# it as a no-op and surface a hint. `-ClaimDeviceOwner` plus `-DryRunClaim`
# (in either order) prints the would-be dpm command and exits 0, WITHOUT
# touching any device, WITHOUT requiring ADB to find a Portal. The real-
# claim path (below) still requires a connected device. This mirrors the
# bash fast-path at portal-probe.sh:72-93.
if ($DryRunClaim -and -not $ClaimDeviceOwner) {
    Step 'Hint: -DryRunClaim without -ClaimDeviceOwner is a no-op. Re-run with both flags (in any order) to print the would-be dpm command.'
    exit 0
}
if ($DryRunClaim -and $ClaimDeviceOwner) {
    Step 'Dry-run: would claim Device-Owner'
    Ok "Would run: $Adb -s <device> shell dpm set-device-owner com.immortal.launcher/.AdminReceiver"
    Ok 'Re-run with a Portal connected (no -DryRunClaim) to actually attempt the claim.'
    exit 0
}

# ----- wait for an authorized device ----------------------------------------
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
    Write-Host ""
    Write-Host "Portal NOT connected. Plug in USB-C; on the device re-toggle" -ForegroundColor Yellow
    Write-Host "Settings > Debug > ADB Enabled, unplug/replug, accept 'Allow USB debugging'," -ForegroundColor Yellow
    Write-Host "then re-run. (See repo README, 'Run the probe'.)" -ForegroundColor Yellow
    exit 1
}
Ok "Portal connected: $DeviceSerial"

# ----- V1: device identity + security patch level ---------------------------
Step 'V1: device identity + Qualcomm security patch level'
$Model = (& $Adb -s $DeviceSerial shell getprop ro.product.model 2>$null) -replace "`r",''
$Patch = (& $Adb -s $DeviceSerial shell getprop ro.build.version.security_patch 2>$null) -replace "`r",''
Write-Host ("  model:                       {0}" -f ($(if ($Model) {$Model} else {'unknown'})))
Write-Host ("  security_patch_level:        {0}" -f ($(if ($Patch) {$Patch} else {'unknown'})))
Write-Host "  [VERIFIED-ON-DEVICE]"

# QualPwn window: CVE-2019-10538/10540 patched in 2019-08 Android Security Bulletin.
if (-not $Patch) {
    Warn 'V1 verdict: could not read security_patch_level; QualPwn applicability unknown'
} elseif ([datetime]::ParseExact($Patch.Substring(0,10), 'yyyy-MM-dd', $null) -lt [datetime]'2019-08-01') {
    Ok 'V1 verdict: patch level < 2019-08 -- QualPwn (CVE-2019-10538/10540) is theoretically applicable. Long-shot path; only on a sacrificial unit.'
} else {
    Warn 'V1 verdict: patch level >= 2019-08 -- QualPwn is patched. The round-2 long-shot path is NOT viable on this device.'
}
Write-Host ""

# ----- V3: camera HAL advertised stream sizes -------------------------------
Step 'V3: camera HAL advertised stream sizes (dumpsys media.camera)'
$DumpsysOut = (& $Adb -s $DeviceSerial shell dumpsys media.camera 2>$null) -join "`n"
if (-not $DumpsysOut) {
    Warn 'V3 verdict: dumpsys media.camera returned no output'
} else {
    $Matches = $DumpsysOut -split "`n" | Where-Object { $_ -match 'SCALER_STREAM|1080|1920|720|1280' } | Select-Object -First 40
    if ($Matches) { $Matches | ForEach-Object { Write-Host "  $_" } } else { Warn 'V3 verdict: no SCALER_STREAM/1920/1280 matches found in dumpsys media.camera' }
    if ($DumpsysOut -match '1920.*1080|1080.*1920') {
        Ok 'V3 verdict: >=1080p sizes advertised by the camera HAL (gate is likely below the framework).'
    } elseif ($DumpsysOut -match '1280.*720|720.*1280') {
        Warn 'V3 verdict: only 720p sizes advertised (gate is above the framework; root would unlock, if root were achievable).'
    } else {
        Warn 'V3 verdict: HAL output did not include recognizable 720/1080 markers; inspect the dumpsys extract above.'
    }
}
Write-Host "  [VERIFIED-ON-DEVICE]"
Write-Host ""

# ----- V2: USB-C host mode + UVC --------------------------------------------
Step 'V2: USB-C host mode + UVC (does the Portal see a UVC webcam?)'
$V2NotRun = $false
if ($Uvc) {
    $Before = (& $Adb -s $DeviceSerial shell 'ls /dev/video*' 2>$null) -join "`n" -replace "`r",''
    Write-Host ("  /dev/video* before plug:  {0}" -f ($(if ($Before) {$Before} else {'<none>'})))
    Warn 'Plug the USB-C OTG adapter + UVC webcam NOW if you have not already. The probe compares /dev/video* before and after.'
    Write-Host "  Press Enter when the webcam is plugged, or Ctrl+C to skip."
    # TTY guard: under no-TTY (nohup, scheduled task, agent, CI) the human is
    # not there to plug the webcam. Default $After to $Before so the V2
    # verdict block below reports "not measured" rather than silently
    # BEFORE==AFTER. Note: PowerShell does not have `set -u`'s unset-variable
    # crash, so we do not need the same belt-and-braces for the comparison
    # logic immediately below -- but the human-vs-no-human difference in
    # $After is the same shape as the bash fix at portal-probe.sh:167-179.
    if ([Console]::IsInputRedirected) {
        Warn 'No TTY; skipping the V2 interactive plug. $After mirrors $Before; the V2 verdict will reflect "not measured", not "no change".'
        $After = $Before
    } else {
        Read-Host
        $After = (& $Adb -s $DeviceSerial shell 'ls /dev/video*' 2>$null) -join "`n" -replace "`r",''
    }
    Write-Host ("  /dev/video* after plug:   {0}" -f ($(if ($After) {$After} else {'<none>'})))
    if (-not $Before -and $After) {
        Ok 'V2 verdict: a new /dev/video* appeared after the UVC plug. USB-C host mode + UVC works on this device.'
    } elseif ($Before -and $After -and ($Before -ne $After)) {
        Ok 'V2 verdict: a new /dev/video* appeared in addition to existing nodes.'
    } elseif ($Before -eq $After) {
        Warn 'V2 verdict: /dev/video* did not change after the plug. USB host mode is likely disabled in firmware, or the UVC driver is not loaded. Path 2 (UVC) is NOT VIABLE on this device.'
    } else {
        Warn 'V2 verdict: could not enumerate either side; the script will mark path 2 as NOT VIABLE.'
    }
} else {
    Warn 'V2 not run. Re-run with -Uvc after plugging a USB-C OTG + UVC webcam if you want this verdict.'
    $V2NotRun = $true
}
Write-Host "  [VERIFIED-ON-DEVICE]"
Write-Host ""

# ----- V4: device-owner slot state ------------------------------------------
Step 'V4: Android Device-Owner slot state (dumpsys device_policy)'
$DpOut = (& $Adb -s $DeviceSerial shell dumpsys device_policy 2>$null) -join "`n"
if (-not $DpOut) {
    Warn 'V4 verdict: dumpsys device_policy returned no output'
    $SlotState = 'UNKNOWN'
} else {
    $DpMatches = $DpOut -split "`n" | Where-Object { $_ -match 'Device Owner|device-owner|Profile Owner' } | Select-Object -First 10
    if ($DpMatches) { $DpMatches | ForEach-Object { Write-Host "  $_" } }
    if ($DpOut -match '(?i)device owner.*com\.facebook\.deviceowner') {
        Warn 'V4 verdict: the slot is held by Meta''s com.facebook.deviceowner. Releasing requires factory reset; the probe will NOT claim.'
        $SlotState = 'META'
    } elseif ($DpOut -match '(?i)device owner' -and $DpOut -match '(?i)device owner.*com\.[a-zA-Z0-9._]+') {
        $Holder = ($DpOut | Select-String -Pattern 'com\.[a-zA-Z0-9._]+' -AllMatches | Select-Object -First 1).Matches[0].Value
        Warn "V4 verdict: the slot is held by $Holder (not com.facebook.deviceowner). Probe cannot claim."
        $SlotState = 'OTHER'
    } elseif ($DpOut -match '(?i)device owner.*(none|unset)' -or $DpOut -match '(?i)no active device owner') {
        Ok 'V4 verdict: the Device-Owner slot is FREE. Claim is feasible.'
        $SlotState = 'FREE'
    } else {
        Warn 'V4 verdict: dumpsys output did not match any expected pattern; inspect the extract above. Defaulting to NOT-FREE.'
        $SlotState = 'UNKNOWN'
    }
}
Write-Host "  [VERIFIED-ON-DEVICE]"
Write-Host ""

# ----- Optional: auto-claim Device Owner ------------------------------------
if ($ClaimDeviceOwner -or $DryRunClaim) {
    Step 'Auto-claim Device Owner (flag was set)'
    Write-Host "  Before:"
    (& $Adb -s $DeviceSerial shell dumpsys device_policy 2>$null) -split "`n" |
        Where-Object { $_ -match 'Device Owner' } | Select-Object -First 5 |
        ForEach-Object { Write-Host "    $_" }
    if ($SlotState -ne 'FREE') {
        Warn "Refusing: slot is $SlotState; not FREE."
        Warn 'Freeing requires factory reset, which the script will not perform automatically.'
    } else {
        $ClaimPkg = 'com.immortal.launcher'
        $ClaimRcv = '/.AdminReceiver'
        $ClaimCmd = "dpm set-device-owner ${ClaimPkg}${ClaimRcv}"
        $Installed = (& $Adb -s $DeviceSerial shell pm list packages 2>$null) -join "`n"
        if ($Installed -notmatch [regex]::Escape($ClaimPkg)) {
            Warn "${ClaimPkg} is not installed on this device. Install com.immortal.launcher first; see the immortal repo's README."
            Warn 'Claim NOT attempted.'
        } else {
            Ok "${ClaimPkg} is installed; attempting: $ClaimCmd"
            $ClaimOutput = & $Adb -s $DeviceSerial shell $ClaimCmd 2>&1
            $ClaimRc     = $LASTEXITCODE
            Write-Host ("  exit code: {0}" -f $ClaimRc)
            Write-Host ("  output:    {0}" -f ($ClaimOutput -join " "))
            if ($ClaimRc -ne 0) {
                Write-Host "ERROR: " -ForegroundColor Red -NoNewline
                Write-Host "dpm claim failed. Inspect the output above. Slot state unchanged. CLAIM_RC=$ClaimRc."
                exit 2
            }
        }
    }
    Write-Host "  After:"
    (& $Adb -s $DeviceSerial shell dumpsys device_policy 2>$null) -split "`n" |
        Where-Object { $_ -match 'Device Owner' } | Select-Object -First 5 |
        ForEach-Object { Write-Host "    $_" }
    Write-Host "  To reverse a successful claim: Settings > System > Reset options > Erase all data (factory reset)."
    Write-Host ""
} else {
    Warn 'Device-Owner claim NOT attempted. Re-run with -ClaimDeviceOwner to try; add -DryRunClaim to print the command without running it.'
    Write-Host ""
}

# ----- Final verdict block --------------------------------------------------
Step 'Path status (based on V1-V4 above)'
Write-Host '  ' -NoNewline
Write-Host 'Path 1 (HDMI capture card):        READY (host-side)' -NoNewline -ForegroundColor Green
Write-Host '  hardware add-on; buy a UVC capture card and follow keeping-portal-alive.md#hdmi.'

if ($V2NotRun) {
    Write-Host '  ' -NoNewline
    Write-Host 'Path 2 (USB-C UVC webcam):         REQUIRES-HARDWARE' -NoNewline -ForegroundColor Yellow
    Write-Host '  UVC not verified; re-run with -Uvc to confirm.'
} elseif ($Uvc) {
    if ($After -and ($Before -ne $After)) {
        $V2Verdict = 'READY'
    } else {
        $V2Verdict = 'NOT-VIABLE'
    }
    Write-Host '  ' -NoNewline
    Write-Host "Path 2 (USB-C UVC webcam):         $V2Verdict" -NoNewline -ForegroundColor Yellow
    Write-Host ''
}

Write-Host '  ' -NoNewline
Write-Host 'Path 3 (OBS RTX upscale):           READY (host-side)' -NoNewline -ForegroundColor Green
Write-Host '  no device change; pure host-side software config (needs NVIDIA RTX). See keeping-portal-alive.md#upscale.'
Write-Host ""
Ok 'Probe complete. The full evidence for these verdicts is at docs/research/portal-1080p-camera-paths.md.'
exit 0
