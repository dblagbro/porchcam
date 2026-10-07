#!/bin/bash
# porchcam-uninstall — remove everything this setup installed.
# Leaves the OS packages alone (ffmpeg, gstreamer, v4l-utils) since other
# things may use them; pass --purge-packages to remove the ones added for this.
set -uo pipefail
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }

echo "stopping and disabling services…"
systemctl disable --now camera-encode-reset.timer 2>/dev/null
systemctl disable --now camera-corruption-monitor.service 2>/dev/null
systemctl disable --now porchcam-capture.service 2>/dev/null
systemctl disable --now deskcam-capture.service 2>/dev/null
systemctl disable --now mediamtx.service 2>/dev/null
rm -f /etc/systemd/system/porchcam-capture.service \
      /etc/systemd/system/deskcam-capture.service \
      /etc/systemd/system/mediamtx.service \
      /etc/systemd/system/camera-corruption-monitor.service \
      /etc/systemd/system/camera-encode-reset.service \
      /etc/systemd/system/camera-encode-reset.timer
rm -rf /etc/systemd/system/porchcam-capture.service.d
systemctl daemon-reload

echo "removing files…"
rm -rf /opt/mediamtx
rm -rf /etc/porchcam
rm -f /usr/local/bin/porchcam-* /usr/local/bin/deskcam-* /usr/local/bin/camera-* \
      /usr/local/bin/porchcam-uninstall

echo "removing the virtual camera…"
modprobe -r v4l2loopback 2>/dev/null
rm -f /etc/modprobe.d/porchcam-v4l2loopback.conf
rm -f /etc/modules-load.d/porchcam-v4l2loopback.conf

echo "removing service accounts…"
userdel mediamtx 2>/dev/null
userdel porchcam 2>/dev/null

# Per-user desktop bits (run for the invoking user, not root)
for home in /home/*; do
    u=$(basename "$home")
    rm -f "$home/.local/share/applications/porchcam-overlay.desktop"
    rm -f "$home/.config/autostart/porchcam-overlay.desktop"
    rm -rf "$home/.config/porchcam"
    pkill -u "$u" -f 'python3 /usr/local/bin/porchcam-overlay' 2>/dev/null
done

if [[ ${1:-} == --purge-packages ]]; then
    echo "removing packages added for porchcam…"
    DEBIAN_FRONTEND=noninteractive apt-get remove -y \
        v4l-utils gstreamer1.0-plugins-bad gstreamer1.0-libav xdotool
fi

echo "done. The camera itself is untouched."
