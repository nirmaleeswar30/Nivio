#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="Nivio"
BINARY_NAME="nivio"
BUILD_DIR="$PROJECT_ROOT/build/appimage"
APPDIR="$BUILD_DIR/$APP_NAME.AppDir"
DIST_DIR="$PROJECT_ROOT/dist"
BUNDLE_DIR="$PROJECT_ROOT/packages/nivio_desktop/build/linux/x64/release/bundle"
APPIMAGETOOL="${APPIMAGETOOL:-/tmp/appimagetool-x86_64.AppImage}"
APPIMAGETOOL_URL="https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"

# Build type selection (normal vs shorebird)
BUILD_TYPE="${1:-}"

if [[ -z "$BUILD_TYPE" ]]; then
  if [ -t 0 ]; then
    echo ""
    echo "=============================================="
    echo "       Select Linux AppImage Build Type       "
    echo "=============================================="
    echo "  1) Standard Flutter Release (no Shorebird)"
    echo "  2) Shorebird Release (OTA-enabled)"
    echo "=============================================="
    read -r -p "Enter choice [1 or 2, default: 1]: " choice
    case "${choice:-1}" in
      2|shorebird)
        BUILD_TYPE="shorebird"
        ;;
      *)
        BUILD_TYPE="normal"
        ;;
    esac
  else
    BUILD_TYPE="normal"
  fi
fi

if [[ "$BUILD_TYPE" == "shorebird" ]]; then
  echo "🦅 Target: Shorebird Linux AppImage (OTA-enabled)"
else
  echo "🏗️ Target: Standard Flutter Linux AppImage"
fi

echo "🏗️ Step 1: Building Linux release bundle..."
if [[ "${SKIP_FLUTTER_BUILD:-0}" != "1" ]]; then
  if [[ "$BUILD_TYPE" == "shorebird" ]]; then
    "$PROJECT_ROOT/scripts/build_desktop.sh" linux shorebird_release
  else
    "$PROJECT_ROOT/scripts/build_desktop.sh" linux build
  fi
fi

if [ ! -d "$BUNDLE_DIR" ]; then
  echo "❌ Build failed! Bundle directory not found: $BUNDLE_DIR"
  exit 1
fi

echo "⚙️ Step 2: Ensuring appimagetool is ready..."
if [[ ! -x "$APPIMAGETOOL" ]]; then
  if [[ ! -f "$APPIMAGETOOL" ]]; then
    echo "📥 Downloading appimagetool..."
    curl -L -o "$APPIMAGETOOL" "$APPIMAGETOOL_URL"
  fi
  chmod +x "$APPIMAGETOOL"
fi

echo "📦 Step 3: Preparing AppDir staging directory..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR" "$DIST_DIR"
cp -a "$BUNDLE_DIR/." "$APPDIR/"

echo "🌐 Step 4: Bundling WPE WebKit helper processes & runtime libraries..."
# 1. Bundle WPEWebKit auxiliary subprocesses (WPENetworkProcess, WPEWebProcess, etc.)
WPE_SYSTEM_DIR="/usr/lib/wpe-webkit-2.0"
if [ -d "$WPE_SYSTEM_DIR" ]; then
  mkdir -p "$APPDIR/lib/wpe-webkit-2.0"
  cp -a "$WPE_SYSTEM_DIR/." "$APPDIR/lib/wpe-webkit-2.0/"
  echo "  ✓ Bundled WPEWebKit subprocesses from $WPE_SYSTEM_DIR"
fi

# 2. Bundle WPE backend libraries (e.g. libWPEBackend-fdo)
for fdo_lib in /usr/lib/libWPEBackend-fdo-1.0.so*; do
  if [ -e "$fdo_lib" ]; then
    cp -d "$fdo_lib" "$APPDIR/lib/" 2>/dev/null || true
  fi
done

# 3. Bundle GStreamer plugins and scanner for HTML5 video/audio playback (YouTube, trailers)
GST_SYSTEM_DIR="/usr/lib/gstreamer-1.0"
if [ -d "$GST_SYSTEM_DIR" ]; then
  mkdir -p "$APPDIR/lib/gstreamer-1.0"
  cp -a "$GST_SYSTEM_DIR/." "$APPDIR/lib/gstreamer-1.0/"
  echo "  ✓ Bundled GStreamer 1.0 plugins (appsink, codecs, demuxers) from $GST_SYSTEM_DIR"
fi

# 4. Automatically resolve and bundle all required runtime dependencies (HarfBuzz, ICU, XML, codecs, GStreamer, etc.)
python3 - << 'PY'
import os, subprocess, re, shutil

appdir = os.environ.get("APPDIR", "build/appimage/Nivio.AppDir")
libdir = os.path.join(appdir, "lib")

