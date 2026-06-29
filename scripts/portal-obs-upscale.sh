#!/usr/bin/env bash
#
# Copyright (c) 2026 Starbright Lab.
# Licensed under the MIT license found in the LICENSE file in the repo root.
#
# Path 3 helper: OBS + NVIDIA RTX Super Resolution 2x upscale of the existing 720p feed.
#
# Single-purpose: thin wrapper around the existing portal-tv-webcam script that
# ALSO installs the NVIDIA filter chain (Artefact Reduction -> Super Resolution
# 2x) on the camera source. The portal-tv-webcam repo's start-portal-cam.ps1
# already handles the USB tunnel + camera app + OBS launch.
#
# Pre-requisites (verified once by this script, then a clear error if missing):
#   - adb on PATH (port-portal-cam's start-portal-cam sets it up)
#   - obs on PATH, OR OBS_STUDIO_BIN env var pointing at obs64/obs
#   - The NVIDIA Broadcast / RTX Super Resolution plugin installed in OBS
#     (https://github.com/Bemjo/OBS-RTX-SuperResolution)
#
# Usage:
#   ./portal-obs-upscale.sh                       arm tunnel + camera + OBS + filters
#   ./portal-obs-upscale.sh --scene <name>        apply filters to a specific scene
#                                                 (default: first scene)
#   ./portal-obs-upscale.sh --source <name>       apply filters to a specific source
#                                                 (default: PortalCam source)
#   ./portal-obs-upscale.sh --help                this help
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
SCENE=""
SOURCE=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --scene)        SCENE="${2:-}"; [ -n "$SCENE" ] || die "--scene requires a name"; shift 2 ;;
    --source)       SOURCE="${2:-}"; [ -n "$SOURCE" ] || die "--source requires a name"; shift 2 ;;
    --help|-h)      usage; exit 0 ;;
    *)              die "Unknown option: $1 (use --help)"; shift ;;
  esac
done

# ----- pre-flight ------------------------------------------------------------
step "Pre-flight checks"
PORTAL_TV_WEBCAM="${PORTAL_TV_WEBCAM:-$SCRIPT_DIR/../../portal-tv-webcam}"
if [ ! -d "$PORTAL_TV_WEBCAM" ]; then
  die "sibling repo portal-tv-webcam not found at $PORTAL_TV_WEBCAM - clone it next to this kit and re-run"
fi
ok "portal-tv-webcam: $PORTAL_TV_WEBCAM"

OBS_BIN="${OBS_BIN:-${OBS_STUDIO_BIN:-obs}}"
if ! command -v "$OBS_BIN" >/dev/null 2>&1; then
  die "obs binary not on PATH and OBS_BIN is unset; install OBS Studio and re-run"
fi
ok "obs binary: $(command -v "$OBS_BIN")"

ADBCMD="${ADB:-adb}"
if ! command -v "$ADBCMD" >/dev/null 2>&1; then
  die "adb not on PATH; install Android platform-tools and re-run"
fi
ok "adb: $(command -v "$ADBCMD")"

# ----- arm the existing portal-tv-webcam pipeline ----------------------------
step "Arming the portal-tv-webcam pipeline (USB tunnel + camera + OBS)"
case "$(uname -s)" in
  Darwin|Linux)
    if command -v pwsh >/dev/null 2>&1; then
      pwsh -NoProfile -File "$PORTAL_TV_WEBCAM/scripts/start-portal-cam.ps1" \
        || warn "portal-tv-webcam launcher exited non-zero - inspect its output above"
    else
      die "pwsh not on PATH; install PowerShell 7+ and re-run"
    fi
    ;;
  MINGW*|MSYS*|CYGWIN*|Windows_NT)
    powershell.exe -NoProfile -ExecutionPolicy Bypass \
      -File "$PORTAL_TV_WEBCAM/scripts/start-portal-cam.ps1" \
      || warn "portal-tv-webcam launcher exited non-zero - inspect its output above"
    ;;
  *)
    die "Unsupported host OS: $(uname -s)"
    ;;
esac

# ----- apply the NVIDIA filter chain via OBS WebSocket ----------------------
step "Applying the NVIDIA filter chain (Artefact Reduction -> Super Resolution 2x)"
if [ -z "$SOURCE" ]; then
  SOURCE="PortalCam"
  warn "--source not set; defaulting to '$SOURCE' (the typical portal-tv-webcam source)."
fi
APPLY="$SCRIPT_DIR/portal-obs-upscale-apply.py"
if [ ! -f "$APPLY" ]; then
  die "missing $APPLY - the kit's helper Python file disappeared"
fi
OBS_HOST="${OBS_HOST:-127.0.0.1}"
OBS_PORT="${OBS_PORT:-4455}"
OBS_PASSWORD="${OBS_PASSWORD:-}"
warn "Prerequisites (not auto-installed):"
warn "  - In OBS Studio -> Tools -> obs-websocket Settings: enable the server, copy the password"
warn "  - The NVIDIA RTX Super Resolution plugin (Bemjo/OBS-RTX-SuperResolution) must be installed"
printf "  Running: python3 %s --host %s --port %s --source %s\\n" \
  "$APPLY" "$OBS_HOST" "$OBS_PORT" "$SOURCE"
PASSWORD_ARGS=()
if [ -n "$OBS_PASSWORD" ]; then PASSWORD_ARGS=(--password "$OBS_PASSWORD"); fi
SCENE_ARGS=()
if [ -n "$SCENE" ]; then SCENE_ARGS=(--scene "$SCENE"); fi
python3 "$APPLY" --host "$OBS_HOST" --port "$OBS_PORT" \
    "${PASSWORD_ARGS[@]}" --source "$SOURCE" "${SCENE_ARGS[@]}"
RC=$?
if [ "$RC" -eq 0 ]; then
  ok "filter chain applied."
else
  die "filter chain helper exited with code $RC (source missing? obs-websocket not enabled? password wrong?)"
fi
