import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../player/services/m3u8_parser.dart';
import '../models/library_models.dart';
import 'library_persistence.dart';

class DesktopDownloadService {
  DesktopDownloadService._({Dio? dio}) : _dio = dio ?? Dio();

  static final DesktopDownloadService instance = DesktopDownloadService._();

  static const _downloadLocationKey = 'download_location';
  static const _downloadConcurrencyKey = 'download_concurrency';

  final Dio _dio;
  final Map<String, CancelToken> _activeTokens = {};
  final Map<String, Process> _activeProcesses = {};

  Box<LibraryDownloadItem> get _box => LibraryPersistence.downloadsBox;

  Future<void> restorePendingDownloads() async {
    if (!LibraryPersistence.isReady) return;
    for (final item in _box.values) {
      if (item.status == LibraryDownloadStatus.pending ||
          item.status == LibraryDownloadStatus.downloading ||
          item.status == LibraryDownloadStatus.extracting) {
        unawaited(startDownload(item));
      }
    }
  }

  Future<void> queueDownload(LibraryDownloadItem item) async {
    if (!LibraryPersistence.isReady) await LibraryPersistence.init();
    await _box.put(item.id, item);
    unawaited(startDownload(item));
  }

  Future<void> startDownload(LibraryDownloadItem item) async {
    if (!LibraryPersistence.isReady) await LibraryPersistence.init();
    if (_activeTokens.containsKey(item.id) ||
        _activeProcesses.containsKey(item.id)) {
      return;
    }

    final streamUrl = item.streamUrl?.trim();
    if (streamUrl == null || streamUrl.isEmpty) {
      await _markFailed(item, 'No stream URL was resolved');
      return;
    }

    final token = CancelToken();
    _activeTokens[item.id] = token;

    try {
      item.savePath = item.savePath.trim().isEmpty
          ? await _buildSavePath(item)
          : item.savePath;
      item.status = LibraryDownloadStatus.downloading;
      item.progress = item.progress < 0 ? 0 : item.progress.clamp(0, 1);
      item.failureReason = null;
      await _putIfPresent(item);

      final isHls = _isHls(streamUrl);
      if (isHls) {
        await _downloadHls(item, streamUrl, token);
      } else {
        await _downloadDirect(item, streamUrl, token);
      }

      if (token.isCancelled || !_box.containsKey(item.id)) return;
      await _completeDownload(item);
    } on _DownloadPaused {
      await _markPaused(item);
    } on DioException catch (error) {
      if (CancelToken.isCancel(error) || token.isCancelled) {
        await _markPaused(item);
      } else {
        debugPrint('DesktopDownloadService Dio error: $error');
        await _markFailed(item, _friendlyError(error));
      }
    } catch (error) {
      if (token.isCancelled) {
        await _markPaused(item);
      } else {
        debugPrint('DesktopDownloadService error: $error');
        await _markFailed(item, _friendlyError(error));
      }
    } finally {
      _activeTokens.remove(item.id);
      final process = _activeProcesses.remove(item.id);
      process?.kill(ProcessSignal.sigterm);
    }
  }

  Future<void> pauseDownload(String id) async {
    _activeTokens[id]?.cancel('Paused');
    _activeProcesses.remove(id)?.kill(ProcessSignal.sigterm);
    final item = _box.get(id);
    if (item == null) return;
    await _markPaused(item);
  }

  Future<void> resumeDownload(String id) async {
    final item = _box.get(id);
    if (item == null) return;
    item.status = LibraryDownloadStatus.pending;
    item.failureReason = null;
    await _putIfPresent(item);
    unawaited(startDownload(item));
  }

  Future<void> retryDownload(String id) async {
    final item = _box.get(id);
    if (item == null) return;
    item
      ..status = LibraryDownloadStatus.pending
      ..progress = 0
      ..downloadedBytes = 0
      ..failureReason = null;
    await _putIfPresent(item);
    unawaited(startDownload(item));
  }

