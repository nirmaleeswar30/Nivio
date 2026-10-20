#!/usr/bin/env bash
# Build the Nivio Windows desktop release and package the Inno Setup installer.
#
# IMPORTANT: the Windows app is built from packages/nivio_desktop, NOT the repo
# root. The desktop package overrides google_sign_in / firebase_* with local
# stubs (the working browser-OAuth loopback login). The root build uses the real
# google_sign_in, which has no Windows implementation and fails at runtime with
# "UnimplementedError".
#
# Usage (from anywhere; run in Git Bash on Windows):
#   ./scripts/build_windows_installer.sh            # build + package
#   ./scripts/build_windows_installer.sh --skip-build   # package only (reuse last build)
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESKTOP_DIR="$PROJECT_ROOT/packages/nivio_desktop"
ISS="$PROJECT_ROOT/installer/nivio.iss"

SKIP_BUILD=0
[[ "${1:-}" == "--skip-build" ]] && SKIP_BUILD=1

if [[ ! -d "$DESKTOP_DIR" ]]; then
  echo "error: desktop package not found at $DESKTOP_DIR" >&2
  exit 1
fi

if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "🏗️  Building Windows release from packages/nivio_desktop ..."
  ( cd "$DESKTOP_DIR" && flutter build windows --release )
fi

RELEASE_DIR="$DESKTOP_DIR/build/windows/x64/runner/Release"
if [[ ! -f "$RELEASE_DIR/nivio.exe" ]]; then
  echo "error: build output not found ($RELEASE_DIR/nivio.exe). Run without --skip-build." >&2
  exit 1
fi

# Locate the Inno Setup 6 compiler (ISCC.exe).
ISCC="${ISCC_PATH:-}"
if [[ -z "$ISCC" ]]; then
  for c in \
    "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" \
    "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" \
    "/c/Program Files/Inno Setup 6/ISCC.exe"; do
    if [[ -f "$c" ]]; then ISCC="$c"; break; fi
  done
fi
if [[ -z "$ISCC" || ! -f "$ISCC" ]]; then
  echo "error: Inno Setup 6 (ISCC.exe) not found. Install it or set ISCC_PATH." >&2
  exit 1
fi

# Extract version dynamically from root pubspec.yaml or desktop pubspec.yaml
APP_VERSION="1.0.0"
if [[ -f "$PROJECT_ROOT/pubspec.yaml" ]]; then
  APP_VERSION=$(grep -E '^version:\s*(.+)$' "$PROJECT_ROOT/pubspec.yaml" | head -n 1 | sed -E 's/^version:\s*(.+)$/\1/' | cut -d'+' -f1 | tr -d '\r' | tr -d ' ')
elif [[ -f "$DESKTOP_DIR/pubspec.yaml" ]]; then
  APP_VERSION=$(grep -E '^version:\s*(.+)$' "$DESKTOP_DIR/pubspec.yaml" | head -n 1 | sed -E 's/^version:\s*(.+)$/\1/' | cut -d'+' -f1 | tr -d '\r' | tr -d ' ')
fi

echo "📦 Compiling installer ($ISS) for version $APP_VERSION ..."
"$ISCC" "/DMyAppVersion=$APP_VERSION" "$ISS"

echo "✅ Done. Installer is in $PROJECT_ROOT/dist/"
