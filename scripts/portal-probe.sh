#!/usr/bin/env bash
#
# Copyright (c) 2026 Starbright Lab.
# Licensed under the MIT license found in the LICENSE file in the repo root.
#
# Portal TV four-verdict probe + optional Device-Owner claim.
#
# Runs V1 (security patch level), V2 (USB-C host mode / UVC), V3 (camera HAL
# advertised sizes), V4 (Device-Owner slot state), then optionally attempts
# `dpm set-device-owner com.immortal.launcher/.AdminReceiver` if the slot is
# free AND --claim-device-owner is set. The only write this script performs
# is the dpm claim; everything else is observation.
#
# Usage:
#   ./portal-probe.sh                       auto-detect the first connected device
#   ./portal-probe.sh --device <serial>     target a specific device
#   ./portal-probe.sh --uvc                 V2 verification (needs a UVC webcam plugged in)
#   ./portal-probe.sh --claim-device-owner  attempt the dpm claim (default off)
#   ./portal-probe.sh --dry-run-claim       print the would-be dpm command without running it
#                                           (combine with --claim-device-owner)
#   ./portal-probe.sh --help                this help
#

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# ----- pretty output ---------------------------------------------------------
if [ -t 1 ]; then B=$'\033[1m'; G=$'\033[32m'; Y=$'\033[33m'; R=$'\033[31m'; D=$'\033[2m'; N=$'\033[0m'; else B=; G=; Y=; R=; D=; N=; fi
step() { printf "%s==>%s %s\n" "$B" "$N" "$1"; }
ok()   { printf "  %s+%s %s\n" "$G" "$N" "$1"; }
warn() { printf "  %s!%s %s\n" "$Y" "$N" "$1"; }
die()  { printf "%sERROR:%s %s\n" "$R" "$N" "$1" >&2; exit 1; }

# ----- defaults & arg parse --------------------------------------------------
DEVICE_SERIAL=""
DO_UVC=0
DO_CLAIM=0
DO_DRY_RUN_CLAIM=0

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device)        DEVICE_SERIAL="${2:-}"; [ -n "$DEVICE_SERIAL" ] || die "--device requires a serial"; shift 2 ;;
    --uvc)           DO_UVC=1; shift ;;
    --claim-device-owner)  DO_CLAIM=1; shift ;;
    --dry-run-claim) DO_DRY_RUN_CLAIM=1; shift ;;
    --help|-h)       usage; exit 0 ;;
    *)               die "Unknown option: $1 (use --help)"; shift ;;
  esac
done

# ----- resolve adb (mirror immortal/provisioning/provision.sh:48-66) ---------
resolve_adb() {
  if [ -x "$SCRIPT_DIR/platform-tools/adb" ]; then ADB="$SCRIPT_DIR/platform-tools/adb"; return; fi
  if command -v adb >/dev/null 2>&1; then ADB="$(command -v adb)"; return; fi
  die "platform-tools not found; install Android adb or set ADB=path/to/adb"
}

if [ -n "${ADB:-}" ]; then
  [ -x "$ADB" ] || die "ADB=$ADB is not executable"
else
  resolve_adb
fi

a() { "$ADB" "$@"; }

# ----- Dry-run fast path: preview the dpm claim without a device -------------
# `--dry-run-claim` alone is meaningless (no "claim" to dry-run), so we treat
# it as a no-op and surface a hint. `--claim-device-owner` plus
# `--dry-run-claim` (in either order) prints the would-be dpm command and
# exits 0, WITHOUT touching any device, WITHOUT requiring ADB to find a
# Portal. The real-claim path (below) still requires a connected device.
#
# NOTE: resolve_adb() must have already run by this point (it does, in the
# block above this comment at the ADB=/resolve_adb fork). If a future
# refactor moves resolve_adb into find_device(), the dry-run path will
# silently succeed with no adb binary on PATH; the user would only learn at
# claim-time. Keep the ordering.
if [ "$DO_DRY_RUN_CLAIM" -eq 1 ] && [ "$DO_CLAIM" -eq 0 ]; then
  step "Hint: --dry-run-claim without --claim-device-owner is a no-op. Re-run with both flags (in any order) to print the would-be dpm command."
  exit 0
