import 'dart:async';

import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../core/debug_log.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/m3u8_parser.dart';
import 'package:nivio/main.dart';

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚨 notificationTapBackground triggered with actionId: ${response.actionId}");
  if (response.actionId != null && response.actionId!.startsWith('cancel_')) {
    final id = response.actionId!.substring(7);
    debugPrint("🚨 Attempting to cancel download with id: $id");
    
    try {
      await DownloadService.deleteDownload(id);
    } catch (e) {
      debugPrint("🚨 Error in deleteDownload: $e");
    }

    final sendPort = IsolateNameServer.lookupPortByName('download_cancel_port');
    if (sendPort != null) {
      debugPrint("🚨 Found sendPort, sending id: $id");
      sendPort.send(id);
    } else {
      debugPrint("🚨 sendPort not found, calling FFmpegKit.cancel()");
      // Fallback for background isolate FFmpeg cancel
      await FFmpegKit.cancel();
    }
    return;
  }

  if (response.payload == 'open_downloads') {
    debugPrint("🚨 Tapped download notification body. Routing to downloads...");
    // The main notification tap forces the app into foreground, so appRouter is available.
    appRouter.go('/library?tab=downloads');
  }
}

void notificationTapForeground(NotificationResponse response) {
  debugPrint("🚨 notificationTapForeground triggered with actionId: \${response.actionId}");
  if (response.actionId != null && response.actionId!.startsWith('cancel_')) {
    final id = response.actionId!.substring(7);
    DownloadService.deleteDownload(id);
    return;
  }
  
  if (response.payload == 'open_downloads') {
    debugPrint("🚨 Tapped download notification body. Routing to downloads...");
    // Delay slightly to ensure app is fully resumed/ready to process navigation
    Future.delayed(const Duration(milliseconds: 100), () {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appRouter.go('/library?tab=downloads');
      });
    });
  }
}

class DownloadService {
  static const String _boxName = 'downloads';
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static final Dio _dio = Dio();
  static bool _isInitialized = false;

  // Active download cancellation tokens
  static final Map<String, CancelToken> _activeDownloads = {};
  static bool _wakelockEnabled = false;
  
  static Future<void> init() async {
    if (_isInitialized) return;
    
    // Initialize notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(
      initSettings,
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
      onDidReceiveNotificationResponse: notificationTapForeground,
    );
    
