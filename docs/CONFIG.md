# porchcam configuration (`porchcam.yaml`)

Phase 0 of the [roadmap](ROADMAP.md): one declarative file is the source of
truth for the cameras. `porchcam-config render` turns it into the per-camera
`*.env` files the capture services read — so the YAML and the running services
never drift. The web UI and the AI-assisted setup (later phases) both read and
write this same file.

> The `*.env` files still work on their own. The YAML is a layer on top of them;
> you can keep hand-editing `.env` if you prefer. `render` regenerates the exact
> same `.env` content (verified by round-trip), so adopting the YAML is a no-op
> for a running system.

## File

`/etc/porchcam/porchcam.yaml`

```yaml
version: 1
rtsp_base: rtsp://127.0.0.1:8554      # mediamtx base; per-camera rtsp_path is appended
defaults:                             # optional: applied to every camera
  input_format: mjpeg
  vaapi_device: /dev/dri/renderD128
cameras:
  - name: porch
    service: porchcam-capture         # systemd unit to restart after a change
    env_file: capture.env             # the .env file `render` writes
    device: /dev/v4l/by-id/usb-...-video-index0   # stable by-id path
    usb_id: "046d:082d"               # vendor:product — found in any USB port
    expect_card: C920
    width: 1920
    height: 1080
    fps: 30
    input_format: mjpeg               # mjpeg (re-encode on VAAPI) or h264 (copy)
    rtsp_path: /porch                 # -> rtsp_base + rtsp_path
    bitrate: 6M
    vaapi_device: /dev/dri/renderD128
    dynamic_framerate: true           # porch only; brighter at night, variable fps
    img_ctrls: "brightness=176,backlight_compensation=1"
  - name: desk
    service: deskcam-capture
    env_file: deskcam.env
    device: /dev/v4l/by-id/usb-...-video-index0
    usb_id: "0c45:6366"
    expect_card: "HDA Webcam USB"
    width: 1920
    height: 1080
    fps: 20
    rtsp_path: /desk
    bitrate: 4M
    img_ctrls: "brightness=8,gamma=130,contrast=36,saturation=64"
    virtual_cam:                      # desk only: the v4l2loopback device for calls
      loopback: /dev/video10
      width: 1280
      height: 720
```

Any env key the tool does not model is preserved verbatim under a camera's
`extra_env:` map, so nothing is ever lost on a round-trip.

## Commands

```bash
porchcam-config list                     # list cameras in the config
porchcam-config validate                 # sanity-check the config
porchcam-config import > porchcam.yaml    # build a config from existing *.env
porchcam-config render --dry-run         # preview the *.env it would write
sudo porchcam-config render              # write /etc/porchcam/*.env from the yaml
sudo systemctl restart porchcam-capture deskcam-capture   # apply
```

`import` is the upgrade path for an existing install; `render` is reversible and
produces byte-for-byte equivalent `.env` content, so it is safe to adopt on a
live system.
