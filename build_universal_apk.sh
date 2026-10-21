#!/usr/bin/env bash
# Build Universal and Split APKs from AAB using bundletool
# Usage: ./build_universal_apk.sh [--shorebird | --normal | --skip-build] [--force]
set -euo pipefail

# Resolve repo root from script location
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
MOBILE_DIR="$REPO_ROOT/packages/nivio_mobile"
AAB_PATH="$MOBILE_DIR/build/app/outputs/bundle/release/app-release.aab"
OUTPUT_DIR="$MOBILE_DIR/build/app/outputs/bundle/release/apks"
PUBSPEC_PATH="$MOBILE_DIR/pubspec.yaml"

# Configuration
TOOLS_DIR="${TOOLS_DIR:-$HOME/tools}"
BUNDLETOOL_PATH="${BUNDLETOOL_PATH:-$TOOLS_DIR/bundletool.jar}"

# Debug keystore
KEYSTORE_PATH=""
if [ -f "$HOME/.android/debug.keystore" ]; then
    KEYSTORE_PATH="$HOME/.android/debug.keystore"
elif [ -f "$HOME/.config/.android/debug.keystore" ]; then
    KEYSTORE_PATH="$HOME/.config/.android/debug.keystore"
elif [ -n "${USERPROFILE:-}" ] && [ -f "$USERPROFILE/.android/debug.keystore" ]; then
    KEYSTORE_PATH="$USERPROFILE/.android/debug.keystore"
else
    KEYSTORE_PATH="$HOME/.android/debug.keystore"
fi
KEY_ALIAS="androiddebugkey"
KEYSTORE_PASSWORD="android"
KEY_PASSWORD="android"

BUILD_TYPE=""
SKIP_BUILD=0
FORCE_FLAG=""

for arg in "$@"; do
    case "$arg" in
        --shorebird)
            BUILD_TYPE="shorebird"
            ;;
        --normal)
            BUILD_TYPE="normal"
            ;;
        --skip-build)
            SKIP_BUILD=1
            ;;
        --force)
            FORCE_FLAG="--force"
            ;;
        *)
            ;;
    esac
done

echo -e "\033[0;36m=== Nivio Universal APK Builder ===\033[0m\n"

# Prompt for build type if not specified and not skipping
if [ "$SKIP_BUILD" -eq 0 ] && [ -z "$BUILD_TYPE" ]; then
    if [ -t 0 ]; then
        echo -e "\033[0;36mSelect Android Release Type:\033[0m"
        echo "  [1] Shorebird Release (Enables Over-the-Air Dart code pushes)"
        echo "  [2] Normal Release (Standard Flutter AAB build)"
        echo "  [3] Skip Build (Only bundle APKs from existing AAB)"
        read -r -p "Enter choice [1, 2, or 3] (Default: 1): " choice
        case "$choice" in
            2)
                BUILD_TYPE="normal"
                ;;
            3)
                SKIP_BUILD=1
                ;;
            *)
                BUILD_TYPE="shorebird"
                ;;
        esac
    else
        BUILD_TYPE="shorebird"
    fi
fi

# Step 1: Build AAB
if [ "$SKIP_BUILD" -eq 0 ]; then
    if [ ! -d "$MOBILE_DIR" ]; then
        echo "error: mobile package not found at $MOBILE_DIR" >&2
        exit 1
    fi

    if [ "$BUILD_TYPE" = "shorebird" ]; then
        echo -e "\033[0;33mChecking Shorebird CLI...\033[0m"
        if ! command -v shorebird &> /dev/null; then
            echo "error: shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev)." >&2
            exit 1
        fi

        echo -e "\033[0;33mVerifying Shorebird credentials...\033[0m"
        APPS_OUTPUT=$(shorebird apps list 2>&1 || true)
        if echo "$APPS_OUTPUT" | grep -qE "shorebird login|rejected your stored credentials|Failed to refresh credentials"; then
            echo "Shorebird credentials expired or not logged in. Launching 'shorebird login'..."
            shorebird login
        fi

        echo -e "\n\033[0;32mBuilding Shorebird Android Release (AAB + OTA)...\033[0m"
        ( cd "$MOBILE_DIR" && shorebird release android --artifact=aab $FORCE_FLAG )
    else
        echo -e "\n\033[0;36mBuilding Standard Flutter Android Release (AAB)...\033[0m"
        ( cd "$MOBILE_DIR" && flutter build appbundle --release )
    fi