# Fundamental host / graphics driver / desktop libraries that MUST come from host OS
SYSTEM_EXCLUDES = (
    # glibc
    "libc.so", "libm.so", "libpthread.so", "libdl.so", "librt.so", "ld-linux",
    # GPU / DRM / Display hardware drivers
    "libGL.so", "libGLX.so", "libEGL.so", "libGLdispatch.so", "libdrm.so", "libgbm.so", "libvulkan.so",
    # Low-level system & audio hardware daemons
    "libsystemd.so", "libudev.so", "libdbus-1.so", "libasound.so",
    # X11 / Wayland core client protocols
    "libX11.so", "libX11-xcb.so", "libXau.so", "libXdmcp.so", "libXext.so", "libXfixes.so", "libXi.so", "libXrender.so",
    "libxcb", "libwayland-client.so", "libwayland-server.so", "libwayland-cursor.so", "libwayland-egl.so",
    # GTK / GLib core runtime (host themes & desktop settings)
    "libgtk-3.so", "libgdk-3.so", "libgdk_pixbuf-2.0.so",
    "libgio-2.0.so", "libglib-2.0.so", "libgobject-2.0.so", "libgmodule-2.0.so",
    "libpango-1.0.so", "libpangocairo-1.0.so", "libpangoft2-1.0.so", "libcairo.so", "libcairo-gobject.so"
)

def is_excluded(soname):
    return any(soname.startswith(prefix) for prefix in SYSTEM_EXCLUDES)

targets = []
# Find all ELF binaries and libraries in AppDir
for root, dirs, files in os.walk(appdir):
    for f in files:
        p = os.path.join(root, f)
        if not os.path.islink(p):
            try:
                with open(p, "rb") as fp:
                    if fp.read(4) == b"\x7fELF":
                        targets.append(p)
            except:
                pass

to_copy = {}
to_inspect = list(targets)
visited = set()

while to_inspect:
    curr = to_inspect.pop(0)
    if curr in visited:
        continue
    visited.add(curr)
    try:
        out = subprocess.check_output(["ldd", curr], stderr=subprocess.DEVNULL).decode()
        for line in out.splitlines():
            m = re.search(r'^\s*([^\s]+)\s+=>\s+([^\s]+)\s+\(', line)
            if m:
                soname, realpath = m.group(1), m.group(2)
                if is_excluded(soname):
                    continue
                if not os.path.isfile(realpath):
                    continue
                if realpath.startswith("/usr/lib") or realpath.startswith("/lib"):
                    dest = os.path.join(libdir, soname)
                    if not os.path.exists(dest) and soname not in to_copy:
                        to_copy[soname] = realpath
                        to_inspect.append(realpath)
    except Exception as e:
        pass

copied_count = 0
for soname, realpath in to_copy.items():
    dest = os.path.join(libdir, soname)
    try:
        shutil.copy2(realpath, dest)
        copied_count += 1
    except Exception as e:
        print(f"  ⚠️ Could not copy {soname}: {e}")

print(f"  ✓ Bundled {copied_count} runtime shared libraries (including HarfBuzz-ICU, codecs, GStreamer)")
PY

