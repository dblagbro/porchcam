#!/bin/bash
# install.sh — deploy the two-camera streaming setup from this repo.
#
# Idempotent: safe to re-run after editing anything here. It will NOT regenerate
# the RTSP password once one exists, so re-running never breaks an already
# configured Blue Iris camera.
#
#   sudo ./install.sh                 # install / update
#   sudo ./install.sh --no-packages   # skip apt, just push files
#
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MEDIAMTX_VERSION=${MEDIAMTX_VERSION:-v1.21.0}
LAN_CIDR_ENV=${LAN_CIDR:-}
# LAN_CIDR decides who may read the camera streams, so it is NOT auto-detected:
# on a host with docker or libvirt bridges the first route is typically
# 172.17.0.0/16, and silently granting access to the wrong subnet is a security
# bug, not a convenience. Set it explicitly:  sudo LAN_CIDR=… ./install.sh
LAN_CIDR=${LAN_CIDR:-192.168.1.0/24}
PASSWORD_FILE=/etc/porchcam/rtsp-password
DESKTOP_USER=${DESKTOP_USER:-${SUDO_USER:-$(logname 2>/dev/null)}}

[[ $EUID -eq 0 ]] || { echo "run with sudo" >&2; exit 1; }

say() { printf '\n\033[1m== %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- packages ---
if [[ ${1:-} != --no-packages ]]; then
    say "packages"
    DEBIAN_FRONTEND=noninteractive apt-get install -y \
        ffmpeg v4l-utils v4l2loopback-dkms \
        gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav \
        python3-gi gir1.2-gtk-3.0 gir1.2-gstreamer-1.0 \
        vainfo curl
fi

# ---------------------------------------------------------------- mediamtx ---
say "mediamtx $MEDIAMTX_VERSION"
install -d -m 0755 /opt/mediamtx
if [[ ! -x /opt/mediamtx/mediamtx ]] || \
   ! /opt/mediamtx/mediamtx --version 2>/dev/null | grep -qx "$MEDIAMTX_VERSION"; then
    tmp=$(mktemp -d)
    url="https://github.com/bluenviron/mediamtx/releases/download/${MEDIAMTX_VERSION}/mediamtx_${MEDIAMTX_VERSION}_linux_amd64.tar.gz"
    echo "  downloading $url"
    curl -sSL --max-time 180 -o "$tmp/m.tgz" "$url"
    tar xzf "$tmp/m.tgz" -C "$tmp"
    install -m 0755 "$tmp/mediamtx" /opt/mediamtx/mediamtx
    install -m 0644 "$tmp/mediamtx.yml" /opt/mediamtx/mediamtx.yml.dist
    rm -rf "$tmp"
else
    echo "  already at $MEDIAMTX_VERSION"
fi

# ---------------------------------------------------------------- accounts ---
say "service accounts"
id mediamtx &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin mediamtx
id porchcam &>/dev/null || useradd --system --no-create-home --shell /usr/sbin/nologin -G video porchcam
# render group is needed for VAAPI encoding on the desk camera
getent group render >/dev/null && usermod -aG render porchcam

# ---------------------------------------------------------------- password ---
say "RTSP credentials"
install -d -m 0755 /etc/porchcam
if [[ ! -s $PASSWORD_FILE ]]; then
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20 > "$PASSWORD_FILE"
    echo "  generated a new password"
else
    echo "  keeping the existing password (Blue Iris stays configured)"
fi
chgrp porchcam "$PASSWORD_FILE" 2>/dev/null || true
chmod 0640 "$PASSWORD_FILE"

# ------------------------------------------------------------ mediamtx.yml ---
say "mediamtx config"
PASS=$(cat "$PASSWORD_FILE")
tmp=$(mktemp)
sed -e "s|@@RTSP_PASSWORD@@|${PASS}|" -e "s|@@LAN_CIDR@@|${LAN_CIDR}|g" \
    "$REPO/mediamtx/mediamtx.yml.template" > "$tmp"
install -m 0640 -o root -g mediamtx "$tmp" /opt/mediamtx/mediamtx.yml
rm -f "$tmp"
unset PASS
echo "  rendered (LAN $LAN_CIDR)"
if [[ -z ${LAN_CIDR_ENV:-} ]]; then
    cat <<WARN

  NOTE: stream access is restricted to $LAN_CIDR.
  If that is not your LAN, re-run with the right subnet, e.g.:
      sudo LAN_CIDR=192.168.10.0/24 ./install.sh
  Candidate subnets on this host:
$(ip -4 -o addr show scope global 2>/dev/null | awk '{printf "      %-10s %s\n", $2, $4}')
WARN
fi

# --------------------------------------------------------------- v4l2loopback -
say "virtual camera"
install -m 0644 "$REPO/etc/modprobe.d/porchcam-v4l2loopback.conf"     /etc/modprobe.d/
install -m 0644 "$REPO/etc/modules-load.d/porchcam-v4l2loopback.conf" /etc/modules-load.d/
if ! lsmod | grep -q '^v4l2loopback'; then
    modprobe v4l2loopback && echo "  module loaded"
else
    echo "  module already loaded (reboot or 'modprobe -r v4l2loopback' to apply option changes)"
fi

# ---------------------------------------------------------------- programs ---
say "scripts"
for f in "$REPO"/bin/*; do
    install -m 0755 "$f" /usr/local/bin/
    echo "  /usr/local/bin/$(basename "$f")"
done
install -m 0755 "$REPO/uninstall.sh" /usr/local/bin/porchcam-uninstall

# --------------------------------------------------------------- env files ---
say "capture config"
# Never clobber local tuning: install only if missing, otherwise show a diff.
for f in "$REPO"/etc/porchcam/*.env; do
    dest=/etc/porchcam/$(basename "$f")
    if [[ ! -e $dest ]]; then
        install -m 0644 "$f" "$dest"; echo "  installed $dest"
    elif ! diff -q "$f" "$dest" >/dev/null; then
        echo "  $dest differs from the repo — left alone. Diff:"
        diff -u "$dest" "$f" | sed 's/^/    /' || true
    else
        echo "  $dest unchanged"
    fi
done

# ----------------------------------------------------------------- systemd ---
say "services"
install -m 0644 "$REPO"/systemd/*.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now mediamtx.service
# Give the server a moment to bind before the publishers connect; the capture
# wrappers also poll the API themselves, so this is belt-and-braces only.
systemctl enable --now porchcam-capture.service
systemctl enable --now deskcam-capture.service
systemctl restart porchcam-capture.service deskcam-capture.service

# ----------------------------------------------------------------- desktop ---
say "desktop integration for $DESKTOP_USER"
if home=$(getent passwd "$DESKTOP_USER" | cut -d: -f6) && [[ -d $home ]]; then
    install -d -o "$DESKTOP_USER" -g "$DESKTOP_USER" \
        "$home/.local/share/applications" "$home/.config/autostart"
    install -m 0644 -o "$DESKTOP_USER" -g "$DESKTOP_USER" \
        "$REPO/desktop/porchcam-overlay.desktop" "$home/.local/share/applications/"
    install -m 0644 -o "$DESKTOP_USER" -g "$DESKTOP_USER" \
        "$REPO/desktop/porchcam-overlay-autostart.desktop" \
        "$home/.config/autostart/porchcam-overlay.desktop"
    echo "  menu entry + autostart installed"
else
    echo "  user $DESKTOP_USER has no home directory — skipped"
fi

say "done"
echo "Blue Iris URL:  rtsp://camreader:<password>@$(hostname -I | tr ' ' '\n' | grep -E '^192\.168\.18\.' | head -1):8554/porch"
echo "                rtsp://camreader:<password>@$(hostname -I | tr ' ' '\n' | grep -E '^192\.168\.18\.' | head -1):8554/desk"
echo "password:       sudo cat $PASSWORD_FILE"
echo "health check:   porchcam-status"
