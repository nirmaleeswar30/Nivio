#!/bin/bash

# Exit on error
set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "🏗️ Step 1: Building the Linux release bundle..."
./scripts/build_desktop.sh linux build

BUNDLE_DIR="packages/nivio_desktop/build/linux/x64/release/bundle"

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "❌ Build failed! Bundle directory not found."
  exit 1
fi

echo "🖼️ Step 2: Resizing icon for AppImage specification..."
# linuxdeploy requires icons to be exactly a standard size, like 512x512
cd "$BUNDLE_DIR"
if command -v magick &> /dev/null; then
  magick nivio.png -resize 512x512 nivio_512.png
  mv nivio_512.png nivio.png
elif command -v convert &> /dev/null; then
  convert nivio.png -resize 512x512 nivio_512.png
  mv nivio_512.png nivio.png
else
  echo "⚠️ Warning: ImageMagick (magick/convert) not found. Skipping icon resize. linuxdeploy may complain if icon is 1024x1024."
fi

# Go back to project root
cd "$PROJECT_ROOT"

echo "⚙️ Step 3: Checking for linuxdeploy (The thick AppImage builder)..."
LINUXDEPLOY="linuxdeploy"

if ! command -v linuxdeploy &> /dev/null; then
  echo "📥 linuxdeploy not found globally. Downloading to temporary location..."
  wget -q -c "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage" -O /tmp/linuxdeploy
  chmod +x /tmp/linuxdeploy
  LINUXDEPLOY="/tmp/linuxdeploy"
fi

echo "📦 Step 4: Generating standalone AppImage..."
echo "This might take a minute as it bundles ALL system dependencies (libmpv, libwpe, etc)..."

# Important: 
# 1. LD_LIBRARY_PATH ensures linuxdeploy finds the flutter plugins in bundle/lib
# 2. NO_STRIP=1 prevents crash on older strip binaries handling newer binutils
export LD_LIBRARY_PATH="$PROJECT_ROOT/$BUNDLE_DIR/lib:$LD_LIBRARY_PATH"
export NO_STRIP=1

echo "📝 Step 5: Creating custom AppRun wrapper for WebKit..."
# We must use a custom AppRun to disable the WebKit sandbox.
# The sandbox intentionally strips LD_LIBRARY_PATH, which causes the host's WebProcess
# to fail to find the bundled libwpe and libWPEWebKit.
cat << 'EOF' > "/tmp/custom_nivio_AppRun"
#!/bin/bash
export APPDIR="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$APPDIR/usr/lib:$APPDIR/lib:$LD_LIBRARY_PATH"

# Disable sandbox so WebKit doesn't strip LD_LIBRARY_PATH when spawning WebProcess
export WEBKIT_DISABLE_SANDBOX=1

exec "$APPDIR/nivio" "$@"
EOF
chmod +x "/tmp/custom_nivio_AppRun"

echo "📦 Step 6: Generating AppImage..."
# We run linuxdeploy normally (tracing only the main executable).
# We MUST explicitly exclude GTK, Wayland, and system dependencies because bundling
# them causes instant segmentation faults (core dumped) in ld-linux.so.2 on other distributions!
$LINUXDEPLOY \
  --appdir="$BUNDLE_DIR" \
  -e "$BUNDLE_DIR/nivio" \
  -d "$BUNDLE_DIR/nivio.desktop" \
  -i "$BUNDLE_DIR/nivio.png" \
  --exclude-library="libwayland-*.so*" \
  --exclude-library="libgtk-3.so*" \
  --exclude-library="libgdk-3.so*" \
  --exclude-library="libglib-2.0.so*" \
  --exclude-library="libgio-2.0.so*" \
  --exclude-library="libgobject-2.0.so*" \
  --exclude-library="libgmodule-2.0.so*" \
  --exclude-library="libcairo*.so*" \
  --exclude-library="libpango*.so*" \
  --exclude-library="libgdk_pixbuf-2.0.so*" \
  --exclude-library="libharfbuzz*.so*" \
  --exclude-library="libfontconfig.so*" \
  --exclude-library="libfreetype.so*" \
  --exclude-library="libsystemd.so*" \
  --exclude-library="libudev.so*" \
  --exclude-library="libmount.so*" \
  --exclude-library="libffi.so*" \
  --exclude-library="libzstd.so*" \
  --exclude-library="liblzma.so*" \
  --custom-apprun "/tmp/custom_nivio_AppRun" \
  --output "appimage"

echo "✅ Success! Your AppImage is generated safely!"
mv Nivio-*-x86_64.AppImage Nivio-Linux-x86_64.AppImage 2>/dev/null || true
