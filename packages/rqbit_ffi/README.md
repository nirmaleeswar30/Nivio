# rqbit_ffi

Embedded [rqbit](https://github.com/ikatson/rqbit) (`librqbit`) BitTorrent
**streaming** engine for Nivio, driven from Dart. This is the engine behind the
**"Nivio Torrents"** anime provider (a Hayase-style P2P streaming path).

## How it works

```
Dart (RqbitEngine)  --FFI-->  rqbit_ffi native lib (Rust)  -->  librqbit
      │                         starts rqbit's HTTP API on 127.0.0.1:<port>
      │
      └── RqbitClient (HTTP) ──> add magnet → pick file → GET /stream (Range)
                                                              │
                                                     media_kit plays the URL
```

- **One FFI call** boots the engine (`rqbit_start(port, dir)` / `rqbit_stop()`),
  everything else is plain HTTP against rqbit's localhost API.
- rqbit provides magnet+metadata (BEP9), DHT, HTTP/UDP trackers, PEX, TCP+uTP,
  per-file selection, and a **sequential streaming HTTP server with byte-range
  seek** — which streams straight into `media_kit`.

## Layout

- `rust/` — the Rust wrapper crate (`crate-type = cdylib`). Depends on
  `librqbit` with features `http-api`, `tracing-subscriber-utils`, `rust-tls`
  (rustls, so no OpenSSL cross-compile pain).
- `lib/` — Dart: `RqbitEngine` (lifecycle), `RqbitClient` (typed HTTP), models.
- `windows/`, `linux/` — CMake that runs `cargo build` and bundles the lib.
- `android/` — Gradle that runs `cargo ndk` into `jniLibs/<abi>/`.
- `example/` — a media_kit player demo (paste a magnet, or stream a local file).

## Prerequisites

- **Rust** (rustup). The build finds `cargo` on PATH or in `~/.cargo/bin`.
- **Android**: `rustup target add aarch64-linux-android armv7-linux-androideabi
  x86_64-linux-android` and `cargo install cargo-ndk`; an installed NDK.
- **Desktop**: a C/C++ toolchain (MSVC on Windows; gcc/clang on Linux) — already
  required by Flutter desktop.

## Build

Native libs are built automatically when the host Flutter app builds
(`flutter build windows|linux|apk`) via the platform CMake/Gradle wiring. The
CMake defaults to a **debug** cargo build for fast iteration
(`-DRQBIT_CARGO_PROFILE=release` for shipping); Android defaults to **release**
(`-PrqbitDebug=true` for fast debug builds).

To try the demo:

```bash
cd example
flutter run -d windows   # or -d <android-device>
```

## Notes

- The engine caches torrent data under the app cache dir
  (`nivio_torrents/`); call `RqbitClient.forget`/`delete` to release torrents.
- P2P needs real network access. Sandboxed/UDP-blocked environments will fail to
  discover peers even though the HTTP/stream layer works.
