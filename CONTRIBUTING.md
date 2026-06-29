<!--
  Copyright (c) 2026 Starbright Lab.
  Licensed under the MIT license found in the LICENSE file in the repo root.
-->
# Contributing to portal-tv-e-waste-kit

Thanks for helping keep Meta Portal TV hardware useful after end-of-life. Contributions
of all kinds are welcome — bug reports, script improvements, docs, additional
verification leads, and testing on Portal TV hardware we haven't confirmed yet.

By participating you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md).

## Ways to contribute

- **Report a bug** — open an
  [issue](https://github.com/painframe/portal-tv-e-waste-kit/issues). Tell us
  your Portal TV model and the `dumpsys media.camera` excerpt; it matters a lot
  when the camera HAL is the suspect.
- **Send a pull request** — see below.
- **Test on a Portal TV variant we haven't confirmed** — the kit is verified on
  the stock Portal TV (the small black one with the camera bar). If you've run it
  on a Jio/Movistar rebrand or a developer unit, an issue with the device's
  `getprop` dump is gold.

## Development

This repo is **docs + bash + PowerShell + Python**. There is no Android app in
this repo. The host-side tools are:

    bash -n scripts/portal-probe.sh        # bash lint
    pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content -Raw scripts/portal-probe.ps1))"  # PowerShell parse-check
    pip install -r requirements-docs.txt && mkdocs build --strict    # docs gate

Iterate against a real Portal TV by running the probe against a device in dev
mode (`adb shell getprop ro.build.type`). To dry-run the dpm claim without a
device, use `--dry-run-claim --claim-device-owner` (in either order) — the
script prints the would-be command and exits 0 without touching anything.

A few things worth knowing:

- **PowerShell scripts must be pure ASCII.** Windows PowerShell 5.1 mis-decodes
  non-ASCII bytes and breaks parsing. CI enforces this. Use `-` instead of `—`.
- **`set -u`, not `set -e`** in the bash scripts. The probe deliberately runs
  every verification lead even if earlier ones fail; `set -e` would abort the
  report on the first failure and leave the user with less information, not more.
- **The round-2 artifact body is byte-stable.** `docs/research/portal-1080p-camera-paths.md`
  contains the original `local://portal-1080p-unlock-r2.md` body verbatim. A
  header + a short "How to use this" section above the body is expected and
  allowed. If you find an inaccuracy in the artifact body, that's a separate
  research-dispatch task, not an in-place edit.

## Pull requests

1. Fork and create a branch from `main`.
2. Keep changes focused and match the existing style.
3. If you changed the probe logic, test it on a real Portal TV and say which
   model in the PR.
4. Open the PR with a clear description of what and why.

## License

By contributing, you agree that your contributions are licensed under the
[MIT License](LICENSE) that covers this project.

## Trademark

portal-tv-e-waste-kit is an independent project and is **not affiliated with,
endorsed by, or sponsored by Meta**. "Meta Portal" and "Portal" are trademarks
of Meta Platforms, Inc., used here only to identify compatible hardware. See
[DISCLAIMER.md](DISCLAIMER.md).
