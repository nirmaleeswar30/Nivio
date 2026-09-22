import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:hive/hive.dart';

import 'package:nivio/core/debug_log.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/m3u8_parser.dart';

/// A tiny localhost HTTP server that serves a *still-downloading* direct video
/// file straight off disk, so it can be watched while it downloads (reusing the
/// exact bytes being written — no re-fetching from the source).
///
/// It understands both shapes the direct downloader produces:
/// - a single contiguous file at `savePath` (sequential download / after merge), and
/// - parallel `savePath.part0..partN` chunk files (which map cleanly onto byte
///   offsets, since chunk `i` holds bytes `[i*chunkSize, (i+1)*chunkSize)`).
///
/// Range requests are honoured, and when the player asks for bytes that haven't
/// been downloaded yet the response simply waits until they arrive (or the
/// download stops), which is what makes it feel like a live stream.
///
/// Note: this only helps progressive/faststart MP4s (moov atom at the front).
/// A file whose moov is at the end won't be playable until it fully downloads.
class LocalStreamServer {
  LocalStreamServer._();
  static final LocalStreamServer instance = LocalStreamServer._();

  HttpServer? _server;
  int? _port;

  static const String _boxName = 'downloads';

  // Active HLS sessions (id -> segment/key metadata), registered by the HLS
  // downloader while it runs so the segments already on disk can be served as a
  // growing local playlist that the player decrypts/muxes itself.
  final Map<String, _HlsSession> _hls = {};

  /// Registers an in-progress HLS download so it can be streamed off disk.
  void registerHls({
    required String id,
    required String tempDir,
    required List<M3u8Segment> video,
    required List<M3u8Segment> audio,
    required Map<String, String> localKeys,
  }) {
    _hls[id] = _HlsSession(tempDir, video, audio, localKeys);
    appDebugLog('[LocalStreamServer] registered HLS session $id '
        '(${video.length} video, ${audio.length} audio segs)');
  }

  void unregisterHls(String id) {
    _hls.remove(id);
  }

  /// URL that plays an in-progress HLS download, or null if not registered.
  Future<String?> hlsUrlFor(String id) async {
    final s = _hls[id];
    if (s == null) return null;
    final port = await _ensureStarted();
    if (port == null) return null;
    final base = 'http://127.0.0.1:$port/hls/$id';
    return s.audio.isNotEmpty ? '$base/master.m3u8' : '$base/v.m3u8';
  }

  /// Ensures the server is running and returns the URL that plays [downloadId].
  /// Returns null if the server can't be started.
  Future<String?> urlFor(String downloadId) async {
    final port = await _ensureStarted();
    if (port == null) return null;
    return 'http://127.0.0.1:$port/d/$downloadId';
  }

