#!/bin/bash
# Builds Frameworks/Mpv.xcframework (iOS device, arm64) from the static
# libraries edde746/mpv-build publishes, pinned with checksums in
# mpv-ios.lock.
#
# Every library is linked into one dynamic Mpv.framework that exports only
# the mpv_* API: media_kit opens it with DynamicLibrary.open
# ('Mpv.framework/Mpv'), and keeping FFmpeg's symbols private means it can't
# clash with FFmpegKit's own FFmpeg frameworks in the same app.
#
# Needs macOS with Xcode. Downloads are cached in $MPV_IOS_CACHE (default
# ios/.cache). Run again after changing mpv-ios.lock.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
LOCK="$HERE/mpv-ios.lock"
OUT="$HERE/Frameworks"
CACHE="${MPV_IOS_CACHE:-$HERE/.cache}"
WORK="$HERE/.build"
MIN_IOS="15.0"

mkdir -p "$CACHE"
rm -rf "$WORK"
mkdir -p "$WORK/x"

# Prints the device (ios-arm64) library binary inside an .xcframework.
device_binary() {
  python3 - "$1" <<'PY'
import os, plistlib, sys
xc = sys.argv[1]
info = plistlib.load(open(os.path.join(xc, "Info.plist"), "rb"))
for lib in info["AvailableLibraries"]:
    if lib.get("SupportedPlatform") != "ios" or lib.get("SupportedPlatformVariant"):
        continue
    if "arm64" not in lib.get("SupportedArchitectures", []):
        continue
    base = os.path.join(xc, lib["LibraryIdentifier"])
    path = lib.get("BinaryPath") or lib["LibraryPath"]
    full = os.path.join(base, path)
    if os.path.isdir(full):  # LibraryPath of a framework without BinaryPath
        name = os.path.splitext(os.path.basename(full))[0]
        full = os.path.join(full, name)
    print(full)
    sys.exit(0)
sys.exit("no ios-arm64 library in " + xc)
PY
}

LIBMPV=""
OTHERS=()
while read -r name sum url; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  zip="$CACHE/$name-$sum.zip"
  if [ ! -f "$zip" ]; then
    echo "[mpv] downloading $name"
    curl -fL --retry 5 --retry-delay 3 --connect-timeout 30 -o "$zip.tmp" "$url"
    mv "$zip.tmp" "$zip"
  fi
  if ! echo "$sum  $zip" | shasum -a 256 -c - >/dev/null; then
    rm -f "$zip"
    echo "error: checksum mismatch for $name ($url)" >&2
    exit 1
  fi
  dest="$WORK/x/$name"
  mkdir -p "$dest"
  unzip -q -o "$zip" -d "$dest"
  rm -rf "$dest/__MACOSX"
  xc="$(find "$dest" -maxdepth 2 -name '*.xcframework' -type d | head -1)"
  [ -n "$xc" ] || { echo "error: no xcframework in $name" >&2; exit 1; }
  bin="$(device_binary "$xc")"
  echo "[mpv] $name -> ${bin#$WORK/x/}"
  if [ "$name" = "Libmpv" ]; then
    LIBMPV="$bin"
  else
    OTHERS+=("$bin")
  fi
done < "$LOCK"
[ -n "$LIBMPV" ] || { echo "error: Libmpv missing from $LOCK" >&2; exit 1; }

SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "_mpv_*" > "$WORK/exports.txt"
: > "$WORK/empty.swift"

# dispatch_sync shim (see shim/nivio_dispatch_sync.m): defined in this image,
# so libmpv's dispatch_sync calls bind to it instead of libdispatch's.
xcrun --sdk iphoneos clang -c -arch arm64 -miphoneos-version-min="$MIN_IOS"   -isysroot "$SDK" -fno-objc-arc -fblocks -O2   "$HERE/shim/nivio_dispatch_sync.m" -o "$WORK/nivio_dispatch_sync.o"

LINK_INPUTS=(-Xlinker "$WORK/nivio_dispatch_sync.o" -Xlinker -force_load -Xlinker "$LIBMPV")
for a in "${OTHERS[@]}"; do
  LINK_INPUTS+=(-Xlinker "$a")
done

# The system frameworks and libraries mpv-build's Package.swift links, plus the
# ones MoltenVK and the AVFoundation output use. swiftc (not clang) links,
# because libmpv contains Swift code (its spatial audio output) and swiftc
# brings in the Swift runtime and back-deployment libraries it needs.
echo "[mpv] linking Mpv.framework"
mkdir -p "$WORK/fw/Mpv.framework"
xcrun --sdk iphoneos swiftc \
  -emit-library \
  -module-name NivioMpvLink \
  -target "arm64-apple-ios$MIN_IOS" \
  -sdk "$SDK" \
  -Osize \
  "$WORK/empty.swift" \
  -o "$WORK/fw/Mpv.framework/Mpv" \
  "${LINK_INPUTS[@]}" \
  -Xlinker -ObjC \
  -Xlinker -dead_strip \
  -Xlinker -exported_symbols_list -Xlinker "$WORK/exports.txt" \
  -Xlinker -install_name -Xlinker @rpath/Mpv.framework/Mpv \
  -framework Accelerate -framework AVFoundation -framework AudioToolbox \
  -framework CoreAudio -framework CoreFoundation -framework CoreImage \
  -framework CoreMedia -framework CoreText -framework CoreVideo \
  -framework Foundation -framework IOSurface -framework Metal \
  -framework QuartzCore -framework Security -framework UIKit \
  -framework VideoToolbox -framework MediaPlayer \
  -lbz2 -liconv -lexpat -lresolv -lxml2 -lz -lc++

xcrun strip -x -S "$WORK/fw/Mpv.framework/Mpv"

cat > "$WORK/fw/Mpv.framework/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>Mpv</string>
  <key>CFBundleIdentifier</key><string>com.nivio.Mpv</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Mpv</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.41.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
PLIST

# Third-party licence texts travel with the framework.
mkdir -p "$WORK/fw/Mpv.framework/licenses"
find "$WORK/x" -iname 'LICENSE*' -type f -maxdepth 6 | while read -r f; do
  rel="${f#$WORK/x/}"
  cp "$f" "$WORK/fw/Mpv.framework/licenses/$(echo "$rel" | tr '/' '_')"
done

rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -create-xcframework -framework "$WORK/fw/Mpv.framework" -output "$OUT/Mpv.xcframework"

# media_kit_video links -framework Mpv from Frameworks/.symlinks/mpv/ios.
SLICE="$(cd "$OUT/Mpv.xcframework" && ls -d ios-arm64* | grep -v simulator | head -1)"
mkdir -p "$OUT/.symlinks/mpv/ios"
ln -sfn "../../../Mpv.xcframework/$SLICE/Mpv.framework" "$OUT/.symlinks/mpv/ios/Mpv.framework"

BIN="$OUT/Mpv.xcframework/$SLICE/Mpv.framework/Mpv"
nm -gU "$BIN" | grep -c ' _mpv_' | xargs echo "[mpv] exported mpv_* symbols:"
# libmpv must use the shim, not libdispatch's dispatch_sync.
if nm -m "$BIN" | grep -q '(undefined) external _dispatch_sync '; then
  echo "error: Mpv.framework still imports dispatch_sync; the shim was not linked in" >&2
  exit 1
fi
du -sh "$OUT/Mpv.xcframework"
rm -rf "$WORK"
echo "[mpv] Built $OUT/Mpv.xcframework"
