#!/usr/bin/env bash
# Build the porchcam .deb with nfpm. Run from anywhere; operates on the repo root.
#
#   packaging/build-deb.sh [version]      # default version 0.1.0
#
# nfpm is a single static binary. If it is not on PATH, drop it at ./build/nfpm
# (download from https://github.com/goreleaser/nfpm/releases) and this script
# will use it. The .deb lands in dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-0.1.0}"

if command -v nfpm >/dev/null 2>&1; then
    NFPM="nfpm"
elif [ -x "./build/nfpm" ]; then
    NFPM="./build/nfpm"
else
    echo "build-deb: nfpm not found. Install it, or place the binary at ./build/nfpm" >&2
    echo "  https://github.com/goreleaser/nfpm/releases (Linux_x86_64.tar.gz)" >&2
    exit 1
fi

mkdir -p dist build
# Debian changelog, gzipped (-n: no timestamp, reproducible)
gzip -9nc packaging/changelog.Debian > build/changelog.gz

export PORCHCAM_VERSION="$VERSION"
"$NFPM" pkg -f packaging/nfpm.yaml -p deb -t "dist/porchcam_${VERSION}_amd64.deb"
echo "build-deb: wrote dist/porchcam_${VERSION}_amd64.deb"