    // Check if app was launched by tapping a notification
    final launchDetails = await _notifications.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      final response = launchDetails!.notificationResponse;
      if (response != null) {
        // Wait a brief moment for the router to be ready, then trigger the tap logic
        Future.delayed(const Duration(milliseconds: 500), () {
          notificationTapForeground(response);
        });
      }
    }
    
    _isInitialized = true;
    appDebugLog('📥 DownloadService initialized');
  }

  static Box<DownloadItem> get box => Hive.box<DownloadItem>(_boxName);

  /// Returns a completed download for the given media whose file still exists on
  /// disk, or null if none is available. Used to transparently prefer offline
  /// playback whenever a local copy exists.
  ///
  /// For TV episodes the season/episode must match. For movies (no season /
  /// episode on the stored item) only the media id is matched.
  static DownloadItem? findPlayableDownload({
    required int mediaId,
    int? season,
    int? episode,
  }) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    for (final item in box.values) {
      if (item.mediaId != mediaId) continue;
      if (item.status != DownloadStatus.completed) continue;

      final bool isEpisode = item.season != null && item.episode != null;
      if (isEpisode) {
        if (item.season != season || item.episode != episode) continue;
      }

      if (item.savePath.isEmpty || !File(item.savePath).existsSync()) continue;
      return item;
    }
    return null;
  }

  static Future<bool> requestPermissions() async {
    if (Platform.isAndroid) {
      await Permission.notification.request();

      if (await Permission.manageExternalStorage.request().isGranted) {
        return true;
      }
      
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) return true;
      
      // On Android 13+, photos/videos permissions replace generic storage
      final photosStatus = await Permission.photos.request();
      final videosStatus = await Permission.videos.request();
      if (photosStatus.isGranted || videosStatus.isGranted) return true;

      appDebugLog('❌ Storage permission denied');
      return false;
    }
    return true; // iOS usually manages this per app
  }

  static Future<String?> getDownloadDirectory() async {
    if (!await requestPermissions()) return null;

    Directory? directory;
    if (Platform.isAndroid) {
      // Use public Downloads directory
      directory = Directory('/storage/emulated/0/Download/Nivio');
    } else {
      directory = await getApplicationDocumentsDirectory();
      directory = Directory('${directory.path}/Downloads');
    }

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory.path;
  }

  static String generateFileName(DownloadItem item) {
    String cleanTitle = item.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    if (item.season != null && item.episode != null) {
      return '${cleanTitle}_S${item.season}E${item.episode}.mkv';
    }
    return '$cleanTitle.mkv';
  }

  static Future<void> _acquireWakelock() async {
    if (!_wakelockEnabled && _activeDownloads.isNotEmpty) {
      try {
        await WakelockPlus.enable();
        _wakelockEnabled = true;
        appDebugLog('📥 Wakelock ENABLED for downloads');
      } catch (e) {
        appDebugLog('📥 Failed to enable wakelock: $e');
      }
    }
  }

  static Future<void> _releaseWakelock() async {
    if (_wakelockEnabled && _activeDownloads.isEmpty) {
      try {
        await WakelockPlus.disable();
        _wakelockEnabled = false;
        appDebugLog('📥 Wakelock DISABLED (no active downloads)');
      } catch (e) {
        appDebugLog('📥 Failed to disable wakelock: $e');
      }
    }
  }

  static Future<void> startDownload(DownloadItem item) async {
    if (item.streamUrl == null) return;
    
    final dir = await getDownloadDirectory();
    if (dir == null) {
      _updateStatus(item, DownloadStatus.failed);
      return;
    }

    final filePath = '$dir/${generateFileName(item)}';
    item.savePath = filePath;
    _updateStatus(item, DownloadStatus.downloading);
    await box.put(item.id, item);

    final cancelToken = CancelToken();
    _activeDownloads[item.id] = cancelToken;
    await _acquireWakelock();

    try {
      String streamUrl = item.streamUrl!;

      _updateStatus(item, DownloadStatus.downloading);

      // No need to change the extension to mkv, FFmpeg can mux HLS directly into mp4
      if (streamUrl.contains('.m3u8') || streamUrl.contains('/proxy?url=')) {
        appDebugLog('🎬 Downloading via FFmpeg (HLS)');
        await _downloadM3u8(item, item.savePath, cancelToken, streamUrlOverride: streamUrl);
      } else {
        appDebugLog('🎬 Downloading directly via Dio');
        await _downloadDirect(item, item.savePath, cancelToken, streamUrlOverride: streamUrl);
      }
    } catch (e) {
      if (cancelToken.isCancelled) {
        _updateStatus(item, DownloadStatus.paused);
      } else {
        appDebugLog('❌ Download failed for ${item.title}: $e');
        _updateStatus(item, DownloadStatus.failed);
      }
    } finally {
      _activeDownloads.remove(item.id);
      await _releaseWakelock();
    }
  }

  static Future<void> _downloadDirect(DownloadItem item, String filePath, CancelToken cancelToken, {String? streamUrlOverride}) async {
    final urlToDownload = streamUrlOverride ?? item.streamUrl!;
    
    // Get concurrency setting
    final prefs = await SharedPreferences.getInstance();
    final concurrency = prefs.getInt('download_concurrency') ?? 6;

    try {
      // 1. Probe file size
      final probeResponse = await _dio.head(
        urlToDownload,
        options: Options(headers: item.headers),
      );
      
      final contentLengthHeader = probeResponse.headers.value(Headers.contentLengthHeader);
      final acceptsRanges = probeResponse.headers.value('accept-ranges') == 'bytes';
      
      int? totalBytes;
      if (contentLengthHeader != null) {
        totalBytes = int.tryParse(contentLengthHeader);
      }

      // If server doesn't support ranges or we don't know the size, fallback to standard download
      if (totalBytes == null || totalBytes <= 0 || !acceptsRanges || concurrency <= 1) {
        appDebugLog('🎬 Direct: Falling back to sequential download (size: $totalBytes, ranges: $acceptsRanges, threads: $concurrency)');
        await _downloadDirectSequential(item, filePath, urlToDownload, cancelToken);
        return;
      }

      appDebugLog('🎬 Direct: Starting parallel download. Size: $totalBytes bytes, Threads: $concurrency');
      
      item.totalBytes = totalBytes;
      item.downloadedBytes = 0;
      
      final chunkCount = concurrency;
      final chunkSize = (totalBytes / chunkCount).ceil();
      
      final List<Future<void>> futures = [];
      final List<String> partFiles = [];
      final List<int> chunkProgress = List.filled(chunkCount, 0);
      
      int lastProgressUpdate = 0;

      // Ensure directory exists for parts


      // 2. Spawn parallel chunks
      for (int i = 0; i < chunkCount; i++) {
        int start = i * chunkSize;
        final int end = (i == chunkCount - 1) ? totalBytes - 1 : (start + chunkSize - 1);
        final int expectedChunkLength = end - start + 1;
        
        final partPath = '$filePath.part$i';
        partFiles.add(partPath);

        final partFile = File(partPath);
        int existingLength = 0;
        
        if (partFile.existsSync()) {
          existingLength = partFile.lengthSync();
          if (existingLength == expectedChunkLength) {
            chunkProgress[i] = existingLength;
            continue; // Chunk fully downloaded, skip!
          } else if (existingLength > expectedChunkLength) {
            partFile.deleteSync();
            existingLength = 0;
          } else {
            start += existingLength;
            chunkProgress[i] = existingLength;
          }
        }

        final chunkHeaders = Map<String, String>.from(item.headers ?? {});
        chunkHeaders['Range'] = 'bytes=$start-$end';

        final chunkCancelToken = CancelToken();
        cancelToken.whenCancel.then((_) => chunkCancelToken.cancel());

        futures.add(() async {
          bool chunkSuccess = false;
          int retries = 0;
          
          while (!chunkSuccess && retries < 5 && !cancelToken.isCancelled) {
            IOSink? sink;
            try {
              final response = await _dio.get<ResponseBody>(
                urlToDownload,
                cancelToken: chunkCancelToken,
                options: Options(
                  responseType: ResponseType.stream,
                  headers: chunkHeaders,
                  receiveTimeout: const Duration(minutes: 5),
                  sendTimeout: const Duration(minutes: 5),
                ),
              );

              sink = partFile.openWrite(mode: FileMode.writeOnlyAppend);
              int receivedThisSession = 0;
              
              await for (final chunk in response.data!.stream) {
                if (cancelToken.isCancelled) break;
                sink.add(chunk);
                receivedThisSession += chunk.length;
                chunkProgress[i] = existingLength + receivedThisSession;
                
                final now = DateTime.now().millisecondsSinceEpoch;
                if (now - lastProgressUpdate > 2000) {
                  lastProgressUpdate = now;
                  int totalReceived = chunkProgress.fold(0, (sum, val) => sum + val);
                  item.downloadedBytes = totalReceived;
                  item.progress = totalReceived / totalBytes!;
                  box.put(item.id, item);
                  _showProgressNotification(item);
                }
              }
              
              await sink.flush();
              await sink.close();
              sink = null;
              
              if (!cancelToken.isCancelled) {
                 if (existingLength + receivedThisSession == expectedChunkLength) {
                   chunkSuccess = true;
                 } else {
                   throw Exception('Chunk stream closed prematurely! (Got ${existingLength + receivedThisSession} / $expectedChunkLength)');
                 }
              }
            } catch (e) {
              if (sink != null) await sink.close();
              retries++;
              if (retries >= 5) {
                appDebugLog('❌ Direct Chunk failed after 5 retries: $e');
                rethrow;
              } else {
                if (partFile.existsSync()) {
                  existingLength = partFile.lengthSync();
                  start = (i * chunkSize) + existingLength;
                  chunkHeaders['Range'] = 'bytes=$start-$end';
                }
                await Future.delayed(Duration(seconds: 2 * retries)); // Exponential backoff
              }
            }
          }
        }());
      }

      // Wait for all chunks to finish
      await Future.wait(futures);

      if (cancelToken.isCancelled) return;

      // 3. Merge chunks
      appDebugLog('🎬 Direct: Merging $chunkCount chunks...');
      
      _updateStatus(item, DownloadStatus.extracting);
      await box.put(item.id, item);
      
      final finalFile = File(filePath);
      if (finalFile.existsSync()) await finalFile.delete();
      
      final output = finalFile.openWrite(mode: FileMode.writeOnlyAppend);
      
      for (final partPath in partFiles) {
        final partFile = File(partPath);
        if (partFile.existsSync()) {
          // Stream chunks asynchronously to prevent RAM exhaustion and UI thread blocking
          await output.addStream(partFile.openRead());
          await partFile.delete(); // Clean up
        }
      }
      await output.close();
      
      appDebugLog('🎬 Direct: Download and merge complete!');
      _completeDownload(item);

    } catch (e) {
      if (!cancelToken.isCancelled) {
        appDebugLog('🎬 Direct Error: $e');
        rethrow;
      }
    }
  }

  static Future<void> _downloadDirectSequential(DownloadItem item, String filePath, String url, CancelToken cancelToken) async {
    int lastProgressUpdate = 0;
    await _dio.download(
      url,
      filePath,
      cancelToken: cancelToken,
      options: Options(
        headers: item.headers,
        receiveTimeout: const Duration(seconds: 60),
      ),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          item.downloadedBytes = received;
          item.totalBytes = total;
          item.progress = received / total;
          
          final now = DateTime.now().millisecondsSinceEpoch;
          if (now - lastProgressUpdate > 2000) {
            lastProgressUpdate = now;
            box.put(item.id, item);
            _showProgressNotification(item);
          }
        }
      },
    );
    _completeDownload(item);
  }

  static Future<void> _downloadM3u8(DownloadItem item, String filePath, CancelToken cancelToken, {String? streamUrlOverride}) async {
    final urlToDownload = streamUrlOverride ?? item.streamUrl!;
    
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
    
    final prefs = await SharedPreferences.getInstance();
    final concurrency = prefs.getInt('download_concurrency') ?? 6;

    final streams = await M3u8Parser.resolveStreams(
      urlToDownload, 
      item.headers, 
      item.selectedAudioLanguage, 
      item.selectedSubtitleLanguage
    );

    final resolvedVideoUrl = streams?.videoUrl ?? urlToDownload;

    // Try parallel M3U8 downloading
    if (concurrency > 1) {
       final success = await _downloadM3u8Parallel(item, filePath, resolvedVideoUrl, streams?.audioUrl, streams?.subtitleUrl, cancelToken, concurrency);
       if (success) {
         _completeDownload(item);
         return;
       }
       // If parallel fails (e.g. unsupported tags, live streams), fallback to FFmpeg native fetching
       if (cancelToken.isCancelled) return;
       appDebugLog('🎬 HLS Parallel failed or unsupported, falling back to native FFmpeg fetching');
    }

    await _downloadM3u8Sequential(item, filePath, resolvedVideoUrl, streams?.audioUrl, streams?.subtitleUrl, cancelToken);
  }

  static Future<bool> _downloadM3u8Parallel(DownloadItem item, String filePath, String videoUrl, String? audioUrl, String? subtitleUrl, CancelToken cancelToken, int concurrency) async {
    try {
      appDebugLog('🎬 HLS: Fetching segments for $videoUrl');
      final videoSegments = await M3u8Parser.fetchSegments(videoUrl, item.headers);
      if (videoSegments.isEmpty) return false;

      final audioSegments = audioUrl != null ? await M3u8Parser.fetchSegments(audioUrl, item.headers) : <M3u8Segment>[];

      final totalSegments = videoSegments.length + audioSegments.length;
      int downloadedSegments = 0;
      int lastProgressUpdate = 0;

      final baseDir = File(filePath).parent.path;
      final tempDir = Directory('$baseDir/.hls_${item.id}');
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      } else {
        // Clean up any lingering .part files from previous paused downloads
        for (final file in tempDir.listSync()) {
          if (file.path.endsWith('.part')) {
            file.deleteSync();
          }
        }
      }



      // 1. Download all keys
      final Set<String> keyUrls = {};
      for (final s in [...videoSegments, ...audioSegments]) {
        if (s.encryptionKey != null) keyUrls.add(s.encryptionKey!.uri);
      }
      
      final Map<String, String> localKeys = {};
      int keyIdx = 0;
      for (final keyUrl in keyUrls) {
        final keyPath = '${tempDir.path}/key_$keyIdx.key';
        await _dio.download(keyUrl, keyPath, options: Options(headers: item.headers));
        localKeys[keyUrl] = 'key_$keyIdx.key';
        keyIdx++;
      }

      // 2. Download all segments using a concurrent queue
      bool failed = false;
      final allTasks = <Future<void>>[];
      
      Future<void> worker(List<MapEntry<int, M3u8Segment>> queue, String prefix) async {
        while (queue.isNotEmpty && !cancelToken.isCancelled && !failed) {
          final entry = queue.removeAt(0);
          final index = entry.key; // unique identifier
          final seg = entry.value;
          final segPath = '${tempDir.path}/${prefix}_$index.ts';
          
          if (File(segPath).existsSync()) {
            downloadedSegments++;
            continue; // Skip already downloaded segments!
          }
          
          final segPartPath = '$segPath.part';
          
          bool chunkSuccess = false;
          int retries = 0;
          
          while (!chunkSuccess && retries < 5 && !cancelToken.isCancelled && !failed) {
            try {
              await _dio.download(
                seg.url, 
                segPartPath, 
                cancelToken: cancelToken, 
                options: Options(
                  headers: item.headers,
                  receiveTimeout: const Duration(seconds: 30),
                  sendTimeout: const Duration(seconds: 30),
                )
              );
              
              // Rename upon success to mark it as fully downloaded
              File(segPartPath).renameSync(segPath);
              chunkSuccess = true;
              downloadedSegments++;
              
              final now = DateTime.now().millisecondsSinceEpoch;
              if (now - lastProgressUpdate > 1000) {
                lastProgressUpdate = now;
                item.progress = downloadedSegments / totalSegments;
                box.put(item.id, item);
                _showProgressNotification(item);
              }
            } catch (e) {
              retries++;
              if (retries >= 5) {
                appDebugLog('❌ HLS Chunk failed after 5 retries: ${seg.url} - Error: $e');
                if (!cancelToken.isCancelled) failed = true;
              } else {
                await Future.delayed(Duration(seconds: 2 * retries)); // Exponential backoff
              }
            }
          }
        }
      }

      final vQueue = videoSegments.asMap().entries.toList();
      for (int i = 0; i < concurrency; i++) allTasks.add(worker(vQueue, 'v'));
      
      final aQueue = audioSegments.asMap().entries.toList();
      if (aQueue.isNotEmpty) {
        for (int i = 0; i < concurrency; i++) allTasks.add(worker(aQueue, 'a'));
      }

      await Future.wait(allTasks);
      
      if (cancelToken.isCancelled || failed) {
        // Do NOT delete tempDir here, keep it for resuming later!
        if (failed) throw Exception('Network error during parallel HLS download');
        return false;
      }

      // 3. Generate Local M3U8 files
      String buildLocalM3u8(List<M3u8Segment> segs, String prefix) {
        final sb = StringBuffer();
        sb.writeln('#EXTM3U');
        sb.writeln('#EXT-X-VERSION:3');
        sb.writeln('#EXT-X-TARGETDURATION:${segs.map((s) => s.duration).reduce((a, b) => a > b ? a : b).ceil()}');
        
        M3u8EncryptionKey? lastKey;
        for (int i = 0; i < segs.length; i++) {
          final seg = segs[i];
          if (seg.encryptionKey != lastKey) {
            if (seg.encryptionKey != null) {
              final localKey = localKeys[seg.encryptionKey!.uri];
              final ivStr = seg.encryptionKey!.iv != null ? ',IV=${seg.encryptionKey!.iv}' : '';
              sb.writeln('#EXT-X-KEY:METHOD=${seg.encryptionKey!.method},URI="$localKey"$ivStr');
            } else {
              sb.writeln('#EXT-X-KEY:METHOD=NONE');
            }
            lastKey = seg.encryptionKey;
          }
          sb.writeln('#EXTINF:${seg.duration},');
          sb.writeln('${prefix}_$i.ts');
        }
        sb.writeln('#EXT-X-ENDLIST');
        return sb.toString();
      }

      final localVideoM3u8 = '${tempDir.path}/video.m3u8';
      File(localVideoM3u8).writeAsStringSync(buildLocalM3u8(videoSegments, 'v'));
      
      String? localAudioM3u8;
      if (audioSegments.isNotEmpty) {
        localAudioM3u8 = '${tempDir.path}/audio.m3u8';
        File(localAudioM3u8).writeAsStringSync(buildLocalM3u8(audioSegments, 'a'));
      }

      // 4. Mux using FFmpeg from local M3U8
      appDebugLog('🎬 HLS: Segments downloaded. Muxing locally via FFmpeg...');
      
      _updateStatus(item, DownloadStatus.extracting);
      await box.put(item.id, item);

      final ffmpegArgs = [
        '-loglevel', 'error', 
        '-allowed_extensions', 'ALL', 
        '-fflags', '+genpts+igndts+discardcorrupt', 
        '-i', localVideoM3u8
      ];
      if (localAudioM3u8 != null) {
        ffmpegArgs.addAll(['-allowed_extensions', 'ALL', '-i', localAudioM3u8]);
        ffmpegArgs.addAll(['-map', '0:v:0', '-map', '1:a:0']);
      } else {
        ffmpegArgs.addAll(['-map', '0:v?', '-map', '0:a?', '-map', '0:s?']);
      }
      
      final isAnimepahe = item.headers?['Referer']?.contains('kwik') == true;
      
      if (isAnimepahe) {
        // Transcode audio to fresh AAC to guarantee valid headers for MediaCodec (Animepahe Kwik bug)
        ffmpegArgs.addAll(['-c:v', 'copy']);
        ffmpegArgs.addAll(['-c:a', 'aac', '-b:a', '128k']);
      } else {
        // Direct stream copy for normal series to ensure instant merging
        ffmpegArgs.addAll(['-c', 'copy']);
      }
      
      // Add output-specific muxing flags
      ffmpegArgs.addAll(['-max_muxing_queue_size', '9999']);
      
      ffmpegArgs.add(filePath);

      final session = await FFmpegKit.executeWithArguments(ffmpegArgs);
      final returnCode = await session.getReturnCode();
      
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);

      if (ReturnCode.isSuccess(returnCode)) {
        try {
          final String srtFilePath = filePath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.srt');
          if (subtitleUrl != null) {
            await FFmpegKit.execute('-y -i "$subtitleUrl" -c:s srt "$srtFilePath"');
          } else {
            // Extract embedded subtitle
            await FFmpegKit.execute('-y -i "$filePath" -map 0:s:0? -c:s srt "$srtFilePath"');
          }
        } catch (e) {
          appDebugLog("Failed to extract SRT post-download: $e");
        }
        return true;
      } else {
        final logs = await session.getLogsAsString();
        appDebugLog('❌ FFmpeg Local Mux Error: $logs');
        return false;
      }
    } catch (e) {
      appDebugLog('❌ HLS Parallel Error: $e');
      return false;
    }
  }

  static Future<void> _downloadM3u8Sequential(DownloadItem item, String filePath, String resolvedVideoUrl, String? audioUrl, String? subtitleUrl, CancelToken cancelToken) async {
    // Try to get duration for progress calculation using fast Dart parser
    int durationMs = await M3u8Parser.getM3u8Duration(resolvedVideoUrl, item.headers);
    
    // Format headers for ffmpeg
    String headers = '';
    if (item.headers != null) {
      item.headers!.forEach((key, value) {
        headers += '$key: $value\r\n';
      });
    }

    final List<String> ffmpegArgs = ['-loglevel', 'debug'];

    void addInputFile(String url) {
      ffmpegArgs.addAll([
        '-reconnect', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '30',
        '-reconnect_on_network_error', '1',
        '-reconnect_on_http_error', '5xx',
        '-rw_timeout', '30000000',
        '-http_persistent', '0',
        '-allowed_extensions', 'ALL',
        '-allowed_segment_extensions', 'ALL',
        '-extension_picky', '0',
        '-seg_max_retry', '10',
        '-err_detect', 'ignore_err',
        '-fflags', '+genpts+igndts+discardcorrupt',
        '-probesize', '50000000',
        '-analyzeduration', '50000000'
      ]);
      if (headers.isNotEmpty) {
        ffmpegArgs.addAll(['-headers', headers]);
      }
      ffmpegArgs.addAll(['-i', url]);
    }
    
    // Add input sources
    addInputFile(resolvedVideoUrl);
    int inputIdx = 1;
    
    int? audioIdx;
    if (audioUrl != null) {
      addInputFile(audioUrl);
      audioIdx = inputIdx++;
    }
    
    // Do NOT add subtitle URL to the primary FFmpeg command to prevent AVERROR_INVALIDDATA!
    // We will download it independently in the post-processing step.

    // Map video
    ffmpegArgs.addAll(['-map', '0:v:0?']);
    
    // Map audio
    if (audioIdx != null) {
      ffmpegArgs.addAll(['-map', '$audioIdx:a:0?']);
    } else {
      if (item.selectedAudioLanguage != null && item.selectedAudioLanguage!.isNotEmpty) {
        ffmpegArgs.addAll(['-map', '0:a:m:language:${item.selectedAudioLanguage}?', '-map', '0:a:0?']);
      } else {
        ffmpegArgs.addAll(['-map', '0:a:m:language:eng?', '-map', '0:a:0?']);
      }
    }

    // Copy video, but transcode audio to fresh AAC to guarantee valid headers for MediaCodec
    ffmpegArgs.addAll(['-c:v', 'copy']);
    ffmpegArgs.addAll(['-c:a', 'aac', '-b:a', '128k']);
    
    final String subCodec = filePath.toLowerCase().endsWith('.mkv') ? 'srt' : 'mov_text';

    // Map embedded subtitles into the primary video file (ONLY if they are already embedded)
    if (subtitleUrl == null) {
      if (item.selectedSubtitleLanguage != null && item.selectedSubtitleLanguage!.isNotEmpty) {
        ffmpegArgs.addAll(['-map', '0:s:m:language:${item.selectedSubtitleLanguage}?', '-map', '0:s:0?']);
        ffmpegArgs.addAll(['-c:s', subCodec]);
      } else if (item.selectedSubtitleLanguage == null && item.id.contains('suboff')) {
        // Intentionally passing null to disable subtitles
      } else if (item.selectedSubtitleLanguage == null) {
        // Intentionally passing null (Off) means no subtitle mapping
      } else {
        ffmpegArgs.addAll(['-map', '0:s:m:language:eng?', '-map', '0:s:0?']);
        ffmpegArgs.addAll(['-c:s', subCodec]);
      }
    }

    // Set metadata tags so players natively recognize the language of the downloaded tracks
    final String audioLang = item.selectedAudioLanguage ?? 'eng';
    ffmpegArgs.addAll(['-metadata:s:a:0', 'language=$audioLang']);
    
    // Add output-specific muxing flags
    ffmpegArgs.addAll(['-max_muxing_queue_size', '9999']);
    
    // Output 1: Video file
    ffmpegArgs.add(filePath);


    final completer = Completer<void>();
    int lastUpdateMs = 0;

    final executeSession = await FFmpegKit.executeWithArgumentsAsync(
      ffmpegArgs, 
      (session) async {
        final returnCode = await session.getReturnCode();
        if (completer.isCompleted) return;
        if (ReturnCode.isSuccess(returnCode)) {
           if (item.progress > 0 && item.progress < 0.95) {
             appDebugLog("FFMPEG returned success but progress is only ${(item.progress * 100).toStringAsFixed(1)}%. Treating as FAILED due to network drop.");
             completer.completeError(Exception("Network drop: Download incomplete"));
           } else {
             completer.complete();
           }
        } else if (ReturnCode.isCancel(returnCode)) {
           completer.completeError(Exception("Cancelled"));
        } else {
           if (item.progress >= 0.95) {
             appDebugLog("FFMPEG returned error $returnCode but progress is ${(item.progress * 100).toStringAsFixed(1)}%. Treating as SUCCESS.");
             completer.complete();
             return;
           }
           final logs = await session.getLogs();
           String logOutput = logs.map((l) => l.getMessage()).join('\n');
           appDebugLog("FFMPEG ERROR LOG:\n$logOutput");
           completer.completeError(Exception("FFmpeg failed with code $returnCode"));
        }
      },
      (log) {
        // Uncomment below to see raw ffmpeg logs during download
        // print(log.getMessage());
      },
      (statistics) {
         if (cancelToken.isCancelled) return;
         if (durationMs > 0) {
           int timeMs = statistics.getTime().toInt();
           item.progress = (timeMs / durationMs).clamp(0.0, 1.0);
           
           // Update UI ~every 2 seconds
           if (timeMs - lastUpdateMs > 2000) {
             lastUpdateMs = timeMs;
             box.put(item.id, item);
             _showProgressNotification(item);
           }
          } else {
           // Fallback progress if duration is unknown (e.g. live stream or probe failed)
           int sizeBytes = statistics.getSize();
           item.downloadedBytes = sizeBytes;
           item.progress = -1.0; // Indicate indeterminate progress
           int timeMs = statistics.getTime().toInt();
           if (timeMs - lastUpdateMs > 2000) {
             lastUpdateMs = timeMs;
             box.put(item.id, item);
             _showProgressNotification(item);
           }
         }
      },
    );
    
    cancelToken.whenCancel.then((_) {
      executeSession.cancel();
    });

    await completer.future;

    // Mark as completed FIRST so the UI immediately shows "Completed"
    // SRT post-processing is non-critical and should never block the status transition
    _completeDownload(item);

    // Post-processing: Extract or download the subtitle into an SRT file
    // Doing this after the main download prevents FFmpeg from crashing with AVERROR_INVALIDDATA 
    // when trying to multiplex sparse network WebVTT streams with heavy video streams.
    try {
      final String srtFilePath = filePath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.srt');
      if (subtitleUrl != null) {
        // Download external subtitle directly to SRT
        await FFmpegKit.execute('-y -i "$subtitleUrl" -c:s srt "$srtFilePath"');
      } else {
        // Extract embedded subtitle
        await FFmpegKit.execute('-y -i "$filePath" -map 0:s:0? -c:s srt "$srtFilePath"');
      }
    } catch (e) {
      appDebugLog("Failed to extract SRT post-download: $e");
    }
  }

  static Future<void> _showProgressNotification(DownloadItem item) async {
    int progressPercentage = item.progress >= 0 ? (item.progress * 100).toInt() : 0;
    
    String title = item.title;
    if (item.season != null && item.episode != null) {
      title += ' S${item.season} E${item.episode}';
    }

    final androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Show download progress',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercentage,
      indeterminate: item.progress < 0,
      onlyAlertOnce: true,
      ongoing: item.status == DownloadStatus.extracting || item.status == DownloadStatus.downloading,
    );
    final details = NotificationDetails(android: androidDetails);

    if (item.status == DownloadStatus.extracting) {
      await _notifications.show(
        item.id.hashCode,
        title,
        item.progress >= 1.0 || item.downloadedBytes > 0 ? 'Merging files...' : 'Extracting video link...',
        details,
        payload: 'open_downloads',
      );
      return;
    }

    String sizeInfo = '';
    try {
      final file = File(item.savePath);
      if (file.existsSync()) {
        final bytes = file.lengthSync();
        if (bytes > 0) {
          final mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
          sizeInfo = ' • ${mb}MB';
        }
      }
    } catch (_) {}

    await _notifications.show(
      item.id.hashCode,
      title,
      'Downloading... $progressPercentage%$sizeInfo',
      details,
      payload: 'open_downloads',
    );
  }

  static Future<void> _completeDownload(DownloadItem item) async {
    item.status = DownloadStatus.completed;
    item.progress = 1.0;
    await box.put(item.id, item);
    
    String title = item.title;
    if (item.season != null && item.episode != null) {
      title += ' S${item.season} E${item.episode}';
    }

    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Show download progress',
      importance: Importance.high,
      priority: Priority.high,
    );

    await _notifications.show(
      item.id.hashCode,
      'Download Complete',
      title,
      const NotificationDetails(android: androidDetails),
      payload: 'open_downloads',
    );
  }

  static void _updateStatus(DownloadItem item, DownloadStatus status) {
    // If the item was deleted from the box, don't resurrect it unless we're just starting
    if (!box.containsKey(item.id) && status != DownloadStatus.downloading && status != DownloadStatus.extracting) {
      return;
    }
    item.status = status;
    box.put(item.id, item);
    if (status == DownloadStatus.extracting) {
      _showProgressNotification(item);
    }
  }

  static void pauseDownload(String id) {
    _activeDownloads[id]?.cancel();
    final item = box.get(id);
    if (item != null) {
      _updateStatus(item, DownloadStatus.paused);
    }
  }
  
  static void resumeDownload(String id) {
    final item = box.get(id);
    if (item != null) startDownload(item);
  }

  static Future<void> deleteDownload(String id) async {
    pauseDownload(id);
    final item = box.get(id);
    if (item != null) {
      final file = File(item.savePath);
      if (await file.exists()) {
        await file.delete();
      }
      
      try {
        final dir = file.parent;
        if (dir.existsSync()) {
          // Cleanup Direct .part files
          for (final f in dir.listSync()) {
            if (f.path.startsWith(file.path) && f.path.contains('.part')) {
               try { f.deleteSync(); } catch (_) {}
            }
          }
          
          // Cleanup HLS temporary folder
          final hlsTempDir = Directory('${dir.path}/.hls_${item.id}');
          if (hlsTempDir.existsSync()) {
            try { hlsTempDir.deleteSync(recursive: true); } catch (_) {}
          }
        }
      } catch (e) {
        appDebugLog('Failed to cleanup temp files: $e');
      }
      
      await box.delete(id);
    }
    // Ensure any stuck progress notification is scrubbed
    await _notifications.cancel(id.hashCode);
  }

  /// Queues a new download item. The UI should call this after fetching the stream URL.
  static Future<void> queueDownload({
    required int mediaId,
    required String title,
    required String mediaType,
    int? season,
    int? episode,
    String? posterPath,
    required String streamUrl,
    Map<String, String>? headers,
    String? selectedAudioLanguage,
    String? selectedSubtitleLanguage,
  }) async {
    final id = '${mediaId}_${season ?? 0}_${episode ?? 0}';
    
    if (box.containsKey(id)) {
      final existing = box.get(id);
      if (existing != null && existing.status != DownloadStatus.failed) {
        return; // Already exists and not failed
      }
    }

    final item = DownloadItem(
      id: id,
      mediaId: mediaId,
      title: title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      posterPath: posterPath,
      streamUrl: streamUrl,
      headers: headers ?? {},
      selectedAudioLanguage: selectedAudioLanguage,
      selectedSubtitleLanguage: selectedSubtitleLanguage,
      createdAt: DateTime.now(),
      status: DownloadStatus.pending,
      savePath: '',
    );

    await box.put(id, item);
    startDownload(item);
  }
}
