#!/bin/bash
# Builds Frameworks/RqbitEngine.xcframework from ../rust for iOS.
#
#   ./build_xcframework.sh            device (arm64) only
#   ./build_xcframework.sh --sim      device + simulator (arm64 + x86_64)
#
# Needs macOS with Xcode and rustup:
#   rustup target add aarch64-apple-ios [aarch64-apple-ios-sim x86_64-apple-ios]
#
# The Rust crate is a cdylib; each slice is wrapped as a dynamic
# RqbitEngine.framework whose install name is
# @rpath/RqbitEngine.framework/RqbitEngine, which CocoaPods embeds in
# Runner.app/Frameworks. (Not "rqbit_ffi": with use_frameworks! the plugin pod
# itself already produces a rqbit_ffi.framework.)
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
RUST_DIR="$HERE/../rust"
OUT="$HERE/Frameworks"
WORK="$HERE/.build"
MIN_IOS="${IPHONEOS_DEPLOYMENT_TARGET:-15.0}"
WITH_SIM=0
[ "${1:-}" = "--sim" ] && WITH_SIM=1

CARGO="cargo"
if ! command -v cargo >/dev/null 2>&1 && [ -x "$HOME/.cargo/bin/cargo" ]; then
  CARGO="$HOME/.cargo/bin/cargo"
fi
command -v "$CARGO" >/dev/null 2>&1 || [ -x "$CARGO" ] || {
  echo "error: cargo not found. Install Rust from https://rustup.rs" >&2
  exit 1
}
RUSTUP="rustup"
command -v rustup >/dev/null 2>&1 || RUSTUP="$HOME/.cargo/bin/rustup"

TARGETS=(aarch64-apple-ios)
[ $WITH_SIM = 1 ] && TARGETS+=(aarch64-apple-ios-sim x86_64-apple-ios)
"$RUSTUP" target add "${TARGETS[@]}" >/dev/null 2>&1 || true

# Xcode's build environment (when run from a script phase) can point Rust's
# cc/linker at the wrong SDK; build against the right one per target.
unset SDKROOT PLATFORM_NAME ARCHS

export IPHONEOS_DEPLOYMENT_TARGET="$MIN_IOS"
NAME="RqbitEngine"
INSTALL_NAME="@rpath/$NAME.framework/$NAME"

for T in "${TARGETS[@]}"; do
  echo "[rqbit_ffi] cargo build --release --target $T"
  RUSTFLAGS="-C link-arg=-Wl,-install_name,$INSTALL_NAME" \
    "$CARGO" build --release --lib --manifest-path "$RUST_DIR/Cargo.toml" --target "$T"
done

make_framework() {
  local dylib="$1" dest="$2" platform="$3"
  rm -rf "$dest"
  mkdir -p "$dest"
  cp "$dylib" "$dest/$NAME"
  install_name_tool -id "$INSTALL_NAME" "$dest/$NAME"
  cat > "$dest/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>com.nivio.RqbitEngine</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleSupportedPlatforms</key><array><string>$platform</string></array>
  <key>MinimumOSVersion</key><string>$MIN_IOS</string>
</dict>
</plist>
PLIST
}

TGT="$RUST_DIR/target"
rm -rf "$WORK"
mkdir -p "$WORK"
make_framework "$TGT/aarch64-apple-ios/release/librqbit_ffi.dylib" "$WORK/ios/$NAME.framework" iPhoneOS
ARGS=(-framework "$WORK/ios/$NAME.framework")

if [ $WITH_SIM = 1 ]; then
  mkdir -p "$WORK/sim"
  lipo -create \
    "$TGT/aarch64-apple-ios-sim/release/librqbit_ffi.dylib" \
    "$TGT/x86_64-apple-ios/release/librqbit_ffi.dylib" \
    -output "$WORK/sim/librqbit_ffi.dylib"
  make_framework "$WORK/sim/librqbit_ffi.dylib" "$WORK/sim/$NAME.framework" iPhoneSimulator
  ARGS+=(-framework "$WORK/sim/$NAME.framework")
fi

rm -rf "$OUT/rqbit_ffi.xcframework" "$OUT/$NAME.xcframework"
mkdir -p "$OUT"
xcodebuild -create-xcframework "${ARGS[@]}" -output "$OUT/$NAME.xcframework"
rm -rf "$WORK"
echo "[rqbit_ffi] Built $OUT/$NAME.xcframework"
