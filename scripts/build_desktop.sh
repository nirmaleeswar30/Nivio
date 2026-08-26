#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Target directory is the desktop package
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT/packages/nivio_desktop"

# Clean up any legacy backup files if present
rm -f pubspec.yaml.bak pubspec.lock.bak

echo "📥 Getting desktop dependencies..."
flutter pub get

# Default target is linux, but allow overriding via args
TARGET_PLATFORM="${1:-linux}"
ACTION="${2:-build}"

if [ "$ACTION" = "run" ]; then
  echo "🚀 Running application on $TARGET_PLATFORM..."
  flutter run -d "$TARGET_PLATFORM"
elif [ "$ACTION" = "run_profile" ]; then
  echo "🚀 Running application on $TARGET_PLATFORM in Profile Mode..."
  flutter run --profile -d "$TARGET_PLATFORM"
elif [ "$ACTION" = "shorebird_release" ]; then
  echo "🦅 Building Shorebird release for $TARGET_PLATFORM..."
  shorebird release "$TARGET_PLATFORM"
elif [ "$ACTION" = "shorebird_patch" ]; then
  echo "🦅 Building Shorebird patch for $TARGET_PLATFORM..."
  shorebird patch "$TARGET_PLATFORM"
else
  echo "🏗️ Building application for $TARGET_PLATFORM in Release mode..."
  flutter build "$TARGET_PLATFORM" --release
fi
