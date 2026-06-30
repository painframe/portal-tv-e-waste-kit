# Keeping your Portal TV alive

The user-facing guide for the **portal-tv-e-waste-kit**. If you've just connected your
Portal TV over USB and want to know what's feasible, jump to ["Run the probe"](#probe)
first — it tells you which of the three ranked paths below actually applies to your
device.

This guide is the **decision-complete entry point**. The full evidence — every source,
every verification lead, every confidence level — lives in
[`research/portal-1080p-camera-paths.md`](research/portal-1080p-camera-paths.md).
Treat the verdict of "Run the probe" below as authoritative on what your particular
device can do. The paths to act on those verdicts are below.

## What this kit gives you (and what it doesn't)

This kit gives you **(a) a higher-quality webcam feed** from your Portal TV via one of
three ranked paths — true 1080p from the Portal's own UI compositor, an external UVC
webcam, or an algorithmic upscale of the existing 720p feed — and **(b) a probe script**
that tells you which of those paths your specific Portal supports, based on its actual
on-device state.

It does **not** give you:

- Root access.
- Bootloader unlock.
- Unmodified access to the Portal's internal camera above 720p (the 720p cap is enforced
  below the app, in the camera HAL / firmware — see the static analysis in
  [`research/`](research/index.md) for the proof).

Those are firmware facts, not bugs in this kit.

## Hardware you might need

Depending on which path applies to you:

