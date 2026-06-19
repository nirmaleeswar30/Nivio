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

# Build APK set
echo -e "\n\033[0;33mBuilding APK set (universal mode)...\033[0m"
"$JAVA_EXE" -jar "$BUNDLETOOL_PATH" build-apks \
    --bundle="$AAB_PATH" \
    --output="$APKS_PATH" \
    --mode=universal \
    --ks="$KEYSTORE_PATH" \
    --ks-key-alias="$KEY_ALIAS" \
    --ks-pass="pass:$KEYSTORE_PASSWORD" \
    --key-pass="pass:$KEY_PASSWORD" \
    --overwrite || { echo -e "\033[0;31m  ERROR: Failed to build APK set\033[0m"; exit 1; }

echo -e "\033[0;32m  APK set created: $APKS_PATH\033[0m"

# Extract universal APK
echo -e "\n\033[0;33mExtracting universal APK...\033[0m"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

unzip -q "$APKS_PATH" -d "$OUTPUT_DIR"

UNIVERSAL_APK="$OUTPUT_DIR/universal.apk"
if [ -f "$UNIVERSAL_APK" ]; then
    APK_SIZE=$(du -m "$UNIVERSAL_APK" | cut -f1)
    echo -e "\033[0;32m  Extracted: $UNIVERSAL_APK (${APK_SIZE}MB)\033[0m"
else
    echo -e "\033[0;31m  ERROR: universal.apk not found in extracted files\033[0m"
    exit 1
fi

# Create versioned copy
VERSION="unknown"
if [ -f "$PUBSPEC_PATH" ]; then
    VERSION=$(grep -E '^version:\s*(.+)$' "$PUBSPEC_PATH" | head -n 1 | sed -E 's/^version:\s*(.+)$/\1/' | tr -d '\r' | tr -d ' ')
fi

VERSION_SAFE=$(echo "$VERSION" | sed -E 's/[^a-zA-Z0-9.\+-]/_/g')
VERSIONED_APK="$OUTPUT_DIR/nivio-$VERSION_SAFE-universal.apk"

cp "$UNIVERSAL_APK" "$VERSIONED_APK"

echo -e "\n\033[0;32m=== SUCCESS ===\033[0m"
echo -e "\033[0;36mUniversal APK: $UNIVERSAL_APK\033[0m"
echo -e "\033[0;36mVersioned APK: $VERSIONED_APK\033[0m"
echo -e "\033[0;36mSize: ${APK_SIZE}MB\033[0m\n"
echo -e "\033[0;37mUpload the APK to GitHub Releases for Shorebird distribution.\033[0m"
