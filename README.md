# porchcam — two USB cameras, Blue Iris, a desktop overlay, and video calls

Two USB webcams on one Ubuntu 24.04 / X11 workstation, each opened exactly
**once** and fanned out to everything that needs it.

```
 C920 (porch/driveway) ──native H.264, no encode──► porchcam-capture ─┐
                                                                      ├─► MediaMTX :8554 ─► Blue Iris
 Vitade (desk, faces you) ─┬─VAAPI H.264 encode──► deskcam-capture ───┘         │            <blue-iris-ip>
                           └─raw 720p───────────► /dev/video10 ──► Zoom/Meet/Teams
                                                                                ▼
                                                                        porchcam-overlay
                                                                        (desktop, 127.0.0.1)
```

The single-capture design is the whole point: a USB webcam will not let two
processes open it. Capturing once and redistributing is what lets Blue Iris
record the desk camera *while* you are on a video call, and lets the desktop
overlay come and go without interrupting recording.

| | Porch camera | Desk camera |
|---|---|---|
| Hardware | Logitech HD Pro Webcam C920 | Any UVC webcam without hardware H.264 |
| Device | set in `etc/porchcam/capture.env` | set in `etc/porchcam/deskcam.env` |
| Encoding | **In the camera** (native H.264) — no CPU, no GPU | **VAAPI on the Radeon** — camera has no H.264 |
| RTSP path | `/porch` | `/desk` |
| Also feeds | Desktop overlay | `/dev/video10` virtual camera |

Point `DEVICE=` in each `.env` file at your own camera — run
`ls -l /dev/v4l/by-id/` to find it. Both cameras are selected by stable
`/dev/v4l/by-id/...` paths, never by device number, and each capture service re-checks the camera's card type on every start
— if a USB re-enumeration puts a different camera on that path, it refuses to
stream rather than silently publishing the wrong view.

---

## Install

```bash
sudo LAN_CIDR=192.168.1.0/24 ./install.sh   # install or update
sudo ./install.sh --no-packages             # skip apt, just push files
```

**Set `LAN_CIDR` to your own subnet.** It decides who may read the camera
streams. It is deliberately not auto-detected — on a host running docker or
libvirt the first route is usually `172.17.0.0/16`, and quietly granting access
to the wrong subnet is a security bug rather than a convenience. The installer
prints the candidate subnets on your host if you leave it at the default.

Idempotent. Re-running never regenerates the RTSP password, so an
already-configured Blue Iris camera keeps working. Local edits to
`/etc/porchcam/*.env` are never clobbered — the installer prints a diff instead.

Override defaults with environment variables:

```bash
sudo LAN_CIDR=10.0.0.0/24 DESKTOP_USER=someone ./install.sh
```

Remove everything:

```bash
sudo ./uninstall.sh                    # keeps shared packages
sudo ./uninstall.sh --purge-packages   # also removes packages added for this
```

---

## Blue Iris

```
rtsp://camreader:<password>@<workstation-ip>:8554/porch
rtsp://camreader:<password>@<workstation-ip>:8554/desk
```

    sudo cat /etc/porchcam/rtsp-password

Settings (Camera ▸ Video ▸ Network IP):

| Field | Value |
|---|---|
| Make / Model | Generic / RTSP H.264 |
| Address | `<workstation-ip>` |
| Port / RTSP port | `8554` |
| Path | `/porch` or `/desk` |
| Username | `camreader` |
| Password | from `/etc/porchcam/rtsp-password` |
| Protocol | RTSP over **TCP** |
| Resolution | 1920×1080 |

Leave "Direct to disk" on — both streams are already H.264, so Blue Iris does
not need to re-encode.

**Access control.** Only user `camreader`, and only from the LAN subnet, may read.
Anonymous access and wrong passwords are refused. Loopback gets unauthenticated
access so the overlay works. Nothing is exposed to the internet; no router
settings were changed.

---

## Video conferencing

Pick **"Deskcam (virtual)"** as the camera in Zoom, Meet, Teams, or Chrome —
*not* the physical webcam. It is `/dev/video10`, fed 1280×720 by
`deskcam-capture`, and it works at the same time as Blue Iris recording.

Selecting the physical camera instead will fail or block the capture service,
since only one process can own a USB webcam.

The node is pinned to `video_nr=10` with `exclusive_caps=1` (both required for
Chrome and Zoom to list it). Config lives in
`/etc/modprobe.d/porchcam-v4l2loopback.conf`; changing options needs a reboot or
`modprobe -r v4l2loopback`.

