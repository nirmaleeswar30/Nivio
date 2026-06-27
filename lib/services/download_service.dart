import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../core/debug_log.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/m3u8_parser.dart';
import 'package:nivio/services/scrapers/animepahe/cloudflare_bypass_service.dart' as nivio;
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
      
      // If it's Animepahe Kwik embed URL, we need to extract the raw video link first
      if (streamUrl.contains('kwik.cx/e/')) {
        _updateStatus(item, DownloadStatus.extracting);
        appDebugLog('🛡️ Animepahe Kwik link detected. Extracting raw video URL from: $streamUrl');
        final bypassService = nivio.CloudflareBypassService.instance; // Use prefix if needed, or import directly
        final rawUrl = await bypassService.extractKwikVideoUrl(streamUrl);
        if (rawUrl != null) {
          if (rawUrl.startsWith('{')) {
            try {
              final Map<String, dynamic> data = jsonDecode(rawUrl);
              if (data['type'] == 'form') {
                final action = data['action'];
                final token = data['token'];
                appDebugLog('🛡️ Kwik form detected. Action: $action, Token: $token');
                
                // Get the cookies from the bypass service
                final cookies = bypassService.cookieString;
                
                // We need to fetch the form action to get the actual download redirect
                final dioRedirect = Dio(BaseOptions(
                  followRedirects: false,
                  validateStatus: (status) => status != null && status < 500,
                  headers: {
                    'Cookie': cookies,
                    'Referer': streamUrl,
                    'User-Agent': bypassService.userAgent,
                  }
                ));
                
                final response = await dioRedirect.post(action, data: {
                  '_token': token
                }, options: Options(
                  contentType: Headers.formUrlEncodedContentType
                ));
                
                if (response.statusCode == 302 || response.statusCode == 301) {
                  streamUrl = response.headers.value('location')!;
                  appDebugLog('🛡️ Kwik form redirected to: $streamUrl');
                } else if (response.statusCode == 200) {
                   // Sometimes it might not redirect if it's a direct stream
                   streamUrl = action; 
                } else {
                  throw Exception("Failed to get redirect from Kwik form: \${response.statusCode}");
                }
              } else if (data['type'] == 'link') {
                streamUrl = data['href'];
              } else if (data['type'] == 'm3u8') {
                streamUrl = data['url'];
              }
            } catch (e) {
               appDebugLog('🛡️ Failed to parse Kwik JSON: $e. Falling back to raw string.');
               streamUrl = rawUrl;
            }
          } else {
            streamUrl = rawUrl;
          }
        } else {
          throw Exception("Failed to extract Kwik video URL");
        }
      }

      _updateStatus(item, DownloadStatus.downloading);

      // No need to change the extension to mkv, FFmpeg can mux HLS directly into mp4
      if (streamUrl.contains('.m3u8')) {
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
    int lastProgressUpdate = 0;
    await _dio.download(
      urlToDownload,
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
          if (now - lastProgressUpdate > 2000) { // Update UI every 2 seconds
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
    if (streams?.audioUrl != null) {
      addInputFile(streams!.audioUrl!);
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
    if (streams?.subtitleUrl == null) {
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
      if (streams?.subtitleUrl != null) {
        // Download external subtitle directly to SRT
        await FFmpegKit.execute('-y -i "${streams!.subtitleUrl!}" -c:s srt "$srtFilePath"');
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
        'Extracting video link...',
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