  Future<int?> _ensureStarted() async {
    if (_server != null && _port != null) return _port;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      appDebugLog('[LocalStreamServer] listening on 127.0.0.1:$_port');
      _server!.listen(_handle, onError: (e) {
        appDebugLog('[LocalStreamServer] listen error: $e');
      });
      return _port;
    } catch (e) {
      appDebugLog('[LocalStreamServer] failed to start: $e');
      _server = null;
      _port = null;
      return null;
    }
  }

  DownloadItem? _lookup(String id) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final box = Hive.box<DownloadItem>(_boxName);
    for (final i in box.values) {
      if (i.id == id) return i;
    }
    return null;
  }

  Future<void> _handle(HttpRequest request) async {
    final response = request.response;
    try {
      final segments = request.uri.pathSegments;
      if (segments.length >= 2 && segments[0] == 'hls') {
        await _handleHls(response, segments);
        return;
      }
      if (segments.length < 2 || segments[0] != 'd') {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      final id = Uri.decodeComponent(segments[1]);
      final item = _lookup(id);
      if (item == null || item.savePath.isEmpty) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }

      final filePath = item.savePath;
      final totalBytes = item.totalBytes;
      if (totalBytes <= 0) {
        // Size unknown — we can't range-serve reliably.
        response.statusCode = HttpStatus.serviceUnavailable;
        await response.close();
        return;
      }

      // Parse an optional Range header (bytes=start-end).
      int start = 0;
      int end = totalBytes - 1;
      final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
      final isPartial = rangeHeader != null && rangeHeader.startsWith('bytes=');
      if (isPartial) {
        final spec = rangeHeader.substring('bytes='.length).split('-');
        start = int.tryParse(spec[0]) ?? 0;
        if (spec.length > 1 && spec[1].trim().isNotEmpty) {
          end = int.tryParse(spec[1]) ?? (totalBytes - 1);
        }
      }
      if (start < 0) start = 0;
      if (end > totalBytes - 1) end = totalBytes - 1;
      if (start > end) {
        response.statusCode = HttpStatus.requestedRangeNotSatisfiable;
        await response.close();
        return;
      }

      response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
      response.headers.contentType = ContentType('video', 'mp4');
      if (isPartial) {
        response.statusCode = HttpStatus.partialContent;
        response.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$totalBytes',
        );
      } else {
        response.statusCode = HttpStatus.ok;
      }
      response.headers.set(HttpHeaders.contentLengthHeader, '${end - start + 1}');

      await _streamRange(response, filePath, id, totalBytes, start, end);
    } catch (e) {
      appDebugLog('[LocalStreamServer] request error: $e');
      try {
        await response.close();
      } catch (_) {}
    }
  }

  Future<void> _streamRange(
    HttpResponse response,
    String filePath,
    String id,
    int totalBytes,
    int start,
    int end,
  ) async {
    var pos = start;
    var clientGone = false;

    while (pos <= end && !clientGone) {
      final available = _availableContiguous(filePath, totalBytes);

      if (pos >= available) {
        // Bytes not downloaded yet. Stop if the download is over/dead.
        final item = _lookup(id);
        final status = item?.status;
        final finished = status == DownloadStatus.completed ||
            (available >= totalBytes);
        if (finished) break;
        if (item == null ||
            status == DownloadStatus.failed ||
            status == DownloadStatus.paused) {
          break;
        }
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }

      final readEnd = min(end, available - 1);
      final want = readEnd - pos + 1;
      final bytes = await _readChunkAt(filePath, totalBytes, pos, want);
      if (bytes == null) {
        // File not readable (e.g. mid-merge) — brief wait then retry.
        await Future.delayed(const Duration(milliseconds: 250));
        continue;
      }
      if (bytes.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 150));
        continue;
      }

      try {
        response.add(bytes);
        await response.flush();
      } catch (_) {
        clientGone = true;
        break;
      }
      pos += bytes.length;
    }

    try {
      await response.close();
    } catch (_) {}
  }

  /// Number of contiguous bytes available from offset 0.
  int _availableContiguous(String filePath, int totalBytes) {
    int chunkCount = 0;
    while (File('$filePath.part$chunkCount').existsSync()) {
      chunkCount++;
    }
    if (chunkCount == 0) {
      final f = File(filePath);
      return f.existsSync() ? f.lengthSync() : 0;
    }
    final chunkSize = (totalBytes / chunkCount).ceil();
    int contiguous = 0;
    for (int i = 0; i < chunkCount; i++) {
      final expected =
          (i == chunkCount - 1) ? totalBytes - i * chunkSize : chunkSize;
      final pf = File('$filePath.part$i');
      final len = pf.existsSync() ? pf.lengthSync() : 0;
      if (len >= expected) {
        contiguous += expected;
      } else {
        contiguous += len;
        break;
      }
    }
    return contiguous;
  }

  /// Reads up to [maxLen] bytes starting at global offset [pos], mapping the
  /// offset onto the single file or the correct `.part` chunk. Returns null on
  /// a transient read failure, an empty list if nothing is available there yet.
  Future<List<int>?> _readChunkAt(
    String filePath,
    int totalBytes,
    int pos,
    int maxLen,
  ) async {
    try {
      int chunkCount = 0;
      while (File('$filePath.part$chunkCount').existsSync()) {
        chunkCount++;
      }

      if (chunkCount == 0) {
        final f = File(filePath);
        if (!f.existsSync()) return null;
        final raf = await f.open();
        try {
          final len = await raf.length();
          if (pos >= len) return <int>[];
          await raf.setPosition(pos);
          final toRead = min(maxLen, len - pos);
          return await raf.read(toRead);
        } finally {
          await raf.close();
        }
      }

      final chunkSize = (totalBytes / chunkCount).ceil();
      final partIndex = pos ~/ chunkSize;
      if (partIndex >= chunkCount) return <int>[];
      final within = pos - partIndex * chunkSize;
      final pf = File('$filePath.part$partIndex');
      if (!pf.existsSync()) return <int>[];
      final raf = await pf.open();
      try {
        final len = await raf.length();
        if (within >= len) return <int>[];
        await raf.setPosition(within);
        final partRemaining = chunkSize - within;
        final toRead = min(min(maxLen, partRemaining), len - within);
        return await raf.read(toRead);
      } finally {
        await raf.close();
      }
    } catch (_) {
      return null;
    }
  }

  // ————————————————————————————————————————————————————— HLS ————————————————
  Future<void> _handleHls(HttpResponse response, List<String> segments) async {
    final id = Uri.decodeComponent(segments[1]);
    final session = _hls[id];
    if (session == null) {
      response.statusCode = HttpStatus.notFound;
      await response.close();
      return;
    }
    final rest = segments.sublist(2);

    // Serve a raw segment (.ts) or key file from the temp dir.
    if (rest.length == 2 && (rest[0] == 'seg' || rest[0] == 'key')) {
      final name = Uri.decodeComponent(rest[1]);
      if (name.contains('/') || name.contains('\\') || name.contains('..')) {
        response.statusCode = HttpStatus.forbidden;
        await response.close();
        return;
      }
      final file = File('${session.tempDir}/$name');
      if (!file.existsSync()) {
        response.statusCode = HttpStatus.notFound;
        await response.close();
        return;
      }
      response.headers.contentType = rest[0] == 'seg'
          ? ContentType('video', 'mp2t')
          : ContentType('application', 'octet-stream');
      try {
        await response.addStream(file.openRead());
      } catch (_) {}
      try {
        await response.close();
      } catch (_) {}
      return;
    }

    final base = 'http://127.0.0.1:${_port ?? 0}/hls/$id';

    if (rest.length == 1 && rest[0] == 'master.m3u8') {
      final sb = StringBuffer()
        ..writeln('#EXTM3U')
        ..writeln('#EXT-X-VERSION:3');
      if (session.audio.isNotEmpty) {
        sb.writeln('#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",NAME="audio",'
            'DEFAULT=YES,AUTOSELECT=YES,URI="$base/a.m3u8"');
        sb.writeln('#EXT-X-STREAM-INF:BANDWIDTH=1,AUDIO="aud"');
      } else {
        sb.writeln('#EXT-X-STREAM-INF:BANDWIDTH=1');
      }
      sb.writeln('$base/v.m3u8');
      await _writeText(response, sb.toString());
      return;
    }

    if (rest.length == 1 && (rest[0] == 'v.m3u8' || rest[0] == 'a.m3u8')) {
      final isVideo = rest[0] == 'v.m3u8';
      final segs = isVideo ? session.video : session.audio;
      final prefix = isVideo ? 'v' : 'a';
      await _writeText(
        response,
        _buildMediaPlaylist(session, segs, prefix, base),
      );
      return;
    }

    response.statusCode = HttpStatus.notFound;
    await response.close();
  }

  /// Builds a growing HLS media playlist for the segments already on disk. It's
  /// an EVENT playlist (segments only appended), so the player reloads it and
  /// keeps going as more segments download; ENDLIST is added once complete.
  String _buildMediaPlaylist(
    _HlsSession s,
    List<M3u8Segment> segs,
    String prefix,
    String base,
  ) {
    int avail = 0;
    while (avail < segs.length &&
        File('${s.tempDir}/${prefix}_$avail.ts').existsSync()) {
      avail++;
    }

    final maxDur = segs.isEmpty
        ? 10.0
        : segs.map((e) => e.duration).reduce((a, b) => a > b ? a : b);

    final sb = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-PLAYLIST-TYPE:EVENT')
      ..writeln('#EXT-X-TARGETDURATION:${maxDur.ceil()}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:0');

    M3u8EncryptionKey? lastKey;
    bool keyWritten = false;
    for (int i = 0; i < avail; i++) {
      final seg = segs[i];
      if (!keyWritten || seg.encryptionKey != lastKey) {
        if (seg.encryptionKey != null) {
          final localKey = s.localKeys[seg.encryptionKey!.uri];
          final ivStr = seg.encryptionKey!.iv != null
              ? ',IV=${seg.encryptionKey!.iv}'
              : '';
          sb.writeln(
            '#EXT-X-KEY:METHOD=${seg.encryptionKey!.method},URI="$base/key/$localKey"$ivStr',
          );
        } else {
          sb.writeln('#EXT-X-KEY:METHOD=NONE');
        }
        lastKey = seg.encryptionKey;
        keyWritten = true;
      }
      sb.writeln('#EXTINF:${seg.duration},');
      sb.writeln('$base/seg/${prefix}_$i.ts');
    }

    if (segs.isNotEmpty && avail == segs.length) {
      sb.writeln('#EXT-X-ENDLIST');
    }
    return sb.toString();
  }

  Future<void> _writeText(HttpResponse response, String body) async {
    response.statusCode = HttpStatus.ok;
    response.headers
        .set(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-cache, no-store');
    response.write(body);
    await response.close();
  }
}

class _HlsSession {
  final String tempDir;
  final List<M3u8Segment> video;
  final List<M3u8Segment> audio;
  final Map<String, String> localKeys;
  _HlsSession(this.tempDir, this.video, this.audio, this.localKeys);
}
