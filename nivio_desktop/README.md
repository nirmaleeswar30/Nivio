# Nivio Desktop

Linux desktop build of Nivio.

## Download

Download the latest Linux desktop packages from:

https://github.com/NithishSaravananRss/Nivio/releases/tag/desktop-v1.0.0

Normal users should download one of the package files, not the source code
archives.

## Install

Portable Linux:

```bash
chmod +x Nivio-x86_64.AppImage
./Nivio-x86_64.AppImage
```

Ubuntu, Debian, Linux Mint, Kali, Pop!_OS, Zorin:

```bash
sudo apt install ./nivio-desktop_1.0.0_amd64.deb
```

Arch, Omarchy, Manjaro, EndeavourOS:

```bash
sudo pacman -U ./nivio-desktop-1.0.0-1-x86_64.pkg.tar.zst
```

## Build From Source

```bash
flutter pub get
flutter build linux --release
```

Packaging scripts:

```bash
scripts/package_appimage.sh
scripts/package_deb.sh
scripts/package_arch.sh
```

Flatpak packaging is prepared in `packaging/flatpak/`, but it is not included
in the first desktop release.
