#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Target directory is the desktop package
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/packages/nivio_desktop"

# Ensure shorebird is in PATH if installed in ~/.shorebird/bin
if ! command -v shorebird &>/dev/null; then
  if [ -x "$HOME/.shorebird/bin/shorebird" ]; then
    export PATH="$HOME/.shorebird/bin:$PATH"
  fi
fi

# Clean up any legacy backup files if present
rm -f pubspec.yaml.bak pubspec.lock.bak

echo "📥 Getting desktop dependencies..."
flutter pub get

# Apply Linux compatibility patches if target is linux
TARGET_PLATFORM="${1:-linux}"
ACTION="${2:-build}"
if [[ $# -gt 0 ]]; then
  shift 2 2>/dev/null || shift $#
fi
EXTRA_ARGS=("$@")

if [ "$TARGET_PLATFORM" = "linux" ]; then
  echo "🔧 Applying Linux compatibility patches..."
  dart run tool/patch_linux.dart
fi

if [ "$ACTION" = "run" ]; then
  echo "🚀 Running application on $TARGET_PLATFORM..."
  flutter run -d "$TARGET_PLATFORM" "${EXTRA_ARGS[@]}"
elif [ "$ACTION" = "run_profile" ]; then
  echo "🚀 Running application on $TARGET_PLATFORM in Profile Mode..."
  flutter run --profile -d "$TARGET_PLATFORM" "${EXTRA_ARGS[@]}"
elif [ "$ACTION" = "shorebird_release" ] || [ "$ACTION" = "shorebird_patch" ]; then
  if ! command -v shorebird &>/dev/null; then
    echo "❌ Shorebird CLI was not found. Please install Shorebird (https://docs.shorebird.dev)."
    exit 1
  fi

  echo "🔍 Verifying Shorebird credentials..."
  if ! shorebird apps list >/dev/null 2>&1; then
    echo "⚠️ Shorebird is not logged in or credentials have expired."
    echo "🔑 Launching 'shorebird login'..."
    shorebird login
    if [ $? -ne 0 ]; then
      echo "❌ Shorebird login was unsuccessful. Aborting."
      exit 1
    fi
  fi

  if [ "$ACTION" = "shorebird_release" ]; then
    FLUTTER_VER_ARG=""
    # Check if --flutter-version was passed in EXTRA_ARGS
    has_custom_flutter=0
    for arg in "${EXTRA_ARGS[@]}"; do
      if [[ "$arg" == --flutter-version* ]]; then
        has_custom_flutter=1
        break
      fi
    done

    if [ "$has_custom_flutter" -eq 0 ]; then
      APP_VERSION=$(grep "^version:" pubspec.yaml | awk '{print $2}' | tr -d '\r')
      if [ -n "$APP_VERSION" ]; then
        EXISTING_VER=$(shorebird releases list 2>/dev/null | grep -E "\b${APP_VERSION//+/\\+}\b" | awk '{print $NF}' | head -n 1)
        if [ -n "$EXISTING_VER" ]; then
          echo "ℹ️ Existing Shorebird release found for $APP_VERSION (Flutter $EXISTING_VER). Matching Flutter revision..."
          FLUTTER_VER_ARG="--flutter-version=$EXISTING_VER"
        fi
      fi
    fi

    echo "🦅 Building Shorebird release for $TARGET_PLATFORM..."
    shorebird release "$TARGET_PLATFORM" ${FLUTTER_VER_ARG:+"$FLUTTER_VER_ARG"} "${EXTRA_ARGS[@]}"
  else
    echo "🦅 Building Shorebird patch for $TARGET_PLATFORM..."
    shorebird patch "$TARGET_PLATFORM" "${EXTRA_ARGS[@]}"
  fi
else
  echo "🏗️ Building application for $TARGET_PLATFORM in Release mode..."
  flutter build "$TARGET_PLATFORM" --release "${EXTRA_ARGS[@]}"
fi
