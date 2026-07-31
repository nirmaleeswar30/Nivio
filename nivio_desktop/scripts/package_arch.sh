#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_DIR="$ROOT_DIR/packaging/arch"
DIST_DIR="$ROOT_DIR/dist"

mkdir -p "$DIST_DIR"
cd "$ARCH_DIR"

if [[ "${SKIP_FLUTTER_BUILD:-0}" == "1" ]]; then
  makepkg -f --nodeps
else
  makepkg -f
fi

pkg_file="$(ls -t nivio-desktop-*-x86_64.pkg.tar.zst | head -n 1)"
cp "$pkg_file" "$DIST_DIR/$pkg_file"

echo "$DIST_DIR/$pkg_file"
