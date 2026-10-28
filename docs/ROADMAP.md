# porchcam → installable product — roadmap

**Goal:** turn the current script + systemd stack into an installable package
(`apt-get install porchcam`) with a **config UI** and an **optional AI-assisted
setup**, so a non-expert can deploy "USB/IP cameras → NVR + desktop overlays +
virtual webcam" on any Ubuntu/Debian host. Manual config stays fully supported;
the UI and AI are conveniences layered on top.

Status: **planning** (drafted 2026-10-27). Nothing below is built yet.

---

## Baseline (what exists today)
- `install.sh` + systemd units + `/etc/porchcam/*.env` — already idempotent.
- Components: mediamtx (RTSP), VAAPI capture scripts, GTK overlays (now with the
  live Adjust panel), `v4l2loopback` virtual cam, corruption monitor, restic backup.
- Config = hand-edited flat `.env` files. **This is the thing the UI/AI replace.**

---

## Phase 0 — Config schema (foundation for everything else)
Move from scattered `.env` files to **one declarative config** the capture
scripts, the UI, and the AI all read/write:
- `/etc/porchcam/porchcam.yaml` — a list of cameras (source URL/device, encode
  settings, mediamtx path, substream, overlay on/off) + global options.
- A small loader shim so existing scripts keep working (`.env` generated from, or
  superseded by, the YAML). Backwards-compatible migration on upgrade.
- Secrets (camera passwords) stay in a `0640 root:porchcam` file, referenced by
  the YAML, never inlined — keeps them out of backups-in-the-clear and AI prompts.

## Phase 1 — Debian packaging (`apt-get`)

**Status: in progress.** A working `.deb` builds from `packaging/` with `nfpm`
(`packaging/build-deb.sh`): all binaries, systemd units, `/etc/porchcam`
conffiles, the mediamtx template, desktop files, docs and a changelog, with
`postinst`/`prerm`/`postrm` ported from `install.sh`/`uninstall.sh` (create
service users, fetch mediamtx, render `mediamtx.yml`, enable units) and the
right dependency list. Built and verified by inspection (not installed on the
dev host — it would collide with the `install.sh` deployment; real install-test
belongs on a clean VM). Follow-ups: **(1)** move binaries from `/usr/local/bin`
to `/usr/bin` with path-agnostic sibling lookup (removes the only lintian
errors) — a coordinated change across scripts + units + `install.sh`; **(2)**
install-test on a clean Ubuntu VM; **(3)** publish a Launchpad PPA.

Options:
- **(a) `nfpm`** — build a `.deb` (and `.rpm`) from the existing file layout with a
  short YAML spec. No debhelper learning curve. **Recommended first step.**
- (b) Full `debhelper`/`dh` source package → upload to a **Launchpad PPA** so users
  `add-apt-repository ppa:…` and `apt-get install porchcam`. Best end-state for
  real `apt-get` distribution; more upfront work.
- (c) snap/flatpak — rejected: needs host V4L2/GPU/X and kernel modules, which
  sandboxes fight.

Package shape: binaries → `/usr/bin`, systemd units, `/etc/porchcam` defaults as
**conffiles** (dpkg won't clobber local edits), modprobe/modules-load drops.
`postinst` creates the service users, loads `v4l2loopback`, enables units;
`prerm/postrm` mirror `uninstall.sh`. Depends: `ffmpeg gstreamer1.0-* v4l-utils
python3-gi`; mediamtx vendored or fetched in `postinst`.
Plan: **(a) now, (b) once stable.**

## Phase 2 — Config UI
Options: GTK desktop app · **local web UI** · TUI.
- **Recommended: a local web UI** (`FastAPI` + a small SPA) bound to
  `127.0.0.1`, shipped as a `porchcam-config` service. Reasons: live camera
  discovery + snapshot preview, multi-step "add camera" wizard, works headless /
  over SSH tunnel, and it's the natural home for the AI chat (Phase 4).
- Features: list/add/remove cameras; **LAN scan + auto-detect** (ONVIF / Dahua
  `37777` fingerprint, as done by hand this session); **test a stream** (`ffprobe`)
  and show a snapshot before saving; edit RTSP path/credentials; map to a mediamtx
  path + optional substream; toggle overlay / virtual cam; enable the self-healing
  units; write config + restart services with one click.

## Phase 3 — Better documentation
- `man` pages: `porchcam(1)`, `porchcam.yaml(5)`.
- A docs site (mkdocs-material): quickstart, architecture diagram, and a
  troubleshooting section seeded from this project's hard-won findings (VAAPI
  grey/pink fix, Amcrest/Dahua RTSP paths, the BI reverse-proxy and the
  wrong-`ippath` reset, the rapid-login IP ban).

## Phase 4 — AI-assisted configuration (opt-in)
Productize exactly the workflow used to add the Amcrest this session.
- A "**Set it up for me**" mode in the config UI: the user describes their cameras
  in plain language; the assistant **scans the LAN, fingerprints cameras, asks
  clarifying questions** ("which one is the front door?"), builds the RTSP URLs,
  writes the config, and **validates with `ffprobe`** before committing.
- Architecture: the config backend runs a **Claude tool-use loop** (default to the
  latest Claude model) exposing *safe, local* tools — `scan_lan`, `probe_rtsp`,
  `snapshot`, `propose_config`, `write_config`, `restart_service`.
- Guardrails: **dry-run + explicit user confirmation before any write**; camera
  credentials redacted from prompts; the Anthropic API key is user-supplied in
  `/etc/porchcam/ai.env` and never packaged. Clearly optional and cost-aware.

---

## Cross-cutting decisions (need input)
1. **Project name** — "porchcam" is historical. A product name (e.g. *camstack*)
   may fit a distributable package. Affects package name, paths, service names.
2. **License** — the public repo currently has none; a license is required before
   distributing a package. (MIT / Apache-2.0 / GPL-3.0?)
3. **Distro targets** — Ubuntu 24.04 only, or broader Debian/derivatives?
4. **mediamtx** — vendor the binary in the package, or depend on / fetch it?

## Suggested build order
Phase 0 (schema) → Phase 1a (`nfpm` .deb) → Phase 2 (web UI CRUD + stream test) →
Phase 4 (AI mode in the UI) → Phase 3 (docs site) → Phase 1b (PPA).
