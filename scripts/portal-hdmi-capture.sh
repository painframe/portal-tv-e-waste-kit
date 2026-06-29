#!/usr/bin/env bash
#
# Copyright (c) 2026 Starbright Lab.
# Licensed under the MIT license found in the LICENSE file in the repo root.
#
# Path 1 helper: HDMI capture card on the host.
#
# Single-purpose: prove the host sees the HDMI-to-USB capture card as a standard
# UVC device. If the host enumerates the card, pipe a short test grab from
# ffmpeg to ./stream.mkv so the user can confirm the pipeline end-to-end
# before plugging it into OBS / Zoom / Meet.
#
# Usage:
#   ./portal-hdmi-capture.sh                 auto-detect by host OS (Linux/macOS/Windows-via-msys)
#   ./portal-hdmi-capture.sh --device <name> pick a specific capture card by name
#   ./portal-hdmi-capture.sh --out <path>    output file (default: ./stream.mkv)
#   ./portal-hdmi-capture.sh --help          this help
#
# Exit codes:
#   0 = capture card enumerated; stream written (or graceful interrupt)
#   1 = no capture card found (try a different USB port, see docs/keeping-portal-alive.md#hdmi-troubleshooting)
#   2 = ffmpeg missing (install ffmpeg, re-run)
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
DEVICE_NAME=""
OUT="stream.mkv"
DURATION="5"  # seconds to grab for the smoke test

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --device)    DEVICE_NAME="${2:-}"; [ -n "$DEVICE_NAME" ] || die "--device requires a name"; shift 2 ;;
    --out)       OUT="${2:-}"; [ -n "$OUT" ] || die "--out requires a path"; shift 2 ;;
    --duration)  DURATION="${2:-}"; [ -n "$DURATION" ] || die "--duration requires a value"; shift 2 ;;
    --help|-h)   usage; exit 0 ;;
    *)           die "Unknown option: $1 (use --help)"; shift ;;
  esac
done

# ----- detect host OS + enumerate the capture card ---------------------------
HOST="$(uname -s 2>/dev/null || echo unknown)"

ffmpeg_bin="$(command -v ffmpeg 2>/dev/null || true)"
[ -n "$ffmpeg_bin" ] || die "ffmpeg not found on PATH; install it and re-run. exit code 2"; true
[ -x "$ffmpeg_bin" ] || die "ffmpeg ($ffmpeg_bin) is not executable"
# (ffmpeg is technically optional for the enumerate step; we only fail if we
# actually need to write the smoke test below. Keeping the check above as a
# pre-flight so the user sees the message before the enumerate loop runs.)

case "$HOST" in
  Linux)
    step "Linux detected - enumerating /dev/video* and checking v4l2-ctl"
    if command -v v4l2-ctl >/dev/null 2>&1; then
      v4l2-ctl --list-devices 2>&1 | sed 's/^/  /'
    else
      warn "v4l2-ctl not installed; install v4l-utils for device names"
    fi
    mapfile -t VIDEO_DEVS < <(ls /dev/video* 2>/dev/null || true)
    if [ "${#VIDEO_DEVS[@]}" -eq 0 ]; then
      die "no /dev/video* present. Connect the HDMI capture card and re-run. See docs/keeping-portal-alive.md#hdmi-troubleshooting"
    fi
    PICK="${VIDEO_DEVS[0]}"
    if [ -n "$DEVICE_NAME" ]; then
      PICK="/dev/$(echo "$DEVICE_NAME" | sed -E 's#^/dev/##')"
    fi
    ok "capture device picked: $PICK"
    INPUT_DEV="$PICK"
    FFMPEG_INPUT=(-f v4l2 -i "$INPUT_DEV")
    ;;

  Darwin)
    step "macOS detected - enumerating AVFoundation video devices"
    "$ffmpeg_bin" -f avfoundation -list_devices true -i "" 2>&1 | sed -n '/AVFoundation video devices/,/AVFoundation audio devices/p' | sed 's/^/  /' || true
    PICK="${DEVICE_NAME:-USB Camera}"
    ok "capture device picked: $PICK"
    FFMPEG_INPUT=(-f avfoundation -i "$PICK")
    ;;

  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    step "Windows detected - enumerating dshow video devices"
    "$ffmpeg_bin" -f dshow -list_devices true -i dummy 2>&1 | sed -n '/DirectShow video devices/,/DirectShow audio devices/p' | sed 's/^/  /' || true
    PICK="${DEVICE_NAME:-USB Camera}"
    ok "capture device picked: $PICK"
    FFMPEG_INPUT=(-f dshow -i "video=$PICK")
    ;;

  *)
    die "Unsupported host OS: $HOST. Linux, macOS, or Windows expected."
    ;;
esac

# ----- enumerate ----------------------------------------------------------------
step "Enumerating the capture card at $PICK"
"$ffmpeg_bin" "${FFMPEG_INPUT[@]}" -t 0.1 -f null - 2>&1 | tail -20 | sed 's/^/  /' \
  && ok "capture card enumerated" \
  || die "capture card did not respond to ffmpeg. Try another USB port; see docs/keeping-portal-alive.md#hdmi-troubleshooting"

# ----- write a short smoke test to ./stream.mkv ----------------------------------
step "Writing $DURATION-second smoke test to $OUT (Ctrl+C to abort)"
if "$ffmpeg_bin" -y "${FFMPEG_INPUT[@]}" -t "$DURATION" "$OUT" < /dev/null; then
  ok "smoke test written: $OUT"
else
  warn "ffmpeg exited non-zero; the capture may still be usable - inspect $OUT"
fi

ok "Done. Open $OUT in VLC or an OBS Media Source to confirm. Then point OBS / Zoom at the capture device directly."
