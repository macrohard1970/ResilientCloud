#!/usr/bin/env bash
# Download the frr_exporter binary into bin/ (bind-mounted into every FRR node).
# Optional: if bin/frr_exporter is absent, routers run normally without metrics.
#
# Usage: scripts/fetch-frr-exporter.sh

set -euo pipefail

VERSION="1.12.0"
SHA256="5279e275ec23e32902dd5c2cfac0c3ebf2f5673184bab367151dacf740888428"   # linux-amd64
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${LAB_DIR}/bin/frr_exporter"
NAME="frr_exporter-${VERSION}.linux-amd64"

if [[ -x "$DEST" ]] && "$DEST" --version 2>&1 | grep -q "$VERSION"; then
  echo "frr_exporter ${VERSION} already present"; exit 0
fi

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
curl -fsSL -o "$tmp/fe.tgz" \
  "https://github.com/tynany/frr_exporter/releases/download/v${VERSION}/${NAME}.tar.gz"
echo "${SHA256}  $tmp/fe.tgz" | sha256sum -c --quiet -
tar -xzf "$tmp/fe.tgz" -C "$tmp"
install -m 0755 "$tmp/${NAME}/frr_exporter" "$DEST"
echo "Installed $DEST (${VERSION})"
