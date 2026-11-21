#!/bin/bash
# Builds Frameworks/CurlImpersonate.xcframework (iOS device, arm64) from the
# prebuilt libcurl-impersonate release (lexiforest/curl-impersonate, MIT):
# its self-contained dylib, renamed and wrapped as a framework.
set -euo pipefail

VERSION="v2.3.2"
SHA256="670e8d1c6c8ebd422b95bd25421ef9de3772bec4f9dfda95477a63c06c6596a5"
URL="https://github.com/lexiforest/curl-impersonate/releases/download/$VERSION/libcurl-impersonate-$VERSION.arm64-apple-ios.tar.gz"

HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/Frameworks"
CACHE="${CURL_IOS_CACHE:-$HERE/.cache}"
WORK="$HERE/.build"
NAME="CurlImpersonate"

mkdir -p "$CACHE"
TARBALL="$CACHE/libcurl-impersonate-$VERSION-ios.tar.gz"
if [ ! -f "$TARBALL" ]; then
  curl -fL --retry 5 --retry-delay 3 -o "$TARBALL.tmp" "$URL"
  mv "$TARBALL.tmp" "$TARBALL"
fi
if ! echo "$SHA256  $TARBALL" | shasum -a 256 -c - >/dev/null; then
  rm -f "$TARBALL"
  echo "error: checksum mismatch for $URL" >&2
  exit 1
fi

rm -rf "$WORK"
mkdir -p "$WORK/x" "$WORK/fw/$NAME.framework"
tar xzf "$TARBALL" -C "$WORK/x"
DYLIB="$(ls "$WORK"/x/libcurl-impersonate.*.*.*.dylib | head -1)"
FW="$WORK/fw/$NAME.framework"
cp "$DYLIB" "$FW/$NAME"
install_name_tool -id "@rpath/$NAME.framework/$NAME" "$FW/$NAME"
mkdir -p "$FW/licenses"
cp "$WORK"/x/LICENSE* "$FW/licenses/"

cat > "$FW/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.nivio.CurlImpersonate</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>${VERSION#v}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>iPhoneOS</string></array>
  <key>MinimumOSVersion</key><string>15.0</string>
</dict>
</plist>
PLIST

rm -rf "$OUT"
mkdir -p "$OUT"
xcodebuild -create-xcframework -framework "$FW" -output "$OUT/$NAME.xcframework"
rm -rf "$WORK"
echo "[curl] Built $OUT/$NAME.xcframework"