  Future<void> deleteDownload(String id) async {
    _activeTokens[id]?.cancel('Deleted');
    _activeProcesses.remove(id)?.kill(ProcessSignal.sigterm);
    final item = _box.get(id);
    if (item != null) {
      await _deleteFileIfExists(item.savePath);
      await _deleteFileIfExists('${item.savePath}.part');
      await _deleteFileIfExists(_subtitlePath(item.savePath));
      await _deleteDirectoryIfExists(
        '${File(item.savePath).parent.path}/.hls_${item.id}',
      );
    }
    await _box.delete(id);
  }

  Future<void> _downloadDirect(
    LibraryDownloadItem item,
    String url,
    CancelToken token,
  ) async {
    final partFile = File('${item.savePath}.part');
    await partFile.parent.create(recursive: true);
    var existingBytes = await partFile.exists() ? await partFile.length() : 0;
    var mode = FileMode.append;
    var headers = <String, String>{
      ...?item.headers,
      if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
    };

    var response = await _dio.get<ResponseBody>(
      url,
      cancelToken: token,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
        validateStatus: (status) => status != null && status < 600,
      ),
    );

    var statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 400) {
      throw Exception('Download HTTP $statusCode');
    }
    if (existingBytes > 0 && statusCode != HttpStatus.partialContent) {
      try {
        await partFile.delete();
      } catch (_) {}
      existingBytes = 0;
      mode = FileMode.write;
      headers = {...?item.headers};
      response = await _dio.get<ResponseBody>(
        url,
        cancelToken: token,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      statusCode = response.statusCode ?? 0;
      if (statusCode < 200 || statusCode >= 400) {
        throw Exception('Download HTTP $statusCode');
      }
    }

    final totalBytes = _totalBytes(response.headers, existingBytes);
    item.totalBytes = totalBytes;
    item.downloadedBytes = existingBytes;
    await _putIfPresent(item);

    final sink = partFile.openWrite(mode: mode);
    var downloaded = existingBytes;
    var lastUpdate = DateTime.now();
    try {
      await for (final chunk in response.data!.stream) {
        if (token.isCancelled) throw const _DownloadPaused();
        sink.add(chunk);
        downloaded += chunk.length;
        final now = DateTime.now();
        if (now.difference(lastUpdate).inMilliseconds >= 500) {
          lastUpdate = now;
          item
            ..downloadedBytes = downloaded
            ..progress = totalBytes > 0 ? downloaded / totalBytes : -1;
          await _putIfPresent(item);
        }
      }
    } finally {
      await sink.close();
    }

    if (token.isCancelled) throw const _DownloadPaused();
    item
      ..downloadedBytes = downloaded
      ..progress = 1;
    await _putIfPresent(item);
    await partFile.rename(item.savePath);
  }

  Future<void> _downloadHls(
    LibraryDownloadItem item,
    String url,
    CancelToken token,
  ) async {
    if (!await _hasFfmpeg()) {
      throw const _DownloadFailure(
        'ffmpeg is not installed. Install ffmpeg and retry this download.',
      );
    }

    item
      ..status = LibraryDownloadStatus.extracting
      ..progress = 0;
    await _putIfPresent(item);

    final headers = item.headers ?? const <String, String>{};
    final streams = await M3u8Parser.resolveStreams(
      url,
      headers,
      item.selectedAudioLanguage,
      item.selectedSubtitleLanguage,
    );

    try {
      await _downloadHlsWithFfmpeg(item, streams, token);
      return;
    } catch (error) {
      if (token.isCancelled) rethrow;
      debugPrint('DesktopDownloadService HLS ffmpeg stream failed: $error');
      await _downloadHlsSegments(item, streams, token);
    }
  }

  Future<void> _downloadHlsWithFfmpeg(
    LibraryDownloadItem item,
    M3u8Streams streams,
    CancelToken token,
  ) async {
    final outputPart = '${item.savePath}.part';
    await _deleteFileIfExists(outputPart);
    final durationMs = await _fetchHlsDuration(
      streams.videoUrl,
      item.headers ?? const {},
    );
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-progress',
      'pipe:2',
      '-nostats',
      '-reconnect',
      '1',
      '-reconnect_streamed',
      '1',
      '-reconnect_delay_max',
      '30',
      '-allowed_extensions',
      'ALL',
      '-protocol_whitelist',
      'file,http,https,tcp,tls,crypto',
      if ((item.headers ?? const {}).isNotEmpty) ...[
        '-headers',
        _ffmpegHeaders(item.headers!),
      ],
      '-i',
      streams.videoUrl,
      if (streams.audioUrl != null) ...[
        '-allowed_extensions',
        'ALL',
        '-protocol_whitelist',
        'file,http,https,tcp,tls,crypto',
        if ((item.headers ?? const {}).isNotEmpty) ...[
          '-headers',
          _ffmpegHeaders(item.headers!),
        ],
        '-i',
        streams.audioUrl!,
      ],
      '-map',
      '0:v:0?',
      '-map',
      streams.audioUrl == null ? '0:a:0?' : '1:a:0?',
      if (streams.subtitleUrl == null) ...['-map', '0:s:0?'],
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-c:s',
      'srt',
      '-max_muxing_queue_size',
      '9999',
      outputPart,
    ];

    final ffmpegErrors = <String>[];
    final exitCode = await _runFfmpeg(
      item: item,
      args: args,
      token: token,
      durationMs: durationMs,
      stderrLines: ffmpegErrors,
    );

    if (token.isCancelled) throw const _DownloadPaused();
    if (exitCode != 0 || !await File(outputPart).exists()) {
      throw _DownloadFailure(
        'ffmpeg stream download failed${_ffmpegErrorSuffix(ffmpegErrors)}',
      );
    }
    await File(outputPart).rename(item.savePath);
    await _downloadSubtitleFromUrl(item, streams.subtitleUrl);
  }

  Future<void> _downloadHlsSegments(
    LibraryDownloadItem item,
    M3u8Streams streams,
    CancelToken token,
  ) async {
    item
      ..status = LibraryDownloadStatus.downloading
      ..progress = 0;
    await _putIfPresent(item);

    final videoSegments = await M3u8Parser.fetchSegments(
      streams.videoUrl,
      item.headers ?? const {},
    );
    if (videoSegments.isEmpty) {
      throw const _DownloadFailure('HLS playlist has no downloadable segments');
    }
    final audioSegments = streams.audioUrl == null
        ? <M3u8Segment>[]
        : await M3u8Parser.fetchSegments(
            streams.audioUrl!,
            item.headers ?? const {},
          );

    final tempDir = Directory(
      '${File(item.savePath).parent.path}/.hls_${item.id}',
    );
    await tempDir.create(recursive: true);
    for (final file in tempDir.listSync()) {
      if (file.path.endsWith('.part')) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
    }

    final localKeys = await _downloadHlsKeys(
      tempDir,
      [...videoSegments, ...audioSegments],
      item,
      token,
    );

    final totalSegments = videoSegments.length + audioSegments.length;
    var downloadedSegments =
        _existingSegmentCount(tempDir, 'v', videoSegments.length) +
        _existingSegmentCount(tempDir, 'a', audioSegments.length);
    item.progress = downloadedSegments / totalSegments;
    await _putIfPresent(item);

    var failed = false;
    var lastUpdate = DateTime.now();
    final concurrency = await _downloadConcurrency();

    Future<void> worker(
      List<MapEntry<int, M3u8Segment>> queue,
      String prefix,
    ) async {
      while (queue.isNotEmpty && !token.isCancelled && !failed) {
        final entry = queue.removeAt(0);
        final segmentPath = '${tempDir.path}/${prefix}_${entry.key}.ts';
        if (File(segmentPath).existsSync()) {
          _stripPngHeaderFromLocalFile(segmentPath);
          continue;
        }
        var retries = 0;
        var success = false;
        while (!success && retries < 5 && !token.isCancelled && !failed) {
          try {
            final partPath = '$segmentPath.part';
            await _dio.download(
              entry.value.url,
              partPath,
              cancelToken: token,
              options: Options(
                headers: item.headers,
                receiveTimeout: const Duration(seconds: 30),
                sendTimeout: const Duration(seconds: 30),
              ),
            );
            _stripPngHeaderFromLocalFile(partPath);
            await File(partPath).rename(segmentPath);
            success = true;
            downloadedSegments++;
            final now = DateTime.now();
            if (now.difference(lastUpdate).inMilliseconds >= 500) {
              lastUpdate = now;
              item.progress = downloadedSegments / totalSegments;
              await _putIfPresent(item);
            }
          } on DioException catch (error) {
            if (token.isCancelled || CancelToken.isCancel(error)) {
              throw const _DownloadPaused();
            }
            retries++;
            if (retries >= 5 && !token.isCancelled) {
              failed = true;
            } else {
              await Future.delayed(Duration(seconds: retries * 2));
            }
          } catch (_) {
            retries++;
            if (retries >= 5 && !token.isCancelled) {
              failed = true;
            } else {
              await Future.delayed(Duration(seconds: retries * 2));
            }
          }
        }
      }
    }

    final tasks = <Future<void>>[];
    final videoQueue = videoSegments.asMap().entries.toList();
    for (var i = 0; i < concurrency; i++) {
      tasks.add(worker(videoQueue, 'v'));
    }
    final audioQueue = audioSegments.asMap().entries.toList();
    for (var i = 0; i < concurrency && audioQueue.isNotEmpty; i++) {
      tasks.add(worker(audioQueue, 'a'));
    }
    await Future.wait(tasks);

    if (token.isCancelled) throw const _DownloadPaused();
    if (failed) {
      throw const _DownloadFailure(
        'Network error while downloading HLS segments',
      );
    }

    final videoM3u8 = '${tempDir.path}/video.m3u8';
    await File(
      videoM3u8,
    ).writeAsString(_buildLocalM3u8(videoSegments, 'v', localKeys));
    String? audioM3u8;
    if (audioSegments.isNotEmpty) {
      audioM3u8 = '${tempDir.path}/audio.m3u8';
      await File(
        audioM3u8,
      ).writeAsString(_buildLocalM3u8(audioSegments, 'a', localKeys));
    }

    item
      ..status = LibraryDownloadStatus.extracting
      ..progress = 1;
    await _putIfPresent(item);

    final outputPart = '${item.savePath}.part';
    await _deleteFileIfExists(outputPart);
    final args = <String>[
      '-y',
      '-hide_banner',
      '-loglevel',
      'error',
      '-allowed_extensions',
      'ALL',
      '-protocol_whitelist',
      'file,http,https,tcp,tls,crypto',
      '-i',
      videoM3u8,
      if (audioM3u8 != null) ...[
        '-allowed_extensions',
        'ALL',
        '-protocol_whitelist',
        'file,http,https,tcp,tls,crypto',
        '-i',
        audioM3u8,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0',
      ] else ...[
        '-map',
        '0:v?',
        '-map',
        '0:a?',
        '-map',
        '0:s?',
      ],
      '-c:v',
      'copy',
      '-c:a',
      'aac',
      '-b:a',
      '128k',
      '-c:s',
      'srt',
      '-max_muxing_queue_size',
      '9999',
      outputPart,
    ];
    final ffmpegErrors = <String>[];
    final exitCode = await _runFfmpeg(
      item: item,
      args: args,
      token: token,
      durationMs: 0,
      stderrLines: ffmpegErrors,
    );
    if (token.isCancelled) throw const _DownloadPaused();
    if (exitCode != 0 || !await File(outputPart).exists()) {
      throw _DownloadFailure(
        'ffmpeg failed while merging HLS segments${_ffmpegErrorSuffix(ffmpegErrors)}',
      );
    }
    await File(outputPart).rename(item.savePath);
    await _downloadSubtitleFromUrl(item, streams.subtitleUrl);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  }

  Future<void> _completeDownload(LibraryDownloadItem item) async {
    if (!_box.containsKey(item.id)) return;
    await _downloadSubtitle(item);
    item
      ..status = LibraryDownloadStatus.completed
      ..progress = 1
      ..failureReason = null
      ..downloadedBytes = await File(item.savePath).exists()
          ? await File(item.savePath).length()
          : item.downloadedBytes;
    if (item.totalBytes <= 0) item.totalBytes = item.downloadedBytes;
    await _putIfPresent(item);
  }

  Future<void> _downloadSubtitle(LibraryDownloadItem item) async {
    final subtitleUrl = item.subtitleUrl?.trim();
    if (subtitleUrl == null || subtitleUrl.isEmpty || item.savePath.isEmpty) {
      return;
    }
    try {
      await _dio.download(
        subtitleUrl,
        _subtitlePath(item.savePath),
        options: Options(headers: item.headers),
      );
    } catch (error) {
      debugPrint('DesktopDownloadService subtitle error: $error');
    }
  }

  Future<void> _downloadSubtitleFromUrl(
    LibraryDownloadItem item,
    String? subtitleUrl,
  ) async {
    final url = subtitleUrl?.trim();
    if (url == null || url.isEmpty || item.savePath.isEmpty) return;
    try {
      await _dio.download(
        url,
        _subtitlePath(item.savePath),
        options: Options(headers: item.headers),
      );
    } catch (error) {
      debugPrint('DesktopDownloadService selected subtitle error: $error');
    }
  }

  Future<String> _buildSavePath(LibraryDownloadItem item) async {
    final directory = Directory(await _downloadDirectory());
    await directory.create(recursive: true);
    final base = _sanitizeFileName(
      [
        item.title.split('|||').first,
        if (item.season != null && item.episode != null)
          'S${item.season}E${item.episode}',
      ].join(' '),
    );
    var candidate = File('${directory.path}/$base.mkv');
    var index = 1;
    while (await candidate.exists()) {
      candidate = File('${directory.path}/$base ($index).mkv');
      index++;
    }
    return candidate.path;
  }

  Future<String> _downloadDirectory() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString(_downloadLocationKey)?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final documents = await getApplicationDocumentsDirectory();
    return '${documents.path}/downloads';
  }

  Future<int> _fetchHlsDuration(
    String url,
    Map<String, String> headers, [
    int depth = 0,
  ]) async {
    if (depth > 2) return 0;
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          followRedirects: true,
        ),
      );
      final body = response.data ?? '';
      var seconds = 0.0;
      for (final match in RegExp(r'#EXTINF:([\d.]+)').allMatches(body)) {
        seconds += double.tryParse(match.group(1) ?? '') ?? 0;
      }
      if (seconds > 0) return (seconds * 1000).round();

      for (final raw in body.split('\n')) {
        final line = raw.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        if (!line.toLowerCase().contains('.m3u8')) continue;
        return _fetchHlsDuration(
          response.realUri.resolve(line).toString(),
          headers,
          depth + 1,
        );
      }
    } catch (_) {}
    return 0;
  }

  Future<bool> _hasFfmpeg() async {
    try {
      final result = await Process.run('ffmpeg', const [
        '-version',
      ]).timeout(const Duration(seconds: 5));
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<int> _downloadConcurrency() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_downloadConcurrencyKey) ?? 6;
    return value.clamp(1, 12).toInt();
  }

  Future<int> _runFfmpeg({
    required LibraryDownloadItem item,
    required List<String> args,
    required CancelToken token,
    required int durationMs,
    List<String>? stderrLines,
  }) async {
    Process process;
    try {
      process = await Process.start('ffmpeg', args);
    } on ProcessException {
      throw const _DownloadFailure(
        'ffmpeg is not installed. Install ffmpeg and retry this download.',
      );
    }

    _activeProcesses[item.id] = process;
    unawaited(process.stdout.drain<void>());

    var lastUpdate = DateTime.now();
    final stderrSubscription = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final progress = _progressFromFfmpegLine(line, durationMs);
          final trimmed = line.trim();
          if (stderrLines != null &&
              trimmed.isNotEmpty &&
              !_isFfmpegProgressLine(trimmed)) {
            stderrLines.add(trimmed);
            if (stderrLines.length > 12) stderrLines.removeAt(0);
          }
          if (progress == null) return;
          final now = DateTime.now();
          if (now.difference(lastUpdate).inMilliseconds < 500) return;
          lastUpdate = now;
          item
            ..status = LibraryDownloadStatus.downloading
            ..progress = progress;
          unawaited(_putIfPresent(item));
        });

    try {
      final exitCode = await process.exitCode;
      await stderrSubscription.cancel();
      if (token.isCancelled) throw const _DownloadPaused();
      return exitCode;
    } finally {
      _activeProcesses.remove(item.id);
    }
  }

  Future<Map<String, String>> _downloadHlsKeys(
    Directory tempDir,
    List<M3u8Segment> segments,
    LibraryDownloadItem item,
    CancelToken token,
  ) async {
    final keys = <String, String>{};
    for (final segment in segments) {
      final key = segment.encryptionKey;
      if (key == null || keys.containsKey(key.uri)) continue;
      if (token.isCancelled) throw const _DownloadPaused();

      final fileName = 'key_${keys.length}.key';
      final path = '${tempDir.path}/$fileName';
      if (!File(path).existsSync()) {
        await _dio.download(
          key.uri,
          path,
          cancelToken: token,
          options: Options(headers: item.headers),
        );
      }
      keys[key.uri] = fileName;
    }
    return keys;
  }

  int _existingSegmentCount(Directory tempDir, String prefix, int count) {
    var existing = 0;
    for (var i = 0; i < count; i++) {
      if (File('${tempDir.path}/${prefix}_$i.ts').existsSync()) {
        existing++;
      }
    }
    return existing;
  }

  void _stripPngHeaderFromLocalFile(String path) {
    try {
      final file = File(path);
      if (!file.existsSync()) return;
      final bytes = file.readAsBytesSync();
      const pngHeader = <int>[137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length <= pngHeader.length) return;
      for (var i = 0; i < pngHeader.length; i++) {
        if (bytes[i] != pngHeader[i]) return;
      }
      file.writeAsBytesSync(bytes.sublist(pngHeader.length), flush: true);
    } catch (_) {}
  }

  String _buildLocalM3u8(
    List<M3u8Segment> segments,
    String prefix,
    Map<String, String> localKeys,
  ) {
    final buffer = StringBuffer()
      ..writeln('#EXTM3U')
      ..writeln('#EXT-X-VERSION:3')
      ..writeln('#EXT-X-TARGETDURATION:${_targetDuration(segments)}')
      ..writeln('#EXT-X-MEDIA-SEQUENCE:0');
    M3u8EncryptionKey? previousKey;

    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final key = segment.encryptionKey;
      if (_keyChanged(previousKey, key)) {
        if (key == null) {
          buffer.writeln('#EXT-X-KEY:METHOD=NONE');
        } else {
          final keyUri = localKeys[key.uri] ?? key.uri;
          final iv = key.iv == null ? '' : ',IV=${key.iv}';
          buffer.writeln('#EXT-X-KEY:METHOD=${key.method},URI="$keyUri"$iv');
        }
        previousKey = key;
      }
      buffer
        ..writeln('#EXTINF:${segment.duration.toStringAsFixed(3)},')
        ..writeln('${prefix}_$i.ts');
    }

    buffer.writeln('#EXT-X-ENDLIST');
    return buffer.toString();
  }

  int _targetDuration(List<M3u8Segment> segments) {
    var maxDuration = 1;
    for (final segment in segments) {
      final duration = segment.duration.ceil();
      if (duration > maxDuration) maxDuration = duration;
    }
    return maxDuration;
  }

  bool _keyChanged(M3u8EncryptionKey? previous, M3u8EncryptionKey? current) {
    return previous?.method != current?.method ||
        previous?.uri != current?.uri ||
        previous?.iv != current?.iv;
  }

  Future<void> _markPaused(LibraryDownloadItem item) async {
    if (!_box.containsKey(item.id)) return;
    item.status = LibraryDownloadStatus.paused;
    await _putIfPresent(item);
  }

  Future<void> _markFailed(LibraryDownloadItem item, [String? reason]) async {
    if (!_box.containsKey(item.id)) return;
    item
      ..status = LibraryDownloadStatus.failed
      ..failureReason = reason;
    await _putIfPresent(item);
  }

  Future<void> _putIfPresent(LibraryDownloadItem item) async {
    if (!_box.containsKey(item.id)) return;
    await _box.put(item.id, item);
  }

  Future<void> _deleteFileIfExists(String path) async {
    if (path.trim().isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _deleteDirectoryIfExists(String path) async {
    if (path.trim().isEmpty) return;
    try {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    } catch (_) {}
  }

  int _totalBytes(Headers headers, int existingBytes) {
    final contentRange = headers.value(HttpHeaders.contentRangeHeader);
    final rangeMatch = contentRange == null
        ? null
        : RegExp(r'/(\d+)$').firstMatch(contentRange);
    if (rangeMatch != null) {
      return int.tryParse(rangeMatch.group(1) ?? '') ?? 0;
    }
    final contentLength = int.tryParse(
      headers.value(HttpHeaders.contentLengthHeader) ?? '',
    );
    if (contentLength == null || contentLength <= 0) return 0;
    return contentLength + existingBytes;
  }

  double? _progressFromFfmpegLine(String line, int durationMs) {
    if (durationMs <= 0 || !line.startsWith('out_time_ms=')) return null;
    final outTimeUs = int.tryParse(line.substring('out_time_ms='.length));
    if (outTimeUs == null) return null;
    return (outTimeUs / 1000 / durationMs).clamp(0.0, 1.0);
  }

  bool _isFfmpegProgressLine(String line) {
    final key = line.split('=').first;
    return const {
      'bitrate',
      'dup_frames',
      'drop_frames',
      'fps',
      'frame',
      'out_time',
      'out_time_ms',
      'out_time_us',
      'progress',
      'speed',
      'stream_0_0_q',
      'total_size',
    }.contains(key);
  }

  String _ffmpegErrorSuffix(List<String> lines) {
    final message = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join(' ')
        .trim();
    if (message.isEmpty) return '';
    return ': $message';
  }

  String _ffmpegHeaders(Map<String, String> headers) {
    final value = headers.entries
        .map((entry) => '${entry.key}: ${entry.value}')
        .join('\r\n');
    return '$value\r\n';
  }

  String _subtitlePath(String videoPath) {
    return videoPath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.srt');
  }

  String _sanitizeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return sanitized.isEmpty ? 'Nivio download' : sanitized;
  }

  bool _isHls(String value) => value.toLowerCase().contains('.m3u8');

  String _friendlyError(Object error) {
    if (error is _DownloadFailure) return error.message;
    if (error is ProcessException && error.executable == 'ffmpeg') {
      return 'ffmpeg is not installed. Install ffmpeg and retry this download.';
    }
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode != null) {
        return 'Download server returned HTTP $statusCode';
      }
      return 'Network error while downloading';
    }
    final message = error.toString().replaceFirst('Exception: ', '').trim();
    if (message.isEmpty) return 'Download failed';
    return message.length > 140 ? '${message.substring(0, 137)}...' : message;
  }
}

class _DownloadPaused implements Exception {
  const _DownloadPaused();
}

class _DownloadFailure implements Exception {
  const _DownloadFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
