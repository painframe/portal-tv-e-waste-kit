# Portal TV e-waste kit

A standalone, host-side toolkit that keeps a Meta Portal TV useful after Meta
end-of-lifed the platform. Companion to the
[`immortal`](https://github.com/starbrightlab/immortal) home-screen project and the
[`portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam) USB-tunnel webcam
project - same author, same host.

## Start here

- **[Guide: keeping-portal-alive.md](keeping-portal-alive.md)** - the user-facing
  walkthrough (decision-complete end-to-end). Read this first.
- **[Research: portal-1080p-camera-paths.md](research/portal-1080p-camera-paths.md)** -
  the round-2 evidence base. Load-bearing; every decision in the guide traces back
  here.
- **Scripts** under [`scripts/`](https://github.com/painframe/portal-tv-e-waste-kit/tree/main/scripts) -
  the probe and three path helpers.

## What this kit gives you

1. **A higher-quality webcam feed** from a Portal TV, via one of three ranked paths.
2. **A probe script** that tells you which paths are feasible on *your specific Portal*,
   based on its actual on-device state.

It does **not** give you root, bootloader unlock, or unmodified access to the
internal camera at >720p. Those are firmware facts, not bugs.

## Cross-repo links

- [`starbrightlab/immortal`](https://github.com/starbrightlab/immortal) - the home
  screen the kit claims Device Owner for.
- [`starbrightlab/portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam) -
  the 720p webcam setup the OBS-upscale fallback extends.

## Disclaimer

`portal-tv-e-waste-kit` is an independent community project, **not affiliated with
or endorsed by Meta**. See
[DISCLAIMER.md](https://github.com/painframe/portal-tv-e-waste-kit/blob/main/DISCLAIMER.md)
(in the repo root) for the full scope and use-at-your-own-risk text.
