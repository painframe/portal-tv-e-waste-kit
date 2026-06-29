# Portal TV e-waste kit

A standalone, host-side toolkit that keeps a Meta Portal TV useful after Meta
end-of-lifed the platform. Companion to the
[`immortal`](https://github.com/starbrightlab/immortal) home-screen project and the
[`portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam) USB-tunnel webcam
project — same author, same host.

## Scope

The kit gives you two things:

1. **A higher-quality webcam feed** from a Portal TV, via one of three ranked paths.
2. **A probe script** that tells you which paths are feasible on *your specific Portal*,
   based on its actual on-device state.

It does **not** give you root, bootloader unlock, or unmodified access to the internal
camera at >720p. Those are firmware facts, not bugs.

## The three paths, ranked

| Rank | Path | Effort | Brick risk | True 1080p | AI tracking | Hardware cost |
|------|------|--------|------------|------------|-------------|---------------|
| **1 (recommended)** | HDMI capture card on the host | 1-2 hr | None | Yes | Preserved | ~£15 |
| 2 (backup) | USB-C UVC external webcam | 1-2 hr | None | Yes | Lost | ~£25-45 |
| 3 (fallback) | OBS RTX Super Resolution 2x upscale of the existing 720p feed | 15-30 min | None | Algorithmic | Lost | Free if you already have an RTX |

Full reasoning, evidence, and verification leads in
[`docs/research/portal-1080p-camera-paths.md`](docs/research/portal-1080p-camera-paths.md).

## Quick start

```bash
# 1. Connect your Portal over USB-C with Settings > Debug > ADB Enabled.
# 2. Run the probe (it tells you which path applies):
./scripts/portal-probe.sh
# 3. Pick the path whose status block the probe prints:
./scripts/portal-hdmi-capture.sh     # recommended path 1
./scripts/portal-uvc-external.sh      # backup path 2
./scripts/portal-obs-upscale.sh       # fallback path 3 (extends portal-tv-webcam)
```

For Windows, swap the `.sh` for `.ps1` (the two scripts are intentionally separate, not a
shared abstraction).

For the full walkthrough see [`docs/keeping-portal-alive.md`](docs/keeping-portal-alive.md).

## The probe at a glance

The probe runs four verification leads and prints a four-verdict report plus a path-status
block:

| Lead | Tells you |
|------|-----------|
| **V1** | `ro.build.version.security_patch` — is QualPwn (the only known MSM8998 root path) still applicable? |
| **V2** | `/dev/video*` after a USB-C OTG + UVC webcam — does the Portal's firmware permit USB host mode + UVC class drivers? |
| **V3** | `dumpsys media.camera` — does the camera HAL advertise ≥1080p to unprivileged callers, or only 720p? (Round-1's pivotal question, finally answered on-device.) |
| **V4** | `dumpsys device_policy` — is the Android Device Owner slot free, held by Meta, or held by something else? |

It also (optionally, behind `--claim-device-owner`) attempts to claim the slot for
`com.immortal.launcher/.AdminReceiver`, persisting the silent-install privilege across
reboots without root. Both `--claim-device-owner` and `--dry-run-claim` must be set; the
defaults are off.

## Layout

```
docs/keeping-portal-alive.md     the user-facing guide (start here)
docs/research/                   two persisted research artifacts (round 1 + round 2)
scripts/                         portal-probe.{sh,ps1} and three path helpers
mkdocs.yml                       docs site config (Material theme)
LICENSE / DISCLAIMER.md          MIT, identical to immortal
AGENTS.md                        agent guidance (build / validate / hard rules)
```

## Related projects

- [`starbrightlab/immortal`](https://github.com/starbrightlab/immortal) — the home-screen
  layer this kit claims Device Owner for (if you want reboot-surviving silent install).
- [`starbrightlab/portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam) —
  the 720p webcam setup the OBS-upscale fallback extends.

## License

[MIT](LICENSE). This project is not affiliated with or endorsed by Meta. See
[`DISCLAIMER.md`](DISCLAIMER.md) for the full scope and use-at-your-own-risk text.
