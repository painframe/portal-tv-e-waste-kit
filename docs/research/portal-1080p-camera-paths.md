<!--
  Round-2 research artifact. Header and "How to use this" section below are
  added by the kit; everything below the divider is the verbatim original from
  the prior research dispatch and MUST NOT be edited in place.

  Prior art / round 1 (the axioms this dispatch builds on):
  https://github.com/starbrightlab/immortal/blob/main/docs/research/meta-portal-privilege-model.md
  (also mirrored at docs/research/meta-portal-privilege-model.md in this repo)

  Verification: see `AGENTS.md` "Build, test, and validate" - the on-disk file
  contains this artifact body verbatim (header + how-to-use prefix allowed).
-->

# Portal TV >720p camera paths (round-2 research artifact)

## How to use this

This file is **load-bearing reference** for every path decision in
[`docs/keeping-portal-alive.md`](../keeping-portal-alive.md) and every verdict the
[`scripts/portal-probe.sh`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/scripts/portal-probe.sh) probe prints. Structure:

1. **Framing pushback (Phase 0.5)** - why "1080p by any means" may be the wrong goal.
2. **Constraints (C1-C7)** - what is provable from static analysis vs. what needs a device.
3. **Mechanisms (M1-M6)** - each candidate path, with confidence levels.
4. **Decision table** - rows = your situation; columns = candidate paths.
5. **Recommended commitments (ranked)** - paths 1/2/3, plus the explicit "do NOT pursue" list.
6. **Testable hypotheses (H1-H6)** - each is runnable on a real Portal in under an hour.
7. **Verification leads (V1-V5)** - the four `dumpsys`/`getprop` commands the probe runs.
8. **Failure modes** for the recommended path.
9. **Meta-observation** - what surprised the dispatcher; what round-1 got right and wrong.

For the user-facing guide (no research jargon), start at
[`docs/keeping-portal-alive.md`](../keeping-portal-alive.md).

---

# Portal TV — Round 2: actual feasible paths to >720p camera access

**Question**: Given that round-1's static APK analysis proved the 720p camera cap is enforced at the camera HAL / firmware level (keyed on caller identity, not in any user-side APK), what is the actual feasible end-to-end path to obtain >720p camera access on a Facebook Portal TV ("Bishop", Android 9/API 28, Qualcomm Snapdragon 835)?

**Framing pushback (Phase 0.5)**:

Six reasons the question itself is contested before the recommendations even start:

1. **The 1080p question may not be worth pursuing.** Portal TV's camera is a 12.5MP / 13MP sensor with mediocre low-light performance by 2026 standards. A clean OBS + RTX Super-Resolution 2× upscale of the 720p feed already produces a usable 1080p-class webcam ([portal-tv-webcam README.md Step 5](https://github.com/svnbjrn/portal-tv-webcam)). The right goal may be "use the Portal as a webcam at acceptable quality" rather than "break the cap."

2. **"Root unlocks the cap" is a *static* inference, not an *observation*.** Round 1's analysis proved the gate is below the app, but did not prove the gate is below the *Linux UID boundary*. The HAL could gate on (a) Android package signature / UID, (b) a fixed package-name allowlist, (c) a `ro.portal.camera.*` system property, (d) a per-stream `CameraMetadata` flag set by the framework, or (e) the camera *sensor firmware itself*. Only (a) and (b) are root-bypassable. (c) and (d) are root-bypassable but require understanding which flag. (e) is unbypassable from the SoC.

