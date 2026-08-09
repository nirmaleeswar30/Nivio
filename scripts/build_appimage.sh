#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Nivio"
BINARY_NAME="nivio"
APPDIR="$PROJECT_ROOT/build/appimage/$APP_NAME.AppDir"
DIST_DIR="$PROJECT_ROOT/dist"
APPIMAGETOOL="${APPIMAGETOOL:-/tmp/appimagetool-x86_64.AppImage}"
APPIMAGETOOL_URL="https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"

echo "🏗️ Step 1: Building the Linux release bundle..."
if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  ./scripts/build_desktop.sh linux build
fi

BUNDLE_DIR="packages/nivio_desktop/build/linux/x64/release/bundle"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "❌ Build failed! Bundle directory not found: $BUNDLE_DIR"
  exit 1
fi

echo "⚙️ Step 2: Downloading appimagetool..."
if [[ ! -x "$APPIMAGETOOL" ]]; then
  if [[ ! -f "$APPIMAGETOOL" ]]; then
    curl -L -o "$APPIMAGETOOL" "$APPIMAGETOOL_URL"
  fi
  chmod +x "$APPIMAGETOOL"
fi

echo "📦 Step 3: Preparing AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR" "$DIST_DIR"
cp -a "$BUNDLE_DIR/." "$APPDIR/"

echo "🖼️ Step 4: Setting up Icon and Desktop Entry..."
if command -v magick &> /dev/null; then
  magick "$APPDIR/nivio.png" -resize 512x512 "$APPDIR/nivio_512.png"
  mv "$APPDIR/nivio_512.png" "$APPDIR/nivio.png"
elif command -v convert &> /dev/null; then
  convert "$APPDIR/nivio.png" -resize 512x512 "$APPDIR/nivio_512.png"
  mv "$APPDIR/nivio_512.png" "$APPDIR/nivio.png"
fi

cp "$APPDIR/nivio.png" "$APPDIR/.DirIcon"

mkdir -p "$APPDIR/usr/share/applications"

# Ensure the .desktop file is correctly placed and named
if [ -f "$APPDIR/nivio.desktop" ]; then
  cp "$APPDIR/nivio.desktop" "$APPDIR/usr/share/applications/nivio.desktop"
fi

echo "📝 Step 5: Creating custom AppRun wrapper..."
cat > "$APPDIR/AppRun" <<'EOF'
#!/usr/bin/env bash
set -e

HERE="$(dirname "$(readlink -f "${0}")")"
export LD_LIBRARY_PATH="$HERE/lib:${LD_LIBRARY_PATH:-}"
export WEBKIT_DISABLE_SANDBOX=1
exec "$HERE/nivio" "$@"
EOF
chmod +x "$APPDIR/AppRun"

echo "📦 Step 6: Generating AppImage..."
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" \
  "$APPDIR" "$DIST_DIR/Nivio-Linux-x86_64.AppImage"

chmod +x "$DIST_DIR/Nivio-Linux-x86_64.AppImage"
echo "✅ Created $DIST_DIR/Nivio-Linux-x86_64.AppImage"

# Maintain compatibility with the original script output location
cp "$DIST_DIR/Nivio-Linux-x86_64.AppImage" "$PROJECT_ROOT/Nivio-Linux-x86_64.AppImage"
echo "✅ Success! Your AppImage is generated safely!"
