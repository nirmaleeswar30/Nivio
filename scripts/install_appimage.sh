#!/bin/bash

# Exit on error
set -e

# AppImages are meant to be user-local, so we don't need sudo!
APP_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$HOME/.local/share/applications"

mkdir -p "$APP_DIR"
mkdir -p "$ICON_DIR"
mkdir -p "$DESKTOP_DIR"

APP_BIN="$APP_DIR/Nivio.AppImage"

if [ -z "$1" ]; then
  echo "🌐 Downloading the latest Nivio AppImage from GitHub..."
  if ! curl -f -L "https://github.com/nirmaleeswar30/Nivio/releases/latest/download/Nivio-Linux-x86_64.AppImage" -o "$APP_BIN"; then
    echo "❌ Failed to download the AppImage."
    exit 1
  fi
else
  if [ ! -f "$1" ]; then
    echo "❌ Could not find local AppImage: $1"
    exit 1
  fi
  echo "📦 Copying local AppImage to $APP_BIN..."
  cp "$1" "$APP_BIN"
fi

chmod +x "$APP_BIN"

echo "🖼️ Downloading Nivio icon..."
curl -sL "https://raw.githubusercontent.com/nirmaleeswar30/Nivio/main/assets/images/nivio.png" -o "$ICON_DIR/nivio.png"

echo "🖥️ Generating Desktop Entry..."
cat << EOF > "$DESKTOP_DIR/nivio.desktop"
[Desktop Entry]
Type=Application
Name=Nivio
Comment=Stream movies, TV shows, and anime
GenericName=Media Player
Exec=$APP_BIN %u
Icon=nivio
Terminal=false
Categories=AudioVideo;Video;Player;
MimeType=x-scheme-handler/nivio;
StartupNotify=true
StartupWMClass=nivio
EOF

chmod +x "$DESKTOP_DIR/nivio.desktop"

# Refresh desktop database so it shows up instantly (if available)
if command -v update-desktop-database &> /dev/null; then
  update-desktop-database "$DESKTOP_DIR"
fi

echo "✅ Nivio AppImage installed successfully!"
echo "You can now launch it from your application menu!"