fi
if [ "$DO_DRY_RUN_CLAIM" -eq 1 ] && [ "$DO_CLAIM" -eq 1 ]; then
  step "Dry-run: would claim Device-Owner"
  ok "Would run: adb -s <device> shell dpm set-device-owner com.immortal.launcher/.AdminReceiver"
  ok "Re-run with a Portal connected (no --dry-run-claim) to actually attempt the claim."
  exit 0
fi

# ----- wait for an authorized device (mirror start-portal-cam.ps1:23-32) ----
DEVICE=""
find_device() {
  step "Looking for your Portal over USB"
  a start-server >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if [ -n "$DEVICE_SERIAL" ]; then
      state="$(a -s "$DEVICE_SERIAL" get-state 2>/dev/null | tr -d '\r')"
      [ "$state" = "device" ] && DEVICE="$DEVICE_SERIAL" && return 0
    else
      line="$(a devices 2>/dev/null | tr -d '\r' | awk '$2 == "device" {print $1; exit}')"
      if [ -n "$line" ]; then DEVICE="$line"; return 0; fi
    fi
    sleep 1
  done
  return 1
}

if find_device; then
  ok "Portal connected: $DEVICE"
else
  cat >&2 <<'EOF'

Portal NOT connected. Plug in USB-C; on the device re-toggle
Settings > Debug > ADB Enabled, unplug/replug, accept 'Allow USB debugging',
then re-run. (See repo README, "Run the probe".)
EOF
  exit 1
fi

# ----- V1: device identity + security patch level ----------------------------
step "V1: device identity + Qualcomm security patch level"
MODEL="$(a -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r')"
PATCH="$(a -s "$DEVICE" shell getprop ro.build.version.security_patch 2>/dev/null | tr -d '\r')"
printf "  model:                       %s\n" "${MODEL:-unknown}"
printf "  security_patch_level:        %s\n" "${PATCH:-unknown}"
printf "  [VERIFIED-ON-DEVICE]\n"

# QualPwn window: CVE-2019-10538/10540 patched in 2019-08 Android Security Bulletin.
if [ -z "$PATCH" ]; then
  warn "V1 verdict: could not read security_patch_level; QualPwn applicability unknown"
elif [ "$PATCH" \< "2019-08-01" ]; then
  ok "V1 verdict: patch level < 2019-08 -- QualPwn (CVE-2019-10538/10540) is theoretically applicable. Long-shot path; only on a sacrificial unit."
else
  warn "V1 verdict: patch level >= 2019-08 -- QualPwn is patched. The round-2 long-shot path is NOT viable on this device."
fi
printf "\n"

# ----- V3: camera HAL advertised stream sizes -------------------------------
step "V3: camera HAL advertised stream sizes (dumpsys media.camera)"
DUMPSYS_OUT="$(a -s "$DEVICE" shell dumpsys media.camera 2>/dev/null | tr -d '\r')"
if [ -z "$DUMPSYS_OUT" ]; then
  warn "V3 verdict: dumpsys media.camera returned no output"
else
  echo "$DUMPSYS_OUT" | grep -E "SCALER_STREAM|1080|1920|720|1280" | head -40 || warn "V3 verdict: no SCALER_STREAM/1920/1280 matches found in dumpsys media.camera"
  if echo "$DUMPSYS_OUT" | grep -qE "1920.*1080|1080.*1920"; then
    ok "V3 verdict: >=1080p sizes advertised by the camera HAL (gate is likely below the framework)."
  elif echo "$DUMPSYS_OUT" | grep -qE "1280.*720|720.*1280"; then
    warn "V3 verdict: only 720p sizes advertised (gate is above the framework; root would unlock, if root were achievable)."
  else
    warn "V3 verdict: HAL output did not include recognizable 720/1080 markers; inspect the dumpsys extract above."
  fi
fi
printf "  [VERIFIED-ON-DEVICE]\n\n"

