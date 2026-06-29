# Research

Two rounds of static analysis on the Meta Portal's privilege and camera-access model.
Both rounds persist as decision-complete artifacts; the kit's user-facing guide
([`keeping-portal-alive.md`](../keeping-portal-alive.md)) is the thin layer on top.

## Round 1 — Meta Portal system-APK privilege model

[`immortal - docs/research/meta-portal-privilege-model.md`](https://github.com/starbrightlab/immortal/blob/main/docs/research/meta-portal-privilege-model.md)

**What it answered:** that the 720p camera cap on Portal TV is enforced **below the
app, in the camera HAL / firmware, keyed on caller identity** (system UID / platform
signature); that every privileged Meta capability (HQ camera, mic, config providers,
silent installer) sits behind `com.facebook.secure` signature trust; and that Android
Device Owner is the one wall that is *not* Meta-exclusive — meaning
`dpm set-device-owner com.immortal.launcher/.AdminReceiver` is a reachable,
persistent, root-free install privilege for any app willing to claim the slot.

**What it didn't:** round 1 was pure static APK analysis. It proved the gate is on
caller identity *in the four APKs it decompiled*, but did not test whether the
camera HAL's specific capability list would still be 720p-capped to an unprivileged
caller on a real device. That question — and the question of whether the device-owner
slot is in fact claimable on a retail Portal — is round 2's territory.

## Round 2 — Actual feasible paths to >720p camera access

[`portal-1080p-camera-paths.md`](portal-1080p-camera-paths.md)

**What it answered:** that the **HDMI capture card** path bypasses the camera HAL
entirely (the Portal's own display compositor renders the camera feed at 1080p into
the HDMI signal — the HAL gate is irrelevant), and that this is the recommended path
over the long-shot QualPwn root path or the "give up" OBS upscale fallback. Round 2
also surfaced the **USB-C UVC external webcam** backup path, which depends on whether
Portal firmware permits USB host mode for UVC class devices (V2 verdict, runnable
in under a minute via the probe).

**What it didn't:** round 2 is still a research artifact, not a code path. The kit's
probe ([`scripts/portal-probe.sh`](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/scripts/portal-probe.sh))
runs the four `dumpsys`/`getprop` verification leads on a real Portal and prints what
is and isn't feasible on that device. The probe is round 2 made runnable.

## Verification leads V1-V4

Each lead takes seconds to run and prints one verdict. The kit's probe runs all four
in order.

| Lead | Question | Where it lives |
|------|----------|----------------|
| **V1** | What is `ro.build.version.security_patch`? Determines whether QualPwn (the only known MSM8998 root path, CVE-2019-10538/10540) is *theoretically* applicable. | Round 2, "Testable hypotheses" H2 |
| **V2** | Does a UVC webcam over USB-C enumerate? Determines whether the backup path is feasible on this device's firmware. | Round 2, H1 |
| **V3** | Does `dumpsys media.camera` advertise ≥1080p sizes to an unprivileged caller (gate is *below* the camera2 framework → root won't help), or only 720p (gate is *above* → root unlocks it)? The single most important experiment — round 2's "what round-1 should have run." | Round 2, H4 |
| **V4** | Is `com.facebook.deviceowner` already the active device-owner? If yes, the kit cannot claim the slot for immortal without factory-resetting first. | Round 2, H5 |

V5 (build-fingerprint cross-check) is also in round 2 but is documentation-only and
not run by the probe.
