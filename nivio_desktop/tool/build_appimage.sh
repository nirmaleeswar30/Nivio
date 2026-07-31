#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BUNDLE="$ROOT_DIR/build/linux/x64/release/bundle"
APPDIR="$ROOT_DIR/build/appimage/Nivio.AppDir"
DIST_DIR="$ROOT_DIR/dist"
APPIMAGETOOL="${APPIMAGETOOL:-/tmp/appimagetool-x86_64.AppImage}"

if [[ ! -x "$APPIMAGETOOL" ]]; then
  echo "appimagetool not found at $APPIMAGETOOL" >&2
  echo "Download it to /tmp/appimagetool-x86_64.AppImage and make it executable." >&2
  exit 1
fi

if [[ ! -x "$BUILD_BUNDLE/nivio_desktop" ]]; then
  echo "Release bundle not found. Run: scripts/build_linux_release.sh" >&2
  exit 1
fi

rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps" "$DIST_DIR"

cp -a "$BUILD_BUNDLE/." "$APPDIR/usr/bin/"
cp "$ROOT_DIR/assets/images/nivio-dark.png" \
  "$APPDIR/usr/share/icons/hicolor/256x256/apps/nivio.png"
cp "$ROOT_DIR/assets/images/nivio-dark.png" "$APPDIR/nivio.png"
ln -sf "usr/share/icons/hicolor/256x256/apps/nivio.png" "$APPDIR/.DirIcon"

cat >"$APPDIR/nivio.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Nivio
Comment=Nivio Desktop
Exec=nivio_desktop
Icon=nivio
Categories=AudioVideo;Video;Player;
Terminal=false
DESKTOP

cp "$APPDIR/nivio.desktop" "$APPDIR/usr/share/applications/nivio.desktop"

cat >"$APPDIR/AppRun" <<'APPRUN'
#!/usr/bin/env bash
set -euo pipefail
APPDIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$APPDIR/usr/bin/lib:${LD_LIBRARY_PATH:-}"
exec "$APPDIR/usr/bin/nivio_desktop" "$@"
APPRUN

chmod +x "$APPDIR/AppRun" "$APPDIR/usr/bin/nivio_desktop"

ARCH=x86_64 "$APPIMAGETOOL" "$APPDIR" "$DIST_DIR/Nivio-Linux-x86_64.AppImage"
chmod +x "$DIST_DIR/Nivio-Linux-x86_64.AppImage"

echo "$DIST_DIR/Nivio-Linux-x86_64.AppImage"