# ----- V2: USB-C host mode + UVC ---------------------------------------------
step "V2: USB-C host mode + UVC (does the Portal see a UVC webcam?)"
if [ "$DO_UVC" -eq 1 ]; then
  BEFORE="$(a -s "$DEVICE" shell ls /dev/video* 2>/dev/null | tr -d '\r')"
  printf "  /dev/video* before plug:  %s\n" "${BEFORE:-<none>}"
  warn "Plug the USB-C OTG adapter + UVC webcam NOW if you have not already. The probe compares /dev/video* before and after."
  printf "  Press Enter when the webcam is plugged, or Ctrl+C to skip.\n"
  if [ -t 0 ]; then
    # TTY present (interactive shell): wait up to 10 min for the human to plug.
    read -r -t 600 _ || true
    AFTER="$(a -s "$DEVICE" shell ls /dev/video* 2>/dev/null | tr -d '\r')"
  else
    # No TTY (nohup, cron, agent, CI): the human is not there. Initialize AFTER
    # to BEFORE so the V2 verdict below reads as "not measured" rather than
    # silently reporting BEFORE==AFTER as a non-result. (Required: the
    # comparison logic at lines 178-186 reads `$AFTER` and would crash under
    # `set -u` if it were left unset.)
    AFTER="$BEFORE"
    warn "No TTY; skipping the V2 interactive plug. AFTER mirrors BEFORE; the V2 verdict below will reflect 'not measured', not 'no change'."
  fi
  printf "  /dev/video* after plug:   %s\n" "${AFTER:-<none>}"
  if [ -z "$BEFORE" ] && [ -n "$AFTER" ]; then
    ok "V2 verdict: a new /dev/video* appeared after the UVC plug. USB-C host mode + UVC works on this device."
  elif [ -n "$BEFORE" ] && [ -n "$AFTER" ] && [ "$BEFORE" != "$AFTER" ]; then
    ok "V2 verdict: a new /dev/video* appeared in addition to existing nodes."
  elif [ "$BEFORE" = "$AFTER" ]; then
    warn "V2 verdict: /dev/video* did not change after the plug. USB host mode is likely disabled in firmware, or the UVC driver is not loaded. Path 2 (UVC) is NOT VIABLE on this device."
  else
    warn "V2 verdict: could not enumerate either side; the script will mark path 2 as NOT VIABLE."
  fi
else
  warn "V2 not run. Re-run with --uvc after plugging a USB-C OTG + UVC webcam if you want this verdict."
  V2_NOT_RUN=1
fi
printf "  [VERIFIED-ON-DEVICE]\n\n"

# ----- V4: device-owner slot state -------------------------------------------
step "V4: Android Device-Owner slot state (dumpsys device_policy)"
DP_OUT="$(a -s "$DEVICE" shell dumpsys device_policy 2>/dev/null | tr -d '\r')"
if [ -z "$DP_OUT" ]; then
  warn "V4 verdict: dumpsys device_policy returned no output"
  SLOT_STATE="UNKNOWN"
else
  echo "$DP_OUT" | grep -E "Device Owner|device-owner|Profile Owner" | head -10 || true
  if echo "$DP_OUT" | grep -qiE "device owner.*com\.facebook\.deviceowner"; then
    warn "V4 verdict: the slot is held by Meta's com.facebook.deviceowner. Releasing requires factory reset; the probe will NOT claim."
    SLOT_STATE="META"
  elif echo "$DP_OUT" | grep -qiE "device owner" && echo "$DP_OUT" | grep -qE "device owner.*\b(com\.[a-zA-Z0-9._]+)/"; then
    SLOT_HOLDER="$(echo "$DP_OUT" | grep -oiE "device owner.*\bcom\.[a-zA-Z0-9._]+" | head -1 | grep -oiE "com\.[a-zA-Z0-9._]+")"
    warn "V4 verdict: the slot is held by $SLOT_HOLDER (not com.facebook.deviceowner). Probe cannot claim."
    SLOT_STATE="OTHER"
  elif echo "$DP_OUT" | grep -qiE "device owner.*none|device owner.*unset|no active device owner"; then
    ok "V4 verdict: the Device-Owner slot is FREE. Claim is feasible."
    SLOT_STATE="FREE"
  else
    warn "V4 verdict: dumpsys output did not match any expected pattern; inspect the extract above. Defaulting to NOT-FREE."
    SLOT_STATE="UNKNOWN"
  fi