---

## Desktop overlay

Start/stop with `porchcam-overlay-toggle`, or the **Porch Camera Overlay** menu
entry. Starts automatically at login.

| Control | Action |
|---|---|
| Drag with left mouse button | Move |
| Mouse wheel | Resize (16:9 locked) |
| **Ctrl** + mouse wheel | Transparency |
| `+` / `-` | Resize |
| `[` / `]` | Transparency |
| `r` | Reset |
| Right click | Menu (reconnect / reset / close) |
| `Esc` or `Ctrl+Q` | Close |

Defaults to 480×270 at 70% opacity, top-left of the **primary** monitor.
Size, position and opacity persist in `~/.config/porchcam/overlay.json`; delete
it to return to defaults.

Transparency is genuine window-wide transparency — the compositor blends the
whole window, video included (`_NET_WM_WINDOW_OPACITY`), not merely a
transparent background. This requires X11; on Wayland the window will show but
opacity and always-on-top behave differently.

The overlay rebuilds its GStreamer pipeline on any stream failure and runs a
frame watchdog: driving a dead `rtspsrc` from `NULL` back to `PLAYING`
reconnects at the protocol level but never resumes frames, which looks exactly
like a frozen picture. A reconnect therefore always means a brand-new pipeline.

---

## Operating

```bash
porchcam-status                       # one-glance health check for everything

systemctl status mediamtx             # RTSP server
systemctl status porchcam-capture     # porch camera
systemctl status deskcam-capture      # desk camera + virtual camera

journalctl -u deskcam-capture -f      # follow a log
sudo systemctl restart porchcam-capture
```

Disable without uninstalling:

```bash
sudo systemctl disable --now porchcam-capture deskcam-capture mediamtx
rm ~/.config/autostart/porchcam-overlay.desktop
```

---

## Tuning

`/etc/porchcam/capture.env` (porch) and `/etc/porchcam/deskcam.env` (desk).
Edit, then restart that service.

| Setting | Meaning |
|---|---|
| `WIDTH` / `HEIGHT` / `FPS` | Capture format |
| `INPUT_FORMAT` | `h264` (C920, free), `mjpeg`, `yuyv` |
| `DYNAMIC_FRAMERATE` | Porch only. `0` = steady rate (default). `1` = brighter at night but the rate collapses — as low as ~4 fps in real darkness |
| `CONF_WIDTH` / `CONF_HEIGHT` | Desk only. Size offered to conferencing apps |
| `BITRATE` | Desk only. VAAPI encode bitrate |
| `VAAPI_DEVICE` | Desk only. Render node used for encoding |
| `PKT_SIZE` | RTP payload; 1200 keeps packets under the server's 1440-byte limit |

**Night frame rate.** The C920 lengthens exposure in low light. With
`DYNAMIC_FRAMERATE=1` an unlit 2 a.m. scene fell to ~4 fps. The default `0`
holds a steady rate, which Blue Iris motion detection prefers. Either way an
unlit scene is nearly black — the porch light matters far more than this knob.

---

## Layout

| Path | What |
|---|---|
| `install.sh` / `uninstall.sh` | Deploy / remove |
| `bin/` | Capture wrappers, overlay, status, toggle |
| `systemd/` | Three service units |
| `mediamtx/mediamtx.yml.template` | Server config; `@@RTSP_PASSWORD@@` and `@@LAN_CIDR@@` are filled in at install |
| `etc/porchcam/*.env` | Per-camera tunables |
| `etc/modprobe.d`, `etc/modules-load.d` | Virtual camera setup |
| `desktop/` | Menu entry and autostart |

The rendered `mediamtx.yml` and `/etc/porchcam/rtsp-password` contain the
password and are **not** tracked — see `.gitignore`.

---

## Requirements

- Ubuntu 24.04 (or similar), **X11** — the overlay's window-wide transparency
  and always-on-top rely on X11 window properties
- One webcam with hardware H.264 (a C920 or similar) is ideal but not required;
  the desk path shows how to encode in hardware instead
- VAAPI-capable GPU for the encoded path (`vainfo` to check), or switch that
  camera to a software encoder in its `.env`
- `v4l2loopback` for the virtual camera

## Status

Working and in daily use for the porch camera, overlay, and Blue Iris. The desk
camera's virtual-webcam output is under active debugging — see the notes in
`bin/deskcam-capture`.
