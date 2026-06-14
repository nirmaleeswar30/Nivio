import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../core/debug_log.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/m3u8_parser.dart';
import 'package:nivio/services/scrapers/animepahe/cloudflare_bypass_service.dart' as nivio;

class DownloadService {
  static const String _boxName = 'downloads';
  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static final Dio _dio = Dio();
  static bool _isInitialized = false;

  // Active download cancellation tokens
  static final Map<String, CancelToken> _activeDownloads = {};
  
  static Future<void> init() async {
    if (_isInitialized) return;
    
    // Initialize notifications
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _notifications.initialize(initSettings);
    
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
    String ext = (item.streamUrl?.contains('.m3u8') == true) ? 'mkv' : 'mp4';
    if (item.season != null && item.episode != null) {
      return '${cleanTitle}_S${item.season}E${item.episode}.$ext';
    }
    return '$cleanTitle.$ext';
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

    try {
      String streamUrl = item.streamUrl!;
      
      // If it's Animepahe Kwik embed URL, we need to extract the raw video link first
      if (streamUrl.contains('kwik.cx/e/')) {
        _updateStatus(item, DownloadStatus.extracting);
        appDebugLog('🛡️ Animepahe Kwik link detected. Extracting raw video URL...');
        final bypassService = nivio.CloudflareBypassService.instance; // Use prefix if needed, or import directly
        final rawUrl = await bypassService.extractKwikVideoUrl(streamUrl);
        if (rawUrl != null) {
          streamUrl = rawUrl;
        } else {
          throw Exception("Failed to extract Kwik video URL");
        }
      }

      _updateStatus(item, DownloadStatus.downloading);

      if (streamUrl.contains('.m3u8')) {
        // Pass streamUrl explicitly because we might have changed it
        await _downloadM3u8(item, filePath, cancelToken, streamUrlOverride: streamUrl);
      } else {
        await _downloadDirect(item, filePath, cancelToken, streamUrlOverride: streamUrl);
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
    }
  }

  static Future<void> _downloadDirect(DownloadItem item, String filePath, CancelToken cancelToken, {String? streamUrlOverride}) async {
    final urlToDownload = streamUrlOverride ?? item.streamUrl!;
    await _dio.download(
      urlToDownload,
      filePath,
      cancelToken: cancelToken,
      options: Options(headers: item.headers),
      onReceiveProgress: (received, total) {
        if (total != -1) {
          item.downloadedBytes = received;
          item.totalBytes = total;
          item.progress = received / total;
          
          if (received % (1024 * 1024 * 5) == 0) { // Update hive every 5MB
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
    
    final streams = await M3u8Parser.resolveStreams(
      urlToDownload, 
      item.headers, 
      item.selectedAudioLanguage, 
      item.selectedSubtitleLanguage
    );

    final resolvedVideoUrl = streams?.videoUrl ?? urlToDownload;

    // Try to get duration for progress calculation using fast Dart parser
    int durationMs = await M3u8Parser.getM3u8Duration(resolvedVideoUrl, item.headers);
    
    // Format headers for ffmpeg
    String headers = '';
    if (item.headers != null) {
      item.headers!.forEach((key, value) {
        headers += '$key: $value\r\n';
      });
    }

    final List<String> ffmpegArgs = [];

    void addInputFile(String url) {
      ffmpegArgs.addAll([
        '-reconnect', '1',
        '-reconnect_streamed', '1',
        '-reconnect_delay_max', '15',
        '-allowed_extensions', 'ALL',
        '-allowed_segment_extensions', 'ALL',
        '-extension_picky', '0'
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
    if (streams?.audioUrl != null) {
      addInputFile(streams!.audioUrl!);
      audioIdx = inputIdx++;
    }
    
    int? subIdx;
    if (streams?.subtitleUrl != null) {
      addInputFile(streams!.subtitleUrl!);
      subIdx = inputIdx++;
    }

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

    // Add base codec copy before specific overrides
    ffmpegArgs.addAll(['-c', 'copy']);
    
    final String subCodec = filePath.toLowerCase().endsWith('.mkv') ? 'srt' : 'mov_text';
    final String srtFilePath = filePath.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '.srt');

    // Map subtitles into the primary video file
    if (subIdx != null) {
      ffmpegArgs.addAll(['-map', '$subIdx:s:0?']);
      ffmpegArgs.addAll(['-c:s', subCodec]);
    } else {
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

    // Output 1: Video file
    ffmpegArgs.add(filePath);

    // Output 2: Extracted SRT file (for BetterPlayer UI)
    if (subIdx != null) {
      ffmpegArgs.addAll(['-map', '$subIdx:s:0?', '-c:s', 'srt', srtFilePath]);
    } else {
      if (item.selectedSubtitleLanguage != null && item.selectedSubtitleLanguage!.isNotEmpty) {
        ffmpegArgs.addAll(['-map', '0:s:m:language:${item.selectedSubtitleLanguage}?', '-map', '0:s:0?', '-c:s', 'srt', srtFilePath]);
      } else if (item.selectedSubtitleLanguage == null && item.id.contains('suboff')) {
        // None
      } else if (item.selectedSubtitleLanguage == null) {
        // None
      } else {
        ffmpegArgs.addAll(['-map', '0:s:m:language:eng?', '-map', '0:s:0?', '-c:s', 'srt', srtFilePath]);
      }
    }

    final completer = Completer<void>();
    int lastUpdateMs = 0;

    final executeSession = await FFmpegKit.executeWithArgumentsAsync(
      ffmpegArgs, 
      (session) async {
        final returnCode = await session.getReturnCode();
        if (ReturnCode.isSuccess(returnCode)) {
           completer.complete();
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
           item.progress = 0.5; // Arbitrary 50% so UI doesn't look completely dead at 0%
           int timeMs = statistics.getTime().toInt();
           if (timeMs - lastUpdateMs > 2000) {
             lastUpdateMs = timeMs;
             box.put(item.id, item);
           }
         }
      },
    );
    
    cancelToken.whenCancel.then((_) {
      executeSession.cancel();
    });

    await completer.future;
    _completeDownload(item);
  }

  static Future<void> _showProgressNotification(DownloadItem item) async {
    int progressPercentage = (item.progress * 100).toInt();
    
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
      onlyAlertOnce: true,
      ongoing: item.status == DownloadStatus.extracting || item.status == DownloadStatus.downloading,
    );
    final details = NotificationDetails(android: androidDetails);

    if (item.status == DownloadStatus.extracting) {
      await _notifications.show(
        item.id.hashCode,
        title,
        'Extracting video link...',
        details,
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
    );
  }

  static void _updateStatus(DownloadItem item, DownloadStatus status) {
    item.status = status;
    box.put(item.id, item);
    if (status == DownloadStatus.extracting) {
      _showProgressNotification(item);
    }
  }

  static void _failDownload(DownloadItem item) {
    item.progress = 0.0;
    _updateStatus(item, DownloadStatus.failed);
    
    const androidDetails = AndroidNotificationDetails(
      'download_channel',
      'Downloads',
      channelDescription: 'Show download progress',
      importance: Importance.high,
      priority: Priority.high,
    );

    _notifications.show(
      item.id.hashCode,
      'Download Failed',
      item.title,
      const NotificationDetails(android: androidDetails),
    );
  }

  static void pauseDownload(String id) {
    _activeDownloads[id]?.cancel();
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
      await box.delete(id);
    }
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
