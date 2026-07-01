#!/bin/bash
set -e

# Resolve repo root from script location
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"

# Configuration
TOOLS_DIR="$HOME/tools"
BUNDLETOOL_PATH="$TOOLS_DIR/bundletool.jar"
AAB_PATH="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
APKS_PATH="$REPO_ROOT/build/app/outputs/bundle/release/app-release.apks"
OUTPUT_DIR="$REPO_ROOT/build/app/outputs/bundle/release/apks"
PUBSPEC_PATH="$REPO_ROOT/pubspec.yaml"

# Debug keystore
KEYSTORE_PATH="/home/nirmal/.config/.android/debug.keystore"
KEY_ALIAS="androiddebugkey"
KEYSTORE_PASSWORD="android"
KEY_PASSWORD="android"

echo -e "\033[0;36m=== Nivio Universal APK Builder ===\033[0m\n"

# Check Java
echo -e "\033[0;33mChecking Java...\033[0m"
if type -p java > /dev/null; then
    JAVA_EXE="java"
elif [[ -n "$JAVA_HOME" ]] && [[ -x "$JAVA_HOME/bin/java" ]];  then
    JAVA_EXE="$JAVA_HOME/bin/java"
else
    echo -e "\033[0;31m  ERROR: Java not found.\033[0m"
    echo -e "\033[0;31m  Install JDK 17 or set JAVA_HOME to your JDK path.\033[0m"
    exit 1
fi

JAVA_VERSION=$("$JAVA_EXE" -version 2>&1 | head -n 1)
if [ $? -ne 0 ]; then
    echo -e "\033[0;31m  ERROR: Java was found but failed to run.\033[0m"
    exit 1
fi
echo -e "\033[0;32m  Found: $JAVA_VERSION\033[0m"

# Check bundletool
echo -e "\033[0;33mChecking bundletool...\033[0m"
if [ -f "$BUNDLETOOL_PATH" ]; then
    echo -e "\033[0;32m  Found: $BUNDLETOOL_PATH\033[0m"
else
    echo -e "\033[0;33m  Bundletool not found. Downloading...\033[0m"
    mkdir -p "$TOOLS_DIR"
    curl -L -o "$BUNDLETOOL_PATH" "https://github.com/google/bundletool/releases/download/1.17.2/bundletool-all-1.17.2.jar"
    echo -e "\033[0;32m  Downloaded to: $BUNDLETOOL_PATH\033[0m"
fi

# Check AAB file
echo -e "\033[0;33mChecking AAB file...\033[0m"
if [ -f "$AAB_PATH" ]; then
    AAB_SIZE=$(du -m "$AAB_PATH" | cut -f1)
    echo -e "\033[0;32m  Found: $AAB_PATH (${AAB_SIZE}MB)\033[0m"
else
    echo -e "\033[0;31m  ERROR: AAB not found at $AAB_PATH\033[0m"
    echo -e "\033[0;31m  Run 'shorebird release android' or 'flutter build appbundle' first.\033[0m"
    exit 1
fi

# Check keystore
echo -e "\033[0;33mChecking keystore...\033[0m"
if [ -f "$KEYSTORE_PATH" ]; then
    echo -e "\033[0;32m  Found: $KEYSTORE_PATH\033[0m"
else
    echo -e "\033[0;31m  ERROR: Debug keystore not found at $KEYSTORE_PATH\033[0m"
    exit 1
fi

# Create output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Extract Version
VERSION="unknown"
if [ -f "$PUBSPEC_PATH" ]; then
    VERSION=$(grep -E '^version:\s*(.+)$' "$PUBSPEC_PATH" | head -n 1 | sed -E 's/^version:\s*(.+)$/\1/' | tr -d '\r' | tr -d ' ')
fi
VERSION_SAFE=$(echo "$VERSION" | sed -E 's/[^a-zA-Z0-9.\+-]/_/g')

# Build Universal APK set
echo -e "\n\033[0;33mBuilding APK set (universal mode)...\033[0m"
"$JAVA_EXE" -jar "$BUNDLETOOL_PATH" build-apks \
    --bundle="$AAB_PATH" \
    --output="$OUTPUT_DIR/universal.apks" \
    --mode=universal \
    --ks="$KEYSTORE_PATH" \
    --ks-key-alias="$KEY_ALIAS" \
    --ks-pass="pass:$KEYSTORE_PASSWORD" \
    --key-pass="pass:$KEY_PASSWORD" \
    --overwrite || { echo -e "\033[0;31m  ERROR: Failed to build universal APK set\033[0m"; exit 1; }

# Extract Universal APK
echo -e "\n\033[0;33mExtracting Universal APK...\033[0m"
unzip -q "$OUTPUT_DIR/universal.apks" -d "$OUTPUT_DIR/universal_temp"
cp "$OUTPUT_DIR/universal_temp/universal.apk" "$OUTPUT_DIR/nivio-$VERSION_SAFE-universal.apk"
rm -rf "$OUTPUT_DIR/universal_temp" "$OUTPUT_DIR/universal.apks"

# Find Android Build Tools
echo -e "\n\033[0;33mLocating Android Build Tools...\033[0m"
BUILD_TOOLS_DIR=$(ls -d $HOME/Android/Sdk/build-tools/* | sort -V | tail -n 1)
ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

if [ ! -f "$ZIPALIGN" ] || [ ! -f "$APKSIGNER" ]; then
    echo -e "\033[0;31m  ERROR: zipalign or apksigner not found in $BUILD_TOOLS_DIR\033[0m"
    exit 1
fi
echo -e "\033[0;32m  Found: $BUILD_TOOLS_DIR\033[0m"

# Build Standalone arm64-v8a APK using Python stripper
echo -e "\n\033[0;33mBuilding Standalone arm64-v8a APK (Shorebird compatible)...\033[0m"
STRIPPED_APK="$OUTPUT_DIR/nivio-$VERSION_SAFE-unaligned.apk"
FINAL_ARM64_APK="$OUTPUT_DIR/nivio-$VERSION_SAFE.apk"

python3 "$REPO_ROOT/scripts/strip_apk.py" "$OUTPUT_DIR/nivio-$VERSION_SAFE-universal.apk" "$STRIPPED_APK" "arm64-v8a"

echo -e "  \033[0;33mAligning APK...\033[0m"
"$ZIPALIGN" -f -p 4 "$STRIPPED_APK" "$FINAL_ARM64_APK"

echo -e "  \033[0;33mSigning APK...\033[0m"
"$APKSIGNER" sign --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" --ks-pass "pass:$KEYSTORE_PASSWORD" --key-pass "pass:$KEY_PASSWORD" "$FINAL_ARM64_APK"

rm -f "$STRIPPED_APK"

echo -e "\n\033[0;32m=== SUCCESS ===\033[0m"
echo -e "\033[0;36mGenerated APKs in: $OUTPUT_DIR\033[0m\n"
ls -lh "$OUTPUT_DIR" | grep ".apk" | awk '{print "  " $9 " (" $5 ")"}'
echo -e "\n\033[0;37mUpload the APKs to GitHub Releases for Shorebird distribution.\033[0m"
