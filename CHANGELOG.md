# Changelog

## 0.1.0 (2026-06-29)

Initial release. Host-side toolkit for keeping a Meta Portal TV useful after
end-of-life, scoped to "ranked paths to a higher-quality webcam feed" with the
evidence and probe to back the ranking.

- **Decision-complete guide.** `docs/keeping-portal-alive.md` walks a user
  through the three ranked paths to a >720p webcam feed, with cross-references
  to the round-2 artifact for every claim.
- **Probe script (`portal-probe.{sh,ps1}`).** Four-verdict probe
  (`dumpsys media.camera` / `getprop` / `dumpsys device_policy`) that reports
  which paths are feasible on the connected device. Optional
  `dpm set-device-owner` claim for the immortal `AdminReceiver`, with
  `--dry-run-claim --claim-device-owner` for a no-device preview.
- **Three helper scripts.** `portal-hdmi-capture` (Path 1), `portal-uvc-external`
  (Path 2), `portal-obs-upscale` (Path 3, plus `portal-obs-upscale-apply.py`).
  All ship as bash + PowerShell pairs.
- **Round-2 artifact.** `docs/research/portal-1080p-camera-paths.md` is the
  load-bearing reference for every path decision; the body is byte-stable and
  CI checks the canonical markers (`[S6]`, `Decision table`,
  `## How to use this`).
- **MkDocs site.** Material-themed docs site built with `mkdocs build --strict`
  and deployed to GitHub Pages on every push to `main`.
- **CI workflow.** Bash lint, PowerShell parse-check, ASCII-guard, MkDocs
  strict build, and round-2 marker check on every push.
- **Cross-links.** Sibling repos
  ([starbrightlab/immortal](https://github.com/starbrightlab/immortal) and
  [starbrightlab/portal-tv-webcam](https://github.com/starbrightlab/portal-tv-webcam))
  link into the kit for the `AdminReceiver` target and the OBS-upscale
  fallback.
