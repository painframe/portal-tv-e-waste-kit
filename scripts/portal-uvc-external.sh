#!/usr/bin/env bash
#
# Copyright (c) 2026 Starbright Lab.
# Licensed under the MIT license found in the LICENSE file in the repo root.
#
# Path 2 helper: USB-C UVC external webcam on the Portal.
#
# Single-purpose: prove the Portal TV enumerates a UVC webcam over its USB-C
# port (i.e. host-mode + UVC class driver binding works in firmware). If the
# UVC camera is enumerated, optionally launches IP Webcam pointed at the
# external camera so the existing portal-tv-webcam pipeline picks it up.
#
# Usage:
#   ./portal-uvc-external.sh                  print V2 verdict; do NOT launch IP Webcam
#   ./portal-uvc-external.sh --launch         if V2 is READY, launch IP Webcam pointed at the external camera
#   ./portal-uvc-external.sh --device <serial> target a specific Portal
#   ./portal-uvc-external.sh --help           this help
#
# Exit codes:
#   0 = V2 verdict reported (camera enumerated or not)
#   1 = no Portal found / adb missing
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
LAUNCH_IP_WEBCAM=0

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device)         DEVICE_SERIAL="${2:-}"; [ -n "$DEVICE_SERIAL" ] || die "--device requires a serial"; shift 2 ;;
    --launch)         LAUNCH_IP_WEBCAM=1; shift ;;
    --help|-h)        usage; exit 0 ;;
    *)                die "Unknown option: $1 (use --help)"; shift ;;
  esac
done

# ----- resolve adb (mirror portal-probe.sh) -----------------------------------
if [ -n "${ADB:-}" ]; then
  [ -x "$ADB" ] || die "ADB=$ADB is not executable"
elif [ -x "$SCRIPT_DIR/platform-tools/adb" ]; then
  ADB="$SCRIPT_DIR/platform-tools/adb"
elif command -v adb >/dev/null 2>&1; then
  ADB="$(command -v adb)"
else
  die "platform-tools not found; install Android adb or set ADB=path/to/adb"
fi

a() { "$ADB" "$@"; }

# ----- find Portal ------------------------------------------------------------
step "Looking for your Portal over USB"
DEVICE=""
a start-server >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
  if [ -n "$DEVICE_SERIAL" ]; then
    state="$(a -s "$DEVICE_SERIAL" get-state 2>/dev/null | tr -d '\r')"
    [ "$state" = "device" ] && DEVICE="$DEVICE_SERIAL" && break
  else
    line="$(a devices 2>/dev/null | tr -d '\r' | awk '$2 == "device" {print $1; exit}')"
    [ -n "$line" ] && DEVICE="$line" && break
  fi
  sleep 1
done
[ -n "$DEVICE" ] || die "no Portal found; check USB cable and ADB"
ok "Portal connected: $DEVICE"

# ----- V2: UVC enumerate ------------------------------------------------------
step "V2: does the Portal see a UVC webcam over USB-C?"
printf "  Plug the USB-C OTG adapter + UVC webcam NOW if you have not already.\n"
printf "  Press Enter when the webcam is plugged, or Ctrl+C to skip.\n"
read -r _
UVD="$(a -s "$DEVICE" shell 'ls /dev/video*' 2>/dev/null | tr -d '\r')"
echo "  /dev/video* after plug:   ${UVD:-<none>}" | sed 's/^/  /'

if [ -z "$UVD" ]; then
  warn "V2 verdict: NO /dev/video* enumerated. USB-C host mode is likely disabled in firmware."
  warn "Path 2 (UVC) is NOT VIABLE on this device."
  exit 0
fi

# Check if Camera2 sees it (Android's camera service)
CMD_LIST="$(a -s "$DEVICE" shell 'cmd camera list' 2>/dev/null | tr -d '\r')"
if [ -n "$CMD_LIST" ]; then
  echo "  cmd camera list:" | sed 's/^/  /'
  echo "$CMD_LIST" | sed 's/^/    /'
fi

ok "V2 verdict: /dev/video* enumerated; USB-C host mode + UVC is working on this device."

# ----- optional: launch IP Webcam pointed at the external camera -------------
if [ "$LAUNCH_IP_WEBCAM" -eq 1 ]; then
  step "Launching IP Webcam on the Portal"
  PKG_OK="$(a -s "$DEVICE" shell pm list packages 2>/dev/null | tr -d '\r' | grep -c '^package:com.pas.webcam$')"
  if [ "$PKG_OK" -eq 0 ]; then
    warn "IP Webcam (com.pas.webcam) is not installed on the Portal."
    warn "Install it via the immortal App Store or by sideloading the APK from APKMirror,"
    warn "then re-run with --launch. See docs/keeping-portal-alive.md#uvc."
    exit 0
  fi
  ok "IP Webcam is installed; launching com.pas.webcam/.Configuration"
  a -s "$DEVICE" shell am start -n com.pas.webcam/.Configuration
  ok "Done. Back on the Portal TV, accept the camera permission, choose 'External' if prompted,"
  ok "then tap 'Start server'. The existing portal-tv-webcam pipeline (USB tunnel to host) handles the rest."
fi