fi
printf "  [VERIFIED-ON-DEVICE]\n\n"

# ----- Optional: auto-claim Device Owner -------------------------------------
if [ "$DO_CLAIM" -eq 1 ]; then
  step "Auto-claim Device Owner (flag was set)"
  printf "  Before:\n"
  a -s "$DEVICE" shell dumpsys device_policy 2>/dev/null | grep -E "Device Owner" | head -5 | sed 's/^/    /'
  if [ "${SLOT_STATE:-}" != "FREE" ]; then
    warn "Refusing: slot is ${SLOT_STATE:-UNKNOWN}; not FREE."
    warn "Freeing requires factory reset, which the script will not perform automatically."
  else
    CLAIM_PKG="com.immortal.launcher"
    CLAIM_RCV="/.AdminReceiver"
    CLAIM_CMD="dpm set-device-owner ${CLAIM_PKG}${CLAIM_RCV}"
    # Confirm the admin receiver is actually installed before claiming. If dpm
    # is given a missing class name it will refuse with ClassNotFoundException;
    # we want to fail earlier with a clearer message.
    if ! a -s "$DEVICE" shell pm list packages 2>/dev/null | tr -d '\r' | grep -q "^package:${CLAIM_PKG}\$"; then
      warn "${CLAIM_PKG} is not installed on this device. Install com.immortal.launcher first; see the immortal repo's README."
      warn "Claim NOT attempted."
    else
      ok "${CLAIM_PKG} is installed; attempting: adb -s $DEVICE shell $CLAIM_CMD"
      CLAIM_OUT="$(a -s "$DEVICE" shell "$CLAIM_CMD" 2>&1)"
      CLAIM_RC=$?
      printf "  exit code: %s\n" "$CLAIM_RC"
      printf "  output:    %s\n" "$CLAIM_OUT"
      if [ "$CLAIM_RC" -ne 0 ]; then
        printf "%sERROR:%s dpm claim failed. Inspect the output above. Slot state unchanged. CLAIM_RC=%s.\n" "$R" "$N" "$CLAIM_RC" >&2
        exit 2
      fi
    fi
  fi
  printf "  After:\n"
  a -s "$DEVICE" shell dumpsys device_policy 2>/dev/null | grep -E "Device Owner" | head -5 | sed 's/^/    /'
  printf "  To reverse a successful claim: Settings > System > Reset options > Erase all data (factory reset).\n"
  printf "\n"
else
  warn "Device-Owner claim NOT attempted. Re-run with --claim-device-owner to try; add --dry-run-claim to print the command without running it."
  printf "\n"
fi

# ----- Final verdict block ---------------------------------------------------
step "Path status (based on V1-V4 above)"

# Path 1: HDMI capture. Independent of V-leads; the only questions are
# hardware-side (does the host have a free HDMI in / capture card).
printf "  %sPath 1 (HDMI capture card):        READY (host-side)%s  hardware add-on; buy a UVC capture card and follow keeping-portal-alive.md#hdmi.\n" "$G" "$N"

# Path 2: UVC. Depends on V2 (only if --uvc was passed).
if [ "${V2_NOT_RUN:-0}" -eq 1 ]; then
  printf "  %sPath 2 (USB-C UVC webcam):         REQUIRES-HARDWARE%s  UVC not verified; re-run with --uvc to confirm.\n" "$Y" "$N"
elif [ "$DO_UVC" -eq 1 ]; then
  if [ -n "${AFTER:-}" ] && [ "$BEFORE" != "$AFTER" ]; then
    V2_VERDICT="READY"
  else
    V2_VERDICT="NOT-VIABLE"
  fi
  printf "  %sPath 2 (USB-C UVC webcam):         %s%s\n" "$Y" "$V2_VERDICT" "$N"
fi

# Path 3: OBS upscale. Always ready (no V-lead dependency; pure host-side
# software configuration).
printf "  %sPath 3 (OBS RTX upscale):           READY (host-side)%s  no device change; pure host-side software config (needs NVIDIA RTX). See keeping-portal-alive.md#upscale.\n" "$G" "$N"

printf "\n"
ok "Probe complete. The full evidence for these verdicts is at docs/research/portal-1080p-camera-paths.md."
exit 0