fi

# Check Java
echo -e "\033[0;33mChecking Java...\033[0m"
if type -p java > /dev/null; then
    JAVA_EXE="java"
elif [[ -n "${JAVA_HOME:-}" ]] && [[ -x "$JAVA_HOME/bin/java" ]]; then
    JAVA_EXE="$JAVA_HOME/bin/java"
elif [[ -x "/opt/android-studio/jbr/bin/java" ]]; then
    JAVA_EXE="/opt/android-studio/jbr/bin/java"
else
    echo -e "\033[0;31m  ERROR: Java not found.\033[0m"
    echo -e "\033[0;31m  Install JDK 17 or set JAVA_HOME to your JDK path.\033[0m"
    exit 1
fi

JAVA_VERSION=$("$JAVA_EXE" -version 2>&1 | head -n 1)
echo -e "\033[0;32m  Found: $JAVA_VERSION\033[0m"

# Check bundletool
echo -e "\033[0;33mChecking bundletool...\033[0m"
if [ -f "$BUNDLETOOL_PATH" ]; then
    echo -e "\033[0;32m  Found: $BUNDLETOOL_PATH\033[0m"
else
    echo -e "\033[0;33m  Bundletool not found. Downloading...\033[0m"
    mkdir -p "$(dirname "$BUNDLETOOL_PATH")"
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
    echo -e "\033[0;31m  Run without --skip-build to compile the AAB first.\033[0m"
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

# Prepare output directory
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# Extract Version (prefer root pubspec.yaml if present)
VERSION="unknown"
if [ -f "$REPO_ROOT/pubspec.yaml" ]; then
    VERSION=$(grep -E '^version:\s*(.+)$' "$REPO_ROOT/pubspec.yaml" | head -n 1 | sed -E 's/^version:\s*(.+)$/\1/' | tr -d '\r' | tr -d ' ')
elif [ -f "$PUBSPEC_PATH" ]; then
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
    --overwrite

# Extract Universal APK
echo -e "\n\033[0;33mExtracting Universal APK...\033[0m"
unzip -q "$OUTPUT_DIR/universal.apks" -d "$OUTPUT_DIR/universal_temp"
cp "$OUTPUT_DIR/universal_temp/universal.apk" "$OUTPUT_DIR/nivio-$VERSION_SAFE-universal.apk"
rm -rf "$OUTPUT_DIR/universal_temp"
rm -f "$OUTPUT_DIR/universal.apks"