| Path | Hardware | Approximate cost |
|------|----------|------------------|
| [HDMI capture card](#hdmi) (recommended) | Any USB HDMI capture card that exposes UVC-over-USB (Elgato Cam Link, generic £15 "HDMI USB capture" dongle, Epiphan AV.io). Optionally an HDMI splitter if you want the Portal to also be your primary TV. | £15-30 (capture) + £10 (splitter if needed) |
| [USB-C UVC external webcam](#uvc) (backup) | A UVC-class USB webcam (Logitech C920 / C922 / Brio, Microsoft LifeCam, etc.) + a USB-C OTG adapter (USB-C female → USB-A male). | £20-40 (webcam) + £5 (adapter) |
| [OBS RTX upscale](#upscale) (fallback) | An NVIDIA RTX GPU for the Super Resolution 2x filter (any RTX-class card). CPU/GPU fallbacks exist but produce noticeably worse results. | Free if you already have an RTX |

The probe script (`scripts/portal-probe.sh` / `.ps1`) needs no additional hardware beyond
a USB-C cable and your existing `adb` setup.

## The three paths, ranked

Reproduction of the round-2 ranking. Full table at
[`research/portal-1080p-camera-paths.md`](research/portal-1080p-camera-paths.md)
(Decision table + Recommended commitments).

| Rank | Path | True 1080p | AI tracking preserved | Brick risk | Effort |
|------|------|------------|----------------------|------------|--------|
| **1** | HDMI capture card (M1) | Yes (1080p) | Yes (rendered into HDMI) | None | 1-2 hours |
| **2** | USB-C UVC external webcam (M2) | Yes (webcam-native) | No (new camera has no Meta SDK) | None | 1-2 hours |
| **3** | OBS RTX Super Resolution 2x upscale of the existing 720p feed (M5) | Algorithmic — looks close to clean 1080p at Zoom/Meet resolutions, but never the sensor-native path | No (no AI on raw 720p) | None | 15-30 minutes |

All three are **independent** — you can attempt them in any order without invalidating
the others. The probe's status block tells you which to start with.

## Run the probe {#probe}

The probe is the recommended first step. It runs four verification leads on your
actual device (V1-V4 below) and prints one of three status codes per path: `READY`,
`REQUIRES-HARDWARE`, or `NOT-VIABLE`. No manual reading of `research/` is required.

**Canonical invocation:**

=== "macOS / Linux"

    ```bash
    ./scripts/portal-probe.sh
    ```

=== "Windows PowerShell"

    ```powershell
    .\scripts\portal-probe.ps1
    ```

You can pin a specific device with `--device <serial>` (or `-Device <serial>` on
PowerShell) — otherwise the probe auto-detects the first connected `device`.

The probe prints, in order:

1. **Device identity** (model + Android Security Patch level — feeds V1).
2. **V1 — Security patch level.** `QualPwn applicable iff ro.build.version.security_patch
   < 2019-08`. Marked `[VERIFIED-ON-DEVICE]` because it pulls the value off your device.
3. **V3 — Camera HAL advertised sizes.** Runs `adb shell dumpsys media.camera` and prints
   the relevant stream-configuration extract. Tells you whether `dumpsys` sees ≥1080p or
   only 720p — the round-1 pivotal question, answered on-device.
4. **V2 — USB-C host mode + UVC.** If `--uvc` is passed AND you've plugged in a UVC
   webcam via USB-C OTG, the probe compares `/dev/video*` before/after. Without
   `--uvc`, it gives a one-line status ("plug in a UVC webcam and re-run with `--uvc`").
5. **V4 — Android Device Owner slot state.** Reads `dumpsys device_policy` and reports
   whether the slot is free, held by Meta, or held by something else.
6. **(optional) Auto-claim Device Owner.** If `--claim-device-owner` is set AND V4 says
   the slot is free AND `com.immortal.launcher` is installed on the device, the probe
   runs `adb shell dpm set-device-owner com.immortal.launcher/.AdminReceiver`. With
   `--dry-run-claim`, it prints the would-be command without running it. **Both flags
   default to off.** The claim is the only write the probe ever performs.
7. **Final verdict block.** Each of the three paths with one-line status.

### What the probe does not do

- It does not write to `/system`, modify the bootloader, or touch `devinfo`.
- It does not enable ADB on the device. Settings → Debug → ADB Enabled must be on
  before you run the probe, same as the existing `portal-tv-webcam` setup requires.
  If ADB is off, the probe exits 1 with a single line of remediation copy.
- It does not upload anything. All output goes to stdout.
- It does not attempt QualPwn or any other root path. The `V1` verdict lets you know
  whether QualPwn is *theoretically applicable*; the kit never attempts it on your behalf.

### Exit codes

| Code | Meaning |
|------|---------|
| 0 | Probe ran successfully. Read the verdict block. |
| 1 | No Portal detected / `adb` not on PATH / ADB not enabled on the device. Fix as printed and re-run. |
| 2 | A `dpm set-device-owner` attempt failed. See the printed literal `dpm` output. The slot state has not been changed. |

The script uses `set -u` (not `set -e`) so a failure in one verification lead does not
abort the remaining leads. Every `adb shell` call that returns non-zero is captured,
printed, and the probe continues.

## Path 1: HDMI capture card {#hdmi}

The recommended path. Zero software risk, zero brick risk, true 1080p from the Portal's
own UI compositor. AI tracking (Smart Camera / auto-framing) is preserved because Bishop
renders the tracked frame into the display surface; the HDMI tap just reads that surface.
The hardware privacy button correctly cuts the signal (black screen on capture) — this is
the correct behaviour and matches the privacy guarantee.

### Step-by-step

1. **Buy any USB HDMI capture card** that exposes UVC-over-USB (most do). Reference
   cards: Elgato Cam Link, Epiphan AV.io, generic Chinese "HDMI USB capture" dongle.
   **Avoid cards that need proprietary drivers** — stick to UVC-class devices so it
   works as a standard webcam on Linux/Windows/macOS.
2. **Connect Portal TV HDMI out → capture card HDMI in.** Portal TV is an HDMI *output*
   stick; the captured signal is the Portal's own display at the host TV's resolution,
   typically 1080p.
3. **If you also want to use the Portal as your primary TV**, add an HDMI splitter (£10)
   upstream of the capture card.
4. **Connect capture card USB → host PC.**
5. **Verify the host sees the capture as a webcam:**

    === "Linux"

        ```bash
        v4l2-ctl --list-devices    # should show a new /dev/videoN
        ```

    === "macOS"

        Open **Photo Booth** or **QuickTime → New Movie Recording** — the card should
        appear in the camera list as "USB Camera" or similar.

    === "Windows"

        Open **Camera** (Win+I → Bluetooth & devices → Camera) — the card should appear
        in the camera list.

6. **Use it in OBS / Zoom / Meet / Teams.** No driver install, no SDK, just a standard
   UVC webcam.

The helper [`scripts/portal-hdmi-capture.sh`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/scripts/portal-hdmi-capture.sh)
(or `.ps1`) verifies the host sees the capture and pipes a short test grab to
`stream.mkv` so you can confirm the path end-to-end before plugging it into OBS.

### Troubleshooting {#hdmi-troubleshooting}

- **Capture card not enumerated** → try a different USB port (some are USB-2 only,
  some are USB-3 only; cards vary). Try without a USB hub. Try a different card.
- **Capture card shows up but image is black** → press the Portal's hardware privacy
  button on the camera bar (it physically disconnects the camera; HDMI shows a black
  frame because the Portal's UI is showing a privacy screen).
- **Audio: HDMI capture does NOT include the Portal's mic** — HDMI carries display
  audio, not the microphone, so this is true regardless of permissions. Capture the
  mic separately on the host (USB/Bluetooth), **or** read it in a sideloaded app:
  the built-in **single-channel mic works** for your own apps with plain
  `RECORD_AUDIO` (grant it: `pm grant <pkg> android.permission.RECORD_AUDIO`) —
  confirmed by Meta's official Portal build skill. Only the far-field beamformed
  array ("Hey Portal" pickup) is locked, behind the Meta-signed
  `com.facebook.alohasdk.permission.RECORD_AUDIO_PRIVILEGED`. The earlier
  "mic → silence" note was a missing-grant artefact, not a hard gate.

## Path 2: USB-C UVC external webcam {#uvc}

The backup path if HDMI is in use or if you want a *better* camera than the Portal's
built-in. Standard `uvcvideo` kernel driver, standard `Camera2` framework — the Portal's
custom HAL gate on the internal camera does not apply because the external UVC device
goes through the generic kernel binding, not `com.qualcomm.qti.camera`.

**Unknown before you run the probe:** whether Meta's firmware disables USB host mode
for UVC class devices (no Portal-specific documentation confirms or denies it). The
probe's V2 verdict is the deciding experiment.

### Step-by-step

1. **Acquire a UVC-class USB webcam** (Logitech C920/C922/Brio, Microsoft LifeCam, etc.).
2. **Connect it via a USB-C OTG adapter** (USB-C female → USB-A male, ~£5) to the
   Portal's USB-C port.
3. **Run the probe with `--uvc`**:

    === "macOS / Linux"

        ```bash
        ./scripts/portal-probe.sh --uvc
        ```

    === "Windows PowerShell"

        ```powershell
        .\scripts\portal-probe.ps1 -Uvc
        ```

4. **If V2 reports the UVC webcam is visible** (`/dev/videoN` enumerated AND
   `cmd camera list` shows a new camera ID): you can install IP Webcam or PortalCam and
   select the external camera in-app, then stream via the existing `portal-tv-webcam`
   pipeline (USB tunnel → host → OBS).
5. **If V2 reports the UVC webcam is NOT visible**: don't fight it — fall back to the
   OBS upscale path (#3).

The helper [`scripts/portal-uvc-external.sh`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/scripts/portal-uvc-external.sh)
automates steps 3-4 and, when a UVC webcam is visible, launches IP Webcam pointed at
the external camera.

### What you lose (vs path 1)

The external UVC webcam has no Meta SDK, so **AI tracking is lost**. If you depend on
auto-framing, this is the wrong path.

## Path 3: OBS RTX upscale (fallback) {#upscale}

The "give up on 1080p" path. Already works today with the existing `portal-tv-webcam`
project — no software modifications, no brick risk, ~15-30 minute setup.

### Step-by-step

1. **Set up `portal-tv-webcam`** per that project's README (PortalCam app + USB tunnel
   + OBS).
2. **Install NVIDIA Broadcast** (provides the RTX Super Resolution plugin for OBS).
3. **In OBS, add the camera source's filters in this order:**

    1. NVIDIA Artefact Reduction
    2. NVIDIA Super Resolution (set to 2×)

    Artefact Reduction removes compression blocks *before* the image is upscaled,
    which makes the 720p feed look closer to a clean 1080p webcam.

4. **Use OBS Virtual Camera as the webcam in Zoom/Meet.**

The helper [`scripts/portal-obs-upscale.sh`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/scripts/portal-obs-upscale.sh)
(or `.ps1`) is a thin wrapper that extends the existing `portal-tv-webcam` setup by
applying this filter chain automatically on launch.

### What you lose (vs paths 1 & 2)

The OBS upscale is **algorithmic** — it never reads more pixels than the 720p HAL
gates, it just makes those pixels look cleaner and bigger. AI tracking is also lost
(no AI on raw 720p). For most video-call use at Zoom/Meet resolution, the result is
indistinguishable from a clean native 1080p webcam (per the round-2 community-sourced
evidence).

### Without an NVIDIA GPU

CPU-based upscaling (`obs-scale` with FSRCNNX x2) works but with noticeably more
latency (~200-400 ms) and softer output. Acceptable for static scenes, less so for
talking-head streaming.

## Rollback / undo {#rollback}

Every path has a documented inverse.

| Path | How to undo |
|------|-------------|
| HDMI capture | Nothing to undo. Pure read-only hardware tap. Unplug the capture card and the Portal is back to stock. |
| USB-C UVC | Nothing to undo. Unplug the webcam and the Portal is back to stock. The probe never installs anything. |
| OBS upscale | Revert OBS filters (remove the two NVIDIA filters) or restore the OBS scene from your pre-upscale backup. No device change. |
| `dpm set-device-owner` (from the probe's auto-claim step) | `Settings → System → Reset options → Erase all data (factory reset)`. This is a full factory reset — there's no per-app "release device owner" command without device-wipe-level privileges, and the kit will never wipe without explicit user action. |
| `set-device-owner` refused (slot held by Meta) | The probe refuses the claim and prints a single-sentence instruction to factory-reset before retrying. The script does not auto-factory-reset. |

The **only write the kit performs is the optional Device Owner claim**, gated by
`--claim-device-owner` (off by default), V4 slot-free check, and the device having
the `com.immortal.launcher` admin receiver installed. Everything else is observation.

## How this guide relates to the research

This guide is the user-facing view. The full evidence — every source, every
verification lead, every confidence level, every testable hypothesis — is in
[`research/portal-1080p-camera-paths.md`](research/portal-1080p-camera-paths.md)
(round 2). Round 2 builds on
- [the round-1 privilege-model writeup](https://github.com/starbrightlab/immortal/blob/main/docs/research/meta-portal-privilege-model.md)
  (round 1; the source file lives in the sibling `immortal` repo at
  `docs/research/meta-portal-privilege-model.md`).

If you want to challenge a recommendation, challenge the round-2 artifact — and the
round-1 axioms it takes as given. There is no third layer.

## Cross-links

- [`README.md`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/README.md) - repo-level tour.
- [`research/index.md`](research/index.md) — research-folder index.
- [`research/portal-1080p-camera-paths.md`](research/portal-1080p-camera-paths.md)
  — round 2 (load-bearing reference; body byte-stable).
- [`starbrightlab/immortal`](https://github.com/starbrightlab/immortal) — the home
  screen the kit claims Device Owner for.
- [`starbrightlab/portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam)
  — the 720p webcam setup the OBS-upscale path extends.
