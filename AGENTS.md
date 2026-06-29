# AGENTS.md

Guidance for AI coding agents working in the **portal-tv-e-waste-kit** repository.
Tool-specific files (e.g. `CLAUDE.md`) just point here. Human contributors should read
[`CONTRIBUTING.md`](CONTRIBUTING.md) (sibling project convention) — this file is a superset
aimed at agents.

## What this project is

`portal-tv-e-waste-kit` is a standalone, host-side toolkit that keeps a Meta Portal TV useful
after Meta end-of-lifed the platform. It is **docs + bash + PowerShell + Python** — there is
**no Android app in this repo**. The kit ships:

- A decision-complete guide ([`docs/keeping-portal-alive.md`](docs/keeping-portal-alive.md))
  that walks a user through the three ranked paths to a >720p webcam feed.
- A probe script ([`scripts/portal-probe.{sh,ps1}`](scripts/portal-probe.sh)) that runs four
  `dumpsys`/`getprop` verification leads on a real Portal TV and reports what is and isn't
  feasible on that device.
- Three small helper scripts for the HDMI capture, USB-C UVC, and OBS-upscale paths.
- Two persisted research artifacts from prior dispatches:
  [`docs/research/meta-portal-privilege-model.md` (round 1)](docs/research/meta-portal-privilege-model.md)
  and [`docs/research/portal-1080p-camera-paths.md` (round 2)](docs/research/portal-1080p-camera-paths.md).
  The round-2 artifact is **load-bearing reference** — every path choice in the top-level
  guide traces back to it.

See [`README.md`](README.md) for the user-facing tour.

## Build, test, and validate

This repo has no Android app and no compiled code. Always run the relevant check below after a
change and fix failures before finishing.

| Task | Command |
|------|---------|
| Verify the round-2 body matches the source-of-truth local handle (header-prefixed file is OK) | `python3 -c "import sys,urllib.request; src=urllib.request.urlopen('local://portal-1080p-unlock-r2.md').read().decode(); dst=open('docs/research/portal-1080p-camera-paths.md').read(); sys.exit(0 if src in dst else 1)"` (exit 0 = source body is present verbatim) |
| Lint every bash script | `bash -n scripts/portal-probe.sh && bash -n scripts/portal-hdmi-capture.sh && bash -n scripts/portal-uvc-external.sh && bash -n scripts/portal-obs-upscale.sh` |
| ASCII-guard every PowerShell script (Windows PowerShell 5.1 mis-decodes non-ASCII; CI enforces this) | `file -E scripts/*.ps1` (must report `ASCII text`); `python3 -c "import sys,pathlib; [sys.exit(1) for p in pathlib.Path('scripts').glob('*.ps1') if not p.read_bytes().isascii()]" ` |
| Mark every `.ps1` (literal three-byte sequence at the top) to keep Windows PowerShell happy | already present in shipped scripts; if you add a new `.ps1`, copy the header from `scripts/portal-probe.ps1` |
| Build the docs site (CI gate) | `pip install -r requirements-docs.txt && mkdocs build --strict` |
| Check internal links | `markdown-link-check docs/keeping-portal-alive.md docs/research/*.md` |
| Exercise the probe with no device attached (must exit non-zero cleanly) | `./scripts/portal-probe.sh` (exits 1 with the "no Portal found" message) |
| Exercise the probe in dry-run claim mode | `./scripts/portal-probe.sh --dry-run-claim --claim-device-owner` (prints the would-be `dpm` command without running it) |

CI workflows live in [`.github/workflows/`](.github/workflows/): `docs.yml` runs the lint +
MkDocs build + link checks on every push to `main`.

The round-2 artifact `docs/research/portal-1080p-camera-paths.md` is the **single sourced
fact** for every path decision in the user guide. Do not rewrite it — see "Conventions and
hard rules" below.

## Repository layout