# Locate Android Build Tools & Python
BUILD_TOOLS_DIR=""
for candidate in "$ANDROID_HOME/build-tools" "$ANDROID_SDK_ROOT/build-tools" "$HOME/Android/Sdk/build-tools" "$HOME/Library/Android/sdk/build-tools"; do
    if [ -d "$candidate" ]; then
        latest=$(ls -d "$candidate"/* 2>/dev/null | sort -V | tail -n 1)
        if [ -f "$latest/zipalign" ] && [ -f "$latest/apksigner" ]; then
            BUILD_TOOLS_DIR="$latest"
            break
        fi
    fi
done

PYTHON_EXE=""
for py in python3 python py; do
    if command -v "$py" &>/dev/null; then
        PYTHON_EXE="$py"
        break
    fi
done

STRIP_SCRIPT="$REPO_ROOT/scripts/strip_apk.py"
UNIVERSAL_APK="$OUTPUT_DIR/nivio-$VERSION_SAFE-universal.apk"

if [ -n "$PYTHON_EXE" ] && [ -n "$BUILD_TOOLS_DIR" ] && [ -f "$STRIP_SCRIPT" ]; then
    echo -e "\n\033[0;33mBuilding Architecture-Specific Split APKs (Shorebird compatible)...\033[0m"
    echo -e "\033[0;32m  Found Python: $PYTHON_EXE\033[0m"
    echo -e "\033[0;32m  Found Build Tools: $BUILD_TOOLS_DIR\033[0m"
    ZIPALIGN="$BUILD_TOOLS_DIR/zipalign"
    APKSIGNER="$BUILD_TOOLS_DIR/apksigner"

    # arm64-v8a
    echo -e "  \033[0;33mProcessing arm64-v8a...\033[0m"
    "$PYTHON_EXE" "$STRIP_SCRIPT" "$UNIVERSAL_APK" "$OUTPUT_DIR/arm64-unaligned.apk" "arm64-v8a"
    "$ZIPALIGN" -f -p 4 "$OUTPUT_DIR/arm64-unaligned.apk" "$OUTPUT_DIR/nivio-$VERSION_SAFE.apk"
    "$APKSIGNER" sign --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" --ks-pass "pass:$KEYSTORE_PASSWORD" --key-pass "pass:$KEY_PASSWORD" "$OUTPUT_DIR/nivio-$VERSION_SAFE.apk"
    rm -f "$OUTPUT_DIR/arm64-unaligned.apk"

    # armeabi-v7a
    echo -e "  \033[0;33mProcessing armeabi-v7a...\033[0m"
    "$PYTHON_EXE" "$STRIP_SCRIPT" "$UNIVERSAL_APK" "$OUTPUT_DIR/armv7-unaligned.apk" "armeabi-v7a"
    "$ZIPALIGN" -f -p 4 "$OUTPUT_DIR/armv7-unaligned.apk" "$OUTPUT_DIR/nivio-$VERSION_SAFE-armeabi-v7a.apk"
    "$APKSIGNER" sign --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" --ks-pass "pass:$KEYSTORE_PASSWORD" --key-pass "pass:$KEY_PASSWORD" "$OUTPUT_DIR/nivio-$VERSION_SAFE-armeabi-v7a.apk"
    rm -f "$OUTPUT_DIR/armv7-unaligned.apk"

    # x86_64
    echo -e "  \033[0;33mProcessing x86_64...\033[0m"
    "$PYTHON_EXE" "$STRIP_SCRIPT" "$UNIVERSAL_APK" "$OUTPUT_DIR/x86_64-unaligned.apk" "x86_64"
    "$ZIPALIGN" -f -p 4 "$OUTPUT_DIR/x86_64-unaligned.apk" "$OUTPUT_DIR/nivio-$VERSION_SAFE-x86_64.apk"
    "$APKSIGNER" sign --ks "$KEYSTORE_PATH" --ks-key-alias "$KEY_ALIAS" --ks-pass "pass:$KEYSTORE_PASSWORD" --key-pass "pass:$KEY_PASSWORD" "$OUTPUT_DIR/nivio-$VERSION_SAFE-x86_64.apk"
    rm -f "$OUTPUT_DIR/x86_64-unaligned.apk"
    rm -f "$OUTPUT_DIR/"*.idsig
else
    echo -e "\n\033[0;33mNotice: Python or Android SDK build-tools not found; skipping architecture-specific split APKs.\033[0m"
fi

echo -e "\n\033[0;32m=== SUCCESS ===\033[0m"
echo -e "\033[0;36mGenerated APKs in: $OUTPUT_DIR\033[0m"
for apk in "$OUTPUT_DIR/"*.apk; do
    [ -e "$apk" ] || continue
    size=$(du -m "$apk" | cut -f1)
    echo "  $(basename "$apk") (${size}MB)"
done
echo -e "\nUpload the APKs to GitHub Releases for distribution."