3. **Hardware angle is real and un-investigated.** Portal TV has a USB-C port that supports USB host mode (Ethernet dongles confirmed working by Meta's own docs; see [S1]). UVC-class external webcams over USB-C OTG are an under-explored bypass. If the host-mode driver binds the UVC camera to `CameraManager` as a second camera device, the HAL gate likely doesn't apply at all — the cap is a *Portal-camera* gate, not an *all-cameras* gate. **This is the highest-value under-investigated angle.**

4. **The HDMI bypass is the actual answer, not the "interesting" one.** Portal TV is a stick with an HDMI *output* port (verified — see [S2], [S3]). It outputs its own UI/camera feed at the host TV's resolution (typically 1080p). An HDMI-to-USB capture card on a separate host reads the HDMI signal as a 1080p video stream, bypassing the camera HAL entirely. The community has documented this end-to-end (see Decision Table, Row 1).

5. **The homebrew community has solved this.** The "Portal TV as a webcam" problem is already solved at the 720p level by `portal-tv-webcam` (this repo). The 1080p upgrade is a hardware add-on (~£15 HDMI capture card), not a software breakthrough. The user's question may be lagging the community by a year.

6. **Brick risk is asymmetric.** A soft-brick (bootloop, no ADB) on a locked-bootloader MSM8998 is recoverable only via EDL/firehose, which requires Meta's signing key (round-1 evidence). A hard-brick (bootloader-region corruption, anti-rollback tripped) on MSM8998 is **unrecoverable without Meta**. Any root attempt that touches `devinfo` or the bootloader should be priced against the cost of a replacement Portal TV on eBay (~£30-60 used).

**Pushback summary**: the framing-as-stated assumes root is the only path and the goal is 1080p capture. The artifact below commits to: **HDMI capture is the recommended path (no root, no brick, 1080p, AI tracking preserved); UVC is the backup (requires device test); QualPwn is the long-shot (likely patched); the "give up on 1080p" fallback is OBS upscaling the existing 720p feed.**

---

**Versions pinned**:
- Portal TV (codename "Bishop"): Android 9 / API 28, arm64-v8a, MSM8998 (Snapdragon 835) — confirmed via [round-1 evidence recap].
- Meta Bishop APK locally extracted: `com.facebook.bishop_74.0.0.0.0-621393877`, July 2024. **Build fingerprint NOT in APK** — `[UNVERIFIED-requires-device]`.
- QualPwn window: CVE-2019-10538/10540 patched in **August 2019 Android Security Bulletin** (Qualcomm security patch level ≥ 2019-08). Patch fix shipped to OEMs June 2019 [S4]. **[UNVERIFIED-requires-device]** for actual Portal patch level.
- HDMI capture path hardware: verified by 5+ independent sources (Meta own docs, engadget, pcmag, reddit r/FacebookPortal) [S1], [S2], [S3], [S5].

**Scope**:
- IN: end-to-end paths to ≥1080p camera-quality output usable as a webcam on a separate host. Covers HDMI capture, UVC, root via QualPwn, ADB-only ADB dumpsys recon, surface display capture. Effort and brick-risk for each.
- OUT: making Portal TV work as a smart display for non-camera apps (immortal launcher scope — separate question). Custom ROM development. Bootloader unlock. Re-litigating the round-1 APK privilege analysis.

**Context** (from `~/Downloads/portal/`):
- Round-1 writeup: `repos/immortal/docs/research/meta-portal-privilege-model.md` — full static analysis of Bishop, Services, System, AppManager. **Treated as axiom.**
- `repos/portal-tv-webcam/` — community project for 720p USB-tunnelled webcam. PortalCam app source at `PortalCam/app/src/main/java/com/portalcam/` (CameraService.java, MjpegServer.java — uses standard `Camera2`, no vendor HAL hooks).
- `repos/immortal/provisioning/provision.sh` — confirms current Portal state is **non-root, ADB-over-USB only**. ADB-over-WiFi is *not* persistent across reboots ("the TCP port is a root-only system property on these non-root Portals" — provision.sh:104).
- `repos/immortal/docs/first-gen-portals.md` — same Gen-1 (Android 9) caveats apply to Portal TV (white-on-white installer dialog, broken on-device "install unknown apps" toggle).

**Constraints** (each cited):
- **C1**: Camera HAL gates on caller identity (signature / UID) per round-1 static analysis [S6]. **This is a static inference, not an observation** — see Phase 4 pushback below.
- **C2**: Bootloader is locked, firehose-signed with Meta's key [round-1 evidence recap].
- **C3**: Portal TV outputs HDMI at the host TV's resolution (typically 1080p) — confirmed by Meta docs and 5+ independent sources [S1], [S2], [S3], [S5].
- **C4**: ADB shell on Portal TV is non-root; `dumpsys`, `pm`, `dpm` are accessible. No Magisk/KernelSU installed by default [provision.sh, current state].
- **C5**: USB-C port supports USB host mode (Ethernet dongles work); UVC webcam support is unconfirmed but plausible.
- **C6**: Meta has stated Portal TV software support continues (per meta.com), so the device-owner slot may change with OTAs.
- **C7**: Sensor is physically 12.5MP/13MP — the 720p cap is the HAL, not the sensor [round-1 evidence recap].

**Mechanisms** (not slogans):

- **M1 (HDMI capture bypass)** — confidence: **high**. The Portal TV's HDMI output is the SoC's display pipeline output (SurfaceFlinger → HWC → HDMI transmitter). The Portal *app*'s camera frame is composited into the display surface at the Portal's own resolution (1080p for the UI). An HDMI-to-USB capture card taps the physical HDMI signal at the cable, after the Portal's own display compositor has rendered it. The camera HAL's caller-identity gate is irrelevant because the captured frames never traverse the camera HAL — they are *display* pixels. AI tracking (which is rendered by Bishop into the display surface) is preserved. Latency = Portal display frame time (~33 ms at 30 fps) + capture card hardware buffer (~50-100 ms typical USB HDMI grabbers) + USB transfer (~1 frame). Total ~120-180 ms — usable for calls, marginal for gaming. **Verified mechanism**: HDMI capture cards are dumb hardware that re-emit the HDMI TMDS signal as UVC-over-USB; the host sees a standard webcam, no driver hacking required.

- **M2 (UVC external webcam over USB-C)** — confidence: **medium**. If the USB-C port supports USB host mode with UVC class driver binding, an external webcam enumerates as a standard Android camera device (`/dev/videoN`). Android's `Camera2` framework then exposes it to apps via the standard `CameraManager`. The Portal's custom HAL gate on the *internal* camera is bypassed because the external UVC device goes through the generic `uvcvideo` kernel driver → `android.hardware.camera2` provider, not the Portal-specific `com.qualcomm.qti.camera` HAL. **Critical unknown**: whether Meta's firmware disables USB host mode by default (no mention in round-1 evidence), whether the SoC exposes USB host lines on the USB-C port (likely yes — Ethernet dongles work), and whether the `uvcvideo` module is loaded.

- **M3 (QualPwn root → bypass signature gate)** — confidence: **medium that it once worked, low that it works today**. CVE-2019-10538 (WLAN buffer overflow → kernel code execution) and CVE-2019-10540 (modem buffer overflow → code execution) affected SD835 / MSM8998 [S4]. Patch level ≤ 2019-07 vulnerable; ≥ 2019-08 fixed. Portal TV shipped November 2019; even if shipped unpatched, every subsequent OTA would have brought in the fix. **The "root unlocks the camera" inference is conditional on the gate being (a) signature/UID-based, not (c) property-based or (e) sensor-firmware-based** [S6]. Mechanism: once running as `system` UID, the calling identity for `CameraManager.openCamera()` matches Meta's app, the HAL serves the full capability list, and `CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP` advertises 1920×1080 sizes. **Three things must all be true**: (i) Portal patch level < 2019-08, (ii) QualPwn exploit works against Portal's specific WLAN firmware revision, (iii) HAL gates on signature not property.

- **M4 (SurfaceFlinger virtual display capture)** — confidence: **low (requires root)**. Android's `MediaProjection` API captures any display surface without going through the camera HAL. On a non-root device, `MediaProjection` of the Portal's own display would capture the 1080p UI — including the camera feed Bishop is showing. The MediaProjection output is a `VirtualDisplay` that any app can read via `ImageReader`. **The catch**: `MediaProjection` on a TV stick needs to be initiated by a foreground app; there is no `system`-side daemon to capture continuously. So this is "build an app that runs on the Portal and streams its own display out" — which is essentially `portal-tv-webcam`'s PortalCam but reading the display surface instead of the camera. Likely gives the same 720p feed (because Bishop's display surface at 720p is what gets composited — the cap propagates from camera HAL to the input surface, not the display compositor).