```
docs/
  keeping-portal-alive.md      the single user-facing guide (entry point)
  research/
    index.md                   cross-reference of round 1 + round 2 + V1-V4 leads
    meta-portal-privilege-model.md    round 1 (verbatim mirror of immortal's research)
    portal-1080p-camera-paths.md      round 2 (load-bearing reference, byte-identical to local://)
scripts/
  portal-probe.{sh,ps1}        the four-verdict probe + auto-claim
  portal-hdmi-capture.{sh,ps1} M1 helper: prove the host sees the HDMI capture
  portal-uvc-external.{sh,ps1}  M2 helper: prove the Portal sees a UVC webcam
  portal-obs-upscale.{sh,ps1}  OBS + RTX Super Resolution 2x upscale helper
provisioning/                  (intentionally empty — see AGENTS.md note below)
.github/workflows/docs.yml     lint + MkDocs strict build
mkdocs.yml                     docs site config (Material theme, matches immortal)
LICENSE / DISCLAIMER.md        MIT, identical to immortal
README.md                      user-facing tour
AGENTS.md                      this file
requirements-docs.txt          pip install -r for MkDocs strict build
```

The `provisioning/` directory is intentionally present but empty. The kit does not ship a
device-side provisioner — install `com.immortal.launcher` from the
[`immortal`](https://github.com/starbrightlab/immortal) project if needed. The
`--claim-device-owner` flag in `portal-probe.sh` requires the immortal AdminReceiver to be
present on the device; the probe fails cleanly with an instructional message if it isn't.

## Conventions and hard rules

- **Match the existing style.** Keep changes focused; prefer editing over rewrites. The
  styles to match are documented per file family:
  - **Bash** (`*.sh`): colour-prefix output pattern from `immortal/provisioning/provision.sh`
    lines 29-34. `set -u` but NOT `set -e` (probes intentionally continue past failures).
  - **PowerShell** (`*.ps1`): ASCII-only, `Write-Host -ForegroundColor` pattern from
    `portal-tv-webcam/scripts/start-portal-cam.ps1`. Em-dash `—` is forbidden — use `-`.
  - **Markdown**: header-link MkDocs-friendly anchor pattern. Section IDs are explicit
    (`{#hdmi}`, `{#uvc}`, ...) so `keeping-portal-alive.md#path-N` links resolve.
- **Copyright headers:** new files use exactly:
  ```
  #!/usr/bin/env bash
  #
  # Copyright (c) 2026 Starbright Lab.
  # Licensed under the MIT license found in the LICENSE file in the repo root.
  #
  ```
  `portal-tv-e-waste-kit` is **not affiliated with Meta** (see `DISCLAIMER.md`). If you copy
  an existing file as a starting point, fix the header to the one above.
- **Windows-executed scripts must be pure ASCII** (`*.ps1`, `*.bat`) — Windows PowerShell
  5.1 mis-decodes non-ASCII bytes and breaks parsing. CI enforces this. Use `-` instead of
  `—`. Bash scripts (`*.sh`) are exempt (macOS/Linux, UTF-8).
- **`set -u`, not `set -e`.** The probe script deliberately runs every verification lead
  even if earlier ones fail; `set -e` would abort the report on the first failure and leave
  the user with less information, not more.
- **Never write to `/system`, never modify the bootloader, never touch `devinfo`.** The
  probe's only write is `dpm set-device-owner`, which is gated by BOTH the `--claim-device-owner`
  flag AND the slot-free check from V4. If either gate fails, the probe refuses.
- **The round-2 artifact body is byte-stable.**
  `docs/research/portal-1080p-camera-paths.md` contains the original `local://portal-1080p-unlock-r2.md`
  body verbatim. A header + a short "How to use this" section above the body is expected and allowed,
  which the verification above (`python3 -c "import sys,urllib.request; ..."`) confirms.
  If you find an inaccuracy in the artifact body, that's a separate research-dispatch task,
  not an in-place edit.
- **The kit does not ship an Android app.** It is purely host-side scripts + docs. If a
  future improvement wants an on-device companion (e.g. for the UVC path), that is a
  follow-up repo, not in scope here.
- **No telemetry.** The probe prints device-state to stdout only; nothing is uploaded.

## Trademark / scope

`portal-tv-e-waste-kit` is an independent community project, **not affiliated with or
endorsed by Meta**. See [`DISCLAIMER.md`](DISCLAIMER.md).

The kit builds on two sibling repos under the same Starbright Lab umbrella:
[`starbrightlab/immortal`](https://github.com/starbrightlab/immortal) (the home-screen layer
this project leans on for the `AdminReceiver` target) and
[`starbrightlab/portal-tv-webcam`](https://github.com/starbrightlab/portal-tv-webcam) (the
720p webcam setup the OBS-upscale fallback extends). Read those projects' own
`DISCLAIMER.md` files before borrowing any code or copy.
