#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Target directory is the project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "⚙️ Setting up desktop compilation overrides..."

# Self-healing: if backup exists from a previous crashed run, restore it first!
if [ -f pubspec.yaml.bak ]; then
  echo "🩹 Restoring previous pubspec.yaml.bak..."
  mv pubspec.yaml.bak pubspec.yaml
fi
if [ -f pubspec.lock.bak ]; then
  mv pubspec.lock.bak pubspec.lock
fi

# Back up pubspec.yaml and pubspec.lock
cp pubspec.yaml pubspec.yaml.bak
cp pubspec.lock pubspec.lock.bak

# Function to clean up/restore files on exit
cleanup() {
  echo "🧹 Restoring original pubspec.yaml and pubspec.lock..."
  if [ -f pubspec.yaml.bak ]; then
    mv pubspec.yaml.bak pubspec.yaml
  fi
  if [ -f pubspec.lock.bak ]; then
    mv pubspec.lock.bak pubspec.lock
  fi
  flutter pub get
}
trap cleanup EXIT

# Append overrides to pubspec.yaml
cat << 'EOF' >> pubspec.yaml

dependency_overrides:
  firebase_core:
    path: ./packages/stubs/firebase_core
  firebase_auth:
    path: ./packages/stubs/firebase_auth
  cloud_firestore:
    path: ./packages/stubs/cloud_firestore
  google_sign_in:
    path: ./packages/stubs/google_sign_in
EOF

echo "📥 Getting local stub dependencies..."
flutter pub get

# Default target is linux, but allow overriding via args
TARGET_PLATFORM="${1:-linux}"
ACTION="${2:-build}"

if [ "$ACTION" = "run" ]; then
  echo "🚀 Running application on $TARGET_PLATFORM..."
  flutter run -d "$TARGET_PLATFORM"
else
  echo "🏗️ Building application for $TARGET_PLATFORM..."
  flutter build "$TARGET_PLATFORM" --debug
fi