# 4. Ensure soname symlinks are present in AppDir/lib
cd "$APPDIR/lib"
for soname in libwpe-1.0.so.1 libWPEWebKit-2.0.so.1 libWPEBackend-fdo-1.0.so.1; do
  if [ ! -e "$soname" ]; then
    target=$(find . -maxdepth 1 -type f -name "$soname.*" -printf '%f\n' 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$target" ]; then
      ln -s "$target" "$soname"
      echo "  ✓ Linked $soname -> $target"
    fi
  fi
done
cd "$PROJECT_ROOT"

# 5. Patch hardcoded PKGLIBEXECDIR in bundled libWPEWebKit so it redirects subprocess lookup to /tmp/wpe-webkit-2.0
python3 - << 'PY'
import glob

old_str1 = b'/usr/lib/wpe-webkit-2.0\x00'
new_str1 = b'/tmp/wpe-webkit-2.0\x00' + b'\x00' * (len(old_str1) - len(b'/tmp/wpe-webkit-2.0\x00'))

old_str2 = b'/usr/lib/wpe-webkit-2.0/injected-bundle/\x00'
new_str2 = b'/tmp/wpe-webkit-2.0/injected-bundle/\x00' + b'\x00' * (len(old_str2) - len(b'/tmp/wpe-webkit-2.0/injected-bundle/\x00'))

for so_file in glob.glob("build/appimage/Nivio.AppDir/lib/libWPEWebKit-2.0.so*"):
    try:
        with open(so_file, "r+b") as f:
            content = f.read()
            if old_str1 in content or old_str2 in content:
                content = content.replace(old_str1, new_str1).replace(old_str2, new_str2)
                f.seek(0)
                f.write(content)
                f.truncate()
                print(f"  ✓ Patched subprocess lookup paths in {so_file}")
    except Exception as e:
        print(f"  ⚠️ Could not patch {so_file}: {e}")
PY

echo "🖼️ Step 5: Setting up Icon and Desktop Entry..."
ICON_SOURCE="$PROJECT_ROOT/packages/nivio_desktop/assets/images/nivio.png"
if [ ! -f "$ICON_SOURCE" ]; then
  ICON_SOURCE="$PROJECT_ROOT/assets/images/nivio.png"
fi

mkdir -p "$APPDIR/usr/share/icons/hicolor/512x512/apps"
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$APPDIR/usr/share/applications"

cp "$ICON_SOURCE" "$APPDIR/nivio.png"
cp "$ICON_SOURCE" "$APPDIR/.DirIcon"
cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/512x512/apps/nivio.png"
cp "$ICON_SOURCE" "$APPDIR/usr/share/icons/hicolor/256x256/apps/nivio.png"

DESKTOP_SOURCE="$PROJECT_ROOT/packages/nivio_desktop/linux/nivio.desktop"
if [ -f "$DESKTOP_SOURCE" ]; then
  cp "$DESKTOP_SOURCE" "$APPDIR/nivio.desktop"
  cp "$DESKTOP_SOURCE" "$APPDIR/usr/share/applications/nivio.desktop"
fi

echo "📝 Step 6: Creating custom AppRun wrapper..."
cat > "$APPDIR/AppRun" << 'EOF'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"

export LD_LIBRARY_PATH="$HERE/lib:$HERE/lib/wpe-webkit-2.0:${LD_LIBRARY_PATH:-}"
export XDG_DATA_DIRS="$HERE/share:/usr/share:${XDG_DATA_DIRS:-}"

# Configure GStreamer to use bundled plugins (appsink, playbin, ffmpeg/libav, etc.)
export GST_PLUGIN_SYSTEM_PATH_1_0="$HERE/lib/gstreamer-1.0:${GST_PLUGIN_SYSTEM_PATH_1_0:-}"
export GST_PLUGIN_SCANNER_1_0="$HERE/lib/gstreamer-1.0/gst-plugin-scanner"

# Disable WebKit sandbox inside AppImage container
export WEBKIT_DISABLE_SANDBOX=1
export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1

# Ensure /tmp/wpe-webkit-2.0 points to the bundled helper processes
rm -f /tmp/wpe-webkit-2.0 2>/dev/null || true
ln -sfn "$HERE/lib/wpe-webkit-2.0" /tmp/wpe-webkit-2.0 2>/dev/null || true

exec "$HERE/nivio" "$@"
EOF
chmod +x "$APPDIR/AppRun"

# Extract version from pubspec.yaml
APP_VERSION="1.0.0"
if [ -f "$PROJECT_ROOT/pubspec.yaml" ]; then
  APP_VERSION=$(grep '^version:' "$PROJECT_ROOT/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f1)
elif [ -f "$PROJECT_ROOT/packages/nivio_desktop/pubspec.yaml" ]; then
  APP_VERSION=$(grep '^version:' "$PROJECT_ROOT/packages/nivio_desktop/pubspec.yaml" | head -n 1 | awk '{print $2}' | cut -d'+' -f1)
fi
APP_VERSION="${APP_VERSION:-1.0.0}"

echo "📦 Step 7: Generating AppImage with appimagetool (Version: $APP_VERSION, Type: $BUILD_TYPE)..."
if [[ "$BUILD_TYPE" == "shorebird" ]]; then
  VERSIONED_APPIMAGE="$DIST_DIR/Nivio-Linux-Shorebird-$APP_VERSION-x86_64.AppImage"
  GENERIC_APPIMAGE="$DIST_DIR/Nivio-Linux-Shorebird-x86_64.AppImage"
else
  VERSIONED_APPIMAGE="$DIST_DIR/Nivio-Linux-$APP_VERSION-x86_64.AppImage"
  GENERIC_APPIMAGE="$DIST_DIR/Nivio-Linux-x86_64.AppImage"
fi

rm -f "$VERSIONED_APPIMAGE" "$GENERIC_APPIMAGE" 2>/dev/null || true

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$APPIMAGETOOL" \
  "$APPDIR" "$VERSIONED_APPIMAGE"

chmod +x "$VERSIONED_APPIMAGE"
cp -f "$VERSIONED_APPIMAGE" "$GENERIC_APPIMAGE" 2>/dev/null || true

echo "🎉 Success! Created AppImage: $VERSIONED_APPIMAGE"
echo "  (Also available as: $GENERIC_APPIMAGE)"
