#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Nivio"
BINARY_NAME="nivio_desktop"
APP_ID="com.nivio.desktop"
APPDIR="$ROOT_DIR/build/appimage/$APP_NAME.AppDir"
DIST_DIR="$ROOT_DIR/dist"
APPIMAGETOOL="${APPIMAGETOOL:-/tmp/appimagetool-x86_64.AppImage}"
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

if [[ ! -x "$APPIMAGETOOL" ]]; then
  if [[ ! -f "$APPIMAGETOOL" ]]; then
    curl -L -o "$APPIMAGETOOL" "$APPIMAGETOOL_URL"
  fi
  chmod +x "$APPIMAGETOOL"
fi

cd "$ROOT_DIR"
flutter build linux --release

rm -rf "$APPDIR"
mkdir -p "$APPDIR" "$DIST_DIR"
cp -a "$ROOT_DIR/build/linux/x64/release/bundle/." "$APPDIR/"

cp "$ROOT_DIR/assets/images/app-icon.png" "$APPDIR/$BINARY_NAME.png"
cp "$ROOT_DIR/assets/images/app-icon.png" "$APPDIR/.DirIcon"

mkdir -p \
  "$APPDIR/usr/share/applications" \
  "$APPDIR/usr/share/icons/hicolor"
cp -a "$ROOT_DIR/linux/runner/resources/icons/hicolor/." \
  "$APPDIR/usr/share/icons/hicolor/"

cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
exec "$HERE/nivio_desktop" "$@"
EOF
chmod +x "$APPDIR/AppRun"

cat > "$APPDIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Nivio
Comment=Nivio Desktop
Exec=AppRun
Icon=$BINARY_NAME
Categories=AudioVideo;Video;Player;
Terminal=false
StartupNotify=true
EOF
cp "$APPDIR/$APP_ID.desktop" "$APPDIR/usr/share/applications/$APP_ID.desktop"

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" \
  "$APPDIR" "$DIST_DIR/Nivio-x86_64.AppImage"

chmod +x "$DIST_DIR/Nivio-x86_64.AppImage"
echo "Created $DIST_DIR/Nivio-x86_64.AppImage"