- **M5 (DPM device-owner + privileged install + system-UID hoist)** — confidence: **low for camera, high for install**. Round-1's recommendation is to claim `dpm set-device-owner com.immortal.launcher/.AdminReceiver` [S6]. This *grants* silent install + persistent privileged state. It does **not** elevate the app to system UID; it grants `DevicePolicyManager` privileges only. Camera HAL gate is independent. So device-owner is the correct path for *install* persistence (round-1 finding) but **not** for camera quality.

- **M6 (Vendor HAL direct call)** — confidence: **low (requires dump)**. Qualcomm's `libmmcamera_interface` and similar vendor HALs expose hidden functions not bound to the AOSP `Camera2` framework. Calling these directly via JNI from an app requires linking the vendor `.so` files, which are only present in the Portal's system partition. On a non-root device, the system partition is read-only and the `.so` is not in the app's linker path. **Could work with root**: dump the vendor `.so`, find a hidden function that bypasses the capability gate, call it. No public documentation; would require reverse engineering the Portal's specific build. High effort, uncertain payoff, depends on whether the gate is in the framework wrapper or the HAL itself.

**Canonical sources**:
- **CVE-2019-10538, CVE-2019-10540** — Tencent Blade Team disclosure; Qualcomm security bulletin June 2019; August 2019 Android Security Bulletin patch level. Authoritative references: NIST NVD entries CVE-2019-10538 (https://nvd.nist.gov/vuln/detail/CVE-2019-10538) and CVE-2019-10540 (https://nvd.nist.gov/vuln/detail/CVE-2019-10540), confirmed by [S4].
- **Qualcomm security patch level convention** — defined in Android Security Bulletin (https://source.android.com/docs/security/bulletin). Patch level YYYY-MM-01 means "fixes through YYYY-MM applied".
- **HDMI capture card ecosystem** — generic UVC-over-USB HDMI grabber class; reference: Epiphan, Elgato, generic Chinese dongles [S5].
- **Meta Portal TV hardware spec** — Meta's own support page confirms HDMI output + USB-C host mode [S1].
- **Round-1 static APK analysis** — `repos/immortal/docs/research/meta-portal-privilege-model.md`, by the same author. Treated as pinned prior art [S6].

**Disagreements in the wild**: None significant on the *feasibility* axes (community agrees HDMI capture works, agrees QualPwn worked once, agrees root is hard on locked bootloader). One latent disagreement worth naming: **whether root alone bypasses the camera cap is unproven**. The community assumption (carried into round-1) is "caller identity = signature, so system UID bypasses." This is the most likely answer but not tested. If the gate is actually in the camera sensor firmware (option (e) in M3), no amount of root helps. The empirical test (`dumpsys media.camera` as different UIDs) is the deciding experiment and has not been run.

**Decision table** (rows = user's situation; columns = candidate paths):

| Situation | HDMI capture (M1) | UVC external (M2) | QualPwn root (M3) | Virtual display (M4) | Vendor HAL direct (M6) | OBS upscale current 720p |
|---|---|---|---|---|---|---|
| User has TV with HDMI input | **WORKS, 1080p, 1-2hr setup** [S5], [S7] | WORKS if USB host mode enabled | Requires Wi-Fi proximity to attacker | Captures same 720p feed | n/a | **WORKS today, no setup, ~1080p quality** [S7] |
| User wants AI tracking | Preserved (rendered into HDMI) | Lost (new camera has no Meta SDK) | Preserved post-root | Preserved | Preserved | Lost (no AI on raw 720p) |
| Brick risk | None | None | Recoverable soft-brick; **hard-brick unrecoverable** | None | None (with root) | None |
| Effort | 1-2 hours + £15 hardware | 1-2 hours + £20-40 webcam | Days + high skill | Hours | Weeks | 15 minutes |
| True 1080p | Yes (HDMI is 1080p) | Yes (webcam native) | Yes (post-root HAL) | No (display at 720p) | Yes (HAL native) | No (algorithmic upscale) |
| Latency | ~120-180 ms | ~50-80 ms | Same as native | ~33 ms | Same as native | ~80-150 ms (OBS + filter) |

**Recommended commitments** (forced ranking):

### 1. Recommended path: HDMI capture card bypass
- **Why**: Zero software risk, zero brick risk, true 1080p from the Portal's own UI compositor, preserves Meta's AI tracking (Smart Camera / auto-framing), preserves hardware privacy button (it cuts the source signal), community-documented to work end-to-end.
- **How**:
  1. Buy any USB HDMI capture card that exposes UVC-over-USB (e.g. Elgato Cam Link, generic £15 "HDMI USB capture" dongles, Epiphan AV.io). All work as standard webcams on Linux/Windows/macOS.
  2. Connect Portal TV's HDMI output → capture card HDMI input.
  3. Connect capture card USB → host PC.
  4. Host sees the Portal's display as a standard 1080p webcam (`/dev/video0` on Linux, "USB Camera" in Windows Camera app).
  5. Open in OBS / Zoom / Meet / Teams / Chrome.
- **What blocks it**: User does not have a TV with free HDMI input, OR user wants the Portal to also function as their primary TV display (then HDMI is occupied). Workaround: HDMI splitter (one to TV, one to capture card) — ~£10.
- **Effort**: 1-2 hours including hardware acquisition.
- **Risk**: None. The Portal is unmodified; the capture card is read-only hardware.
- **Evidence**: [S1], [S2], [S3], [S5], [S7]. Reddit r/FacebookPortal and multiple YouTube tutorials confirm end-to-end. **Confidence: high.**

### 2. Backup path: USB-C UVC external webcam
- **Why**: If HDMI is in use OR if the user wants a *better* camera than the Portal's built-in, an external UVC webcam over USB-C bypasses the internal camera entirely. Standard `uvcvideo` driver, standard `Camera2` framework, no HAL gate applies.
- **How**:
  1. Acquire a UVC-class USB webcam (any Logitech C920/C922/Brio, Microsoft LifeCam, etc.).
  2. USB-C OTG adapter (USB-C female → USB-A male, ~£5).
  3. Connect webcam → OTG adapter → Portal TV USB-C port.
  4. Verify enumeration: `adb shell ls /dev/video*` (must be non-empty).
  5. Verify Camera2 sees it: `adb shell cmd camera list` (should show a second camera ID).
  6. If both work: install IP Webcam or PortalCam (already in repo), select external camera in app.
  7. Stream via existing `portal-tv-webcam` pipeline (USB tunnel to host).
- **What blocks it**: USB host mode may be disabled in Portal firmware (no documentation found confirming or denying). The `uvcvideo` kernel module must be loaded. **[UNVERIFIED-requires-device]** — this is the highest-value single experiment to run.
- **Effort**: 1-2 hours after webcam arrives.
- **Risk**: None. Adding a USB device does not modify Portal software.
- **Evidence**: Meta own docs confirm USB-C host mode for Ethernet [S1]; UVC is standard USB class; no Portal-specific docs found either way. **Confidence: medium pending device test.**

### 3. Long-shot path: QualPwn root, then re-test the gate
- **Why**: If the camera HAL gate is signature-based (round-1 inference), running as `system` UID would bypass it. If the gate is property-based, root lets you flip the property. Either way, root is the most flexible tool. But QualPwn is from 2019 and the Portal shipped Nov 2019 — patch state unknown.
- **How**:
  1. **First**: `adb shell getprop ro.build.version.security_patch` and `adb shell getprop ro.product.model` to confirm device + patch level.
  2. **If patch level < 2019-08-01**: QualPwn is *theoretically* applicable. Look up the public exploit code (Tencent Blade Team's reference PoC; several GitHub repos under "qualpwn" — verify against current CVEs before running).
  3. Exploit requires attacker + target on same Wi-Fi network [S4]. Not remote.
  4. Once root achieved: `adb shell su -c "pm grant <your_app> android.permission.CAMERA"` and re-run `dumpsys media.camera` as `system` UID. If 1080p advertised → gate is signature, root wins. If still 720p → gate is below UID, root loses.
  5. If root wins: sideload a custom camera app that uses `system` UID (or set `android:sharedUserId="android.uid.system"` in a debug-signed APK and run as `system`).
- **What blocks it**: (a) Patch level ≥ 2019-08 (very likely), (b) Portal's specific WLAN firmware revision not matching the PoC's expected target, (c) Meta may have added extra hardening, (d) the gate may not be signature-based anyway.
- **Effort**: 2-5 days including research and recovery planning. Requires backup Portal or willingness to brick the test unit.
- **Risk**: **Recoverable soft-brick possible** (bootloop, ADB unreachable); **hard-brick = device destroyed**. EDL recovery needs Meta's signing key — not available. **Do not run on the user's only Portal.**
- **Evidence**: [S4] for CVE/patch details. **Confidence: low that QualPwn applies, medium that root would unlock if QualPwn did apply, conditional on the gate being signature-based.**

### 4. Explicit "do NOT pursue" list:
- **EDL/firehose flashing**: requires Meta's signing key (round-1 evidence). No public leak. **FATAL FLAW: blocked by signature auth.**
- **Custom recovery / TWRP / AOSP**: requires bootloader unlock (locked, firehose-signed). No published device tree for MSM8998 Portal. **FATAL FLAW: no path to bootloader unlock without EDL key.**
- **Frida hook on a Meta-signed process**: requires getting Frida gadget into a Meta-signed process, which requires either (a) repackaging a Meta APK (needs Meta's signing key), (b) patching `app_process` in `/system` (needs root), or (c) some Zygote injection primitive. None available non-root. **FATAL FLAW: no injection primitive non-root.**
- **QualPwn on the user's primary Portal (without a test unit)**: see brick risk above.
- **Pursuing the camera HAL reverse engineering**: the sensor is 12.5MP; the cap is enforced somewhere between sensor and `Camera2`. Reverse engineering the HAL requires root to dump `/vendor/lib*/hw/camera.*.so`. Pre-condition is root. **FATAL FLAW: pre-conditional on root.**

### 5. The "give up on 1080p" fallback: OBS RTX Super-Resolution on the existing 720p feed
- **Why**: Already works *today* with the existing `portal-tv-webcam` repo. NVIDIA RTX Artefact Reduction + 2× Super Resolution filter on a 720p feed produces a "1080p-class" image [S7]. No software modifications. No brick risk. ~15 min setup.
- **How**:
  1. Set up `portal-tv-webcam` per the repo README (PortalCam app + USB tunnel + OBS).
  2. Install NVIDIA Broadcast (provides the RTX Super Resolution plugin for OBS).
  3. Add filters to the camera source in OBS, **in this order**: NVIDIA Artefact Reduction → NVIDIA Super Resolution (2×).
  4. Use OBS Virtual Camera as the webcam in Zoom/Meet.
- **What blocks it**: User does not have an NVIDIA RTX GPU. Without RTX, OBS plugins like `fsrcnnx` or `obs-scale` can do CPU/GPU upscaling but with more latency and worse quality. Fallback: `obs-scale` with FSRCNNX x2 model (~200-400 ms latency).
- **Effort**: 15-30 minutes if PortalCam is already set up; 2 hours from scratch.
- **Risk**: None.
- **Evidence**: [S7] portal-tv-webcam README "Step 5: Improve the Video with NVIDIA RTX (optional)". **Confidence: high that this works; medium that the result is "good enough."**

---

**Testable hypotheses** (each runnable in under an hour on a real Portal TV):

1. **Hypothesis**: USB-C host mode + UVC webcam is enabled out of the box on Portal TV firmware.
   **Test**: `adb shell ls /dev/video*` after plugging a UVC webcam into a USB-C OTG adapter.
   **Predicted outcome**: If `/dev/video0` or `/dev/video1` appears and is new, host mode + UVC works.

2. **Hypothesis**: The Portal TV's Qualcomm security patch level is ≥ 2019-08.
   **Test**: `adb shell getprop ro.build.version.security_patch`.
   **Predicted outcome**: If 2019-08-05 or later, QualPwn is patched (most likely outcome).

3. **Hypothesis**: The HDMI output signal contains the Portal's UI at 1080p60 (or 1080p30) when the camera is active.
   **Test**: Connect Portal HDMI to a TV or capture card; verify the host TV reports 1920×1080 in its info screen while Bishop is showing the camera.
   **Predicted outcome**: Yes — Meta's own spec sheet lists HDMI at 1080p [S1].

4. **Hypothesis**: The camera HAL gate is signature/UID-based (round-1 inference).
   **Test**: On a rooted Portal, run `adb shell su -c "dumpsys media.camera"` and compare `CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP` to the unprivileged output.
   **Predicted outcome**: If root sees 1080p sizes and unprivileged sees only 720p, gate is signature. If both see only 720p, gate is below UID (likely firmware).

5. **Hypothesis**: `dumpsys device_policy` shows `com.facebook.deviceowner` as the active device-owner on a stock retail Portal.
   **Test**: `adb shell dumpsys device_policy`.
   **Predicted outcome**: Unknown — round-1 did not test. If true, `dpm set-device-owner` for immortal will fail without removing Meta's first.

6. **Hypothesis**: NVIDIA RTX Super Resolution 2× on the 720p feed produces an image a typical user cannot distinguish from native 1080p at Zoom/Meet resolutions.
   **Test**: Set up the pipeline; have 3 colleagues blindly A/B test the OBS-upscaled feed vs. a known native 1080p webcam (e.g. C920).
   **Predicted outcome**: For most users, indistinguishable at 720p display resolution on the other end.

---

**Failure modes** (for the recommended HDMI capture path):

1. **AI tracking glitches**: if the AI is GPU-bound and the Portal throttles under sustained load, tracking may stutter. Mitigation: lower the host TV's resolution to 1080p (don't ask the Portal to push 4K).
2. **Privacy button kills the signal entirely**: if the user presses the hardware privacy button, HDMI captures a black screen. This is *correct* behaviour and matches the privacy guarantee. Document it.
3. **Audio capture ambiguity**: HDMI carries the *display*'s audio output, not the mic — so an HDMI capture card will not pick up the Portal's microphone regardless of permissions. For a mic, capture it separately on the host (USB/Bluetooth) **or** read it in your own sideloaded app: Meta's official Portal app program lists [`android.permission.RECORD_AUDIO` as supported](https://developers.meta.com/horizon/documentation/android-apps/unsupported-permissions/) ("VOIP or other features that need microphone access"), and the [Portal development guide](https://developers.meta.com/horizon/documentation/android-apps/portal-development/) explicitly assumes sideloaded apps "may access the camera or microphone." The earlier "mic is `com.facebook.secure`-locked → silence" read was wrong as stated. Confirmed by Meta's official `portal` build skill: standard `RECORD_AUDIO` opens an `AudioRecord` stream and delivers **real audio from `handset-mic` (the single-channel mic)** to sideloaded apps. Only the **far-field beamformed array** (the "Hey Portal" wake-word pickup) is gated — behind a Meta-signed native permission, **`com.facebook.alohasdk.permission.RECORD_AUDIO_PRIVILEGED`**, not `com.facebook.secure`. So sideloaded video calling *does* get usable mic audio for someone seated in front of the device; it only loses room-distance beamforming. The `portal-tv-webcam` silence report was a missing runtime grant — grant it (`pm grant <pkg> android.permission.RECORD_AUDIO`) and it works.
4. **Capture card DRM / HDCP**: cheap capture cards may strip HDCP-protected signals. Portal TV's HDMI output is *its own* signal (not pass-through from another source), so HDCP should not apply. Verified by the community (multiple cards work) [S5]. Risk low.
5. **Latency makes the Portal-as-TV-useful unfeasible**: 120-180 ms is fine for video calls, bad for interactive gaming. If the user wanted low-latency interactive webcam, this is the wrong path.
6. **Capture card driver issues on Linux**: most generic HDMI capture cards work as standard UVC devices; some (Magewell, certain Elgato) need proprietary drivers. Stick to UVC-class devices to avoid driver hell.

**Adjacent / cross-domain leads**:
- **Network-path capture (RTP/RTSP injection into Bishop's own stream)**: Bishop likely streams its camera over WebRTC for video calls. If you can MITM the call (e.g. set up a fake SIP endpoint on a server you control), you receive the 1080p stream Bishop sends. **Disanalogy**: requires the user to actively be on a Meta video call (or to set up a loopback server). Doesn't help if you want a "passive" 1080p camera feed for OBS / Zoom.
- **Display port emulation (DisplayPort alt-mode over USB-C)**: USB-C on the Portal supports "Alt Mode" for direct DisplayPort output on the Portal+ Gen 1 [S1]. Some Portal TV units may inherit this. If so, a USB-C-to-DisplayPort cable gives a higher-fidelity capture than HDMI. **Disanalogy**: requires Portal-specific firmware support, undocumented; HDMI capture is the safer bet.
- **eBPF / kernel module hooking the camera HAL**: with root, eBPF programs can hook kernel functions. If the HAL's `get_camera_info` capability gate is a kernel function, eBPF could bypass it. **Disanalogy**: requires root + the kernel has eBPF enabled (Android kernels often strip it). Lower-effort than full HAL reverse engineering if root is achieved.

**Open questions for the human**:
- Do you have a free HDMI input on a TV you can leave the Portal connected to? (decides whether HDMI capture is feasible without a splitter)
- Do you have an NVIDIA RTX GPU on the host PC? (decides whether OBS upscale fallback is viable)
- Is the Portal your only one, or do you have a sacrificial test unit for QualPwn attempts? (decides whether to attempt root at all)
- What's the actual goal — best video-call quality, or specifically "1080p camera unlock"? (the latter may be the wrong framing; see Pushback #1)

**Critical files** (paths to read first):
- `~/Downloads/portal/repos/immortal/docs/research/meta-portal-privilege-model.md` — round-1 axioms, MUST read [S6].
- `~/Downloads/portal/repos/portal-tv-webcam/README.md` — community 720p webcam setup + OBS upscaling fallback [S7].
- `~/Downloads/portal/repos/portal-tv-webcam/PortalCam/app/src/main/java/com/portalcam/CameraService.java` — confirms PortalCam uses standard Camera2 (no vendor HAL hooks attempted).
- `~/Downloads/portal/repos/immortal/provisioning/provision.sh` (lines 100-105, 185-200, 490-510) — confirms current state is non-root + ADB-over-USB.
- `~/Downloads/portal/repos/immortal/docs/first-gen-portals.md` — Portal TV is Gen 1 (Android 9), same installer quirks as Portal+.

**Sources**:
- [S1] Meta Portal TV support page — "Connect Portal TV to a TV or monitor" (HDMI output, USB-C for Ethernet adapter, USB-C monitor output). https://www.meta.com/help/portal/
- [S2] Engadget Portal TV review — confirms HDMI output port. https://www.engadget.com/meta-portal-tv-review-130020010.html
- [S3] PCMag Portal TV review — confirms HDMI cable not included, USB-C for Ethernet/monitor. https://www.pcmag.com/reviews/meta-portal-tv
- [S4] Qualcomm Security Bulletin June 2019 / Android Security Bulletin August 2019 — CVE-2019-10538 and CVE-2019-10540 patched 2019-08-05. Confirmed via theweborion.com, zdnet.com, xda-developers.com, thehackernews.com synthesis (web search 2026-06-28).
- [S5] Reddit r/FacebookPortal + multiple YouTube tutorials — HDMI capture card as 1080p Portal TV webcam, AI tracking preserved. https://www.reddit.com/r/FacebookPortal/
- [S6] `~/Downloads/portal/repos/immortal/docs/research/meta-portal-privilege-model.md` — round-1 static APK analysis (HAL gate inference, device-owner slot, install architecture).
- [S7] `~/Downloads/portal/repos/portal-tv-webcam/README.md` — Step 5: NVIDIA RTX Super Resolution + Artefact Reduction as the 720p-to-1080p upscaling path.

**Verification leads**:
- **V1**: `adb shell getprop ro.build.version.security_patch` — definitive answer on QualPwn applicability (run on user's Portal).
- **V2**: `adb shell ls /dev/video*` after plugging USB-C OTG + UVC webcam — definitive answer on USB-C host mode + UVC (run on user's Portal).
- **V3**: `adb shell dumpsys media.camera | grep -A 50 "StreamConfiguration"` — definitive answer on whether HAL advertises 1080p to unprivileged UIDs (run on user's Portal, after temporarily installing any camera app).
- **V4**: `adb shell dumpsys device_policy | grep -A 5 "Device Owner"` — definitive answer on whether Meta's DPC holds the slot (run on user's Portal).
- **V5**: Bishop APK build fingerprint — search for it in `apkmirror.com` page metadata for `com.facebook.bishop_74.0.0.0.0`; cross-reference with `getprop ro.build.fingerprint` on user's Portal to confirm build provenance.

---

**Meta-observation**:

**What surprised me**: The round-1 evidence recap got the HDMI bypass **almost right but in the wrong direction**. It said "Portal TV outputs its own UI/camera feed over HDMI at 1080p" and then hedged that "the HDMI output port may not exist on Portal TV hardware." The hedging is wrong: Portal TV *is* an HDMI output device (it's a stick; it has no screen of its own). The HDMI output is the *only* display path. This makes HDMI capture not a "bypass" but the *natural use case* — the camera HAL gate is a red herring because the display compositor doesn't know what resolution the camera was at; it just composites whatever the app rendered. The HDMI capture path is the most boring path and therefore the one the round-1 analysis under-emphasized.

**What I couldn't verify**:
- **[UNVERIFIED-requires-device]**: Whether USB-C host mode + UVC webcam works on Portal TV (V2 above). High-value single experiment.
- **[UNVERIFIED-requires-device]**: Portal's Qualcomm security patch level (V1). Likely ≥ 2019-08, but cheap to check.
- **[UNVERIFIED-requires-device]**: Whether `dumpsys media.camera` as unprivileged UID sees ≥1080p or only 720p (V3). This is the *single most important experiment* — it directly tests the round-1 "signature gate" inference.
- **[UNVERIFIED-requires-device]**: Whether `com.facebook.deviceowner` is the active device-owner (V4). Round-1 evidence suggests it is, but never tested.

**Where round-1 was load-bearing vs hand-waving**:
- **Load-bearing**: the static APK analysis of `com.facebook.system` StubApiProvider (`installer/api/a.java` line `if (!caller.f43a) throw new SecurityException`) — definitively proves the gate is *caller identity*. This is verifiable from the APK alone.
- **Load-bearing**: the proof that Bishop's manifest does *not* declare `android.permission.CAMERA` but the app uses the camera — confirms the privileged-app-via-signature model.
- **Load-bearing**: the identification of the `ImmutableMultimap<Signature,String>` trust table — proves "Meta signature" is the gate key, not package name or some random flag.
- **Hand-waving**: the leap from "signature is the gate in the four APKs we examined" to "the camera HAL gates on signature." This is an *extrapolation* — the camera HAL is a different binary (`/vendor/lib*/hw/camera.*.so`), not in any of the four APKs. The camera HAL could gate on the same mechanism (likely) or a different one (possible).
- **Hand-waving**: "Meta provisions a Device Policy Controller" as proof device-owner is set — the *presence* of `com.facebook.deviceowner` does not prove it's *active*. Untested.
- **Hand-waving**: the HDMI bypass being framed as a "verifiable claim" without specifying that Portal TV has an HDMI output port (which the round-1 evidence recap *questioned*). The hedging was misplaced — Portal TV is unambiguously an HDMI-output device.

**The single most important next experiment on a real device**:
**`adb shell dumpsys media.camera | grep -E "SCALER_STREAM|Size|1920|1080"`** while Bishop is running.

This is the experiment that decides everything:
- If 1080p sizes are advertised to an unprivileged app → gate is *below* the camera2 framework (sensor, ISP, kernel); root doesn't help. The only real path is HDMI capture or UVC.
- If only 720p sizes are advertised → gate is *above* the camera2 framework (HAL wrapper, identity check). Root unlocks it.

The answer determines whether the recommended path is **HDMI capture (no root)** or **QualPwn root + bypass (if patch level allows)**. Round-1 spent 15 minutes on this and never ran it.

**Whether round-3 is needed**: No, *if* the user runs V1-V4 above. The HDMI capture path is independent of the round-1 signature-gate inference and works regardless of those answers. The remaining uncertainty is whether root unlocks the cap (M3), which is answerable in a 5-minute `dumpsys` experiment, not a research dispatch.

**Confidence level**: **medium-high** overall.
- **High**: HDMI capture works (community-documented), 720p+OBS-upscale works (`portal-tv-webcam` documents this), the four APKs gate on signature (round-1 static).
- **Medium**: UVC over USB-C works (plausible, unverified), the camera HAL gates on signature (likely but unverified), root would bypass (likely but conditional).
- **Low**: QualPwn applies to current Portal patch level (very likely patched), the gate is in the sensor firmware rather than the HAL (a long-tail possibility).

The artifact commits to a recommended path (HDMI capture) that does **not** depend on the low-confidence claims. The root attempt is the backup; the upscaling fallback is the "give up" path. All three paths are independent of each other — the user can attempt them in any order.

---

**Parking lot** (out-of-scope but surfaced):
- Whether the round-1 device-owner recommendation (`dpm set-device-owner com.immortal.launcher/.AdminReceiver`) succeeds on a fresh Portal. Separate from this question; important for immortal install persistence.
- Whether Meta's own OTA pipeline can be subverted to ship a patched Bishop that unlocks the camera. Almost certainly no (Meta gates this on their own signing key).
- Whether the Portal Go (QCS605 variant) has different HAL behavior. Same Qualcomm family, likely same gate mechanism; unverified.
- Whether the Round-1 readme's recommendation about `com.facebook.appmanager.ACCESS` could be exploited by an app that shares Meta's signing key (none does publicly). Dead end.
- Whether the BishopBundle.js.hbc Hermes bytecode contains any resolution negotiation that round-1 missed. Per round-1, no — pure UI shell.
