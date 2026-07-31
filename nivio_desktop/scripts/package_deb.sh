#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_DIR="$ROOT_DIR/build/linux/x64/release/bundle"
DIST_DIR="$ROOT_DIR/dist"
PKG_NAME="nivio-desktop"
APP_ID="com.nivio.desktop"
VERSION="$(sed -n 's/^version: \([0-9][^+]*\).*/\1/p' "$ROOT_DIR/pubspec.yaml" | head -n 1)"
DEB_ROOT="$ROOT_DIR/build/deb/${PKG_NAME}_${VERSION}_amd64"
DEB_FILE="$DIST_DIR/${PKG_NAME}_${VERSION}_amd64.deb"
MAINTAINER="${MAINTAINER:-Nivio Desktop Maintainers <support@nivio.app>}"

if [[ -z "$VERSION" ]]; then
  echo "Could not read app version from pubspec.yaml" >&2
  exit 1
fi

if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  "$ROOT_DIR/scripts/build_linux_release.sh"
fi

if [[ ! -x "$BUNDLE_DIR/nivio_desktop" ]]; then
  echo "Release bundle not found at $BUNDLE_DIR" >&2
  echo "Run: scripts/build_linux_release.sh" >&2
  exit 1
fi

rm -rf "$DEB_ROOT"
mkdir -p \
  "$DEB_ROOT/DEBIAN" \
  "$DEB_ROOT/opt/nivio-desktop" \
  "$DEB_ROOT/usr/bin" \
  "$DEB_ROOT/usr/share/applications" \
  "$DEB_ROOT/usr/share/icons/hicolor" \
  "$DIST_DIR"

cp -a "$BUNDLE_DIR/." "$DEB_ROOT/opt/nivio-desktop/"
install -Dm755 "$ROOT_DIR/packaging/linux/nivio-desktop" \
  "$DEB_ROOT/usr/bin/nivio-desktop"
install -Dm644 "$ROOT_DIR/packaging/linux/${APP_ID}.desktop" \
  "$DEB_ROOT/usr/share/applications/${APP_ID}.desktop"
cp -a "$ROOT_DIR/linux/runner/resources/icons/hicolor/." \
  "$DEB_ROOT/usr/share/icons/hicolor/"

INSTALLED_SIZE="$(du -sk "$DEB_ROOT" | awk '{print $1}')"

cat > "$DEB_ROOT/DEBIAN/control" <<EOF_CONTROL
Package: $PKG_NAME
Version: $VERSION
Section: video
Priority: optional
Architecture: amd64
Maintainer: $MAINTAINER
Installed-Size: $INSTALLED_SIZE
Depends: libc6 (>= 2.31), libstdc++6, libglib2.0-0, libgtk-3-0, libwebkit2gtk-4.1-0, libmpv2, libgstreamer1.0-0, gstreamer1.0-plugins-base, gstreamer1.0-plugins-good, xdg-utils
Homepage: https://nivio.app
Description: Nivio Desktop for Linux
 A Linux desktop client for Nivio.
EOF_CONTROL

cat > "$DEB_ROOT/DEBIAN/postinst" <<'EOF_POSTINST'
#!/usr/bin/env bash
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
EOF_POSTINST

cat > "$DEB_ROOT/DEBIAN/postrm" <<'EOF_POSTRM'
#!/usr/bin/env bash
set -e

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || true
fi

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || true
fi
EOF_POSTRM

chmod 755 "$DEB_ROOT/DEBIAN/postinst" "$DEB_ROOT/DEBIAN/postrm"
dpkg-deb --root-owner-group --build "$DEB_ROOT" "$DEB_FILE"

echo "$DEB_FILE"
