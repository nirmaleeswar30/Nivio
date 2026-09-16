/// rqbit_ffi — embedded BitTorrent streaming engine for Nivio.
///
/// Boots `librqbit` via a tiny FFI bootstrap and exposes its localhost HTTP API
/// as a typed Dart client. Hand [RqbitClient.streamUrl] to media_kit to play a
/// torrent file while it downloads (sequential, byte-range/seek capable).
library rqbit_ffi;

export 'src/rqbit_engine.dart';
export 'src/rqbit_client.dart';
export 'src/models.dart';
export 'src/torrent_foreground_service.dart';
