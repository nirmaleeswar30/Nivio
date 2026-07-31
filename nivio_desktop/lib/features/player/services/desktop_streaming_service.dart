import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../live_tv/services/builtin_live_tv_providers.dart';
import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';
import 'anime_stream_providers.dart';
import 'netmirror_stream_provider.dart';
import 'playback_runtime_diagnostics.dart';
import 'provider_registry.dart';
import 'stream_resolver.dart';

enum StreamContentKind { mp4, hls, dash, iframe, html, redirect, unknown }

class StreamValidationResult {
  const StreamValidationResult({
    required this.playable,
    required this.kind,
    this.statusCode,
    this.contentType,
    this.finalUrl,
    this.failureReason,
  });

  final bool playable;
  final StreamContentKind kind;
  final int? statusCode;
  final String? contentType;
  final String? finalUrl;
  final String? failureReason;
}

abstract interface class StreamHealthChecker {
  Future<StreamValidationResult> validate(
    String source,
    Map<String, String> headers, {
    bool isHls = false,
  });
}

class DesktopStreamHealthChecker implements StreamHealthChecker {
  DesktopStreamHealthChecker({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              validateStatus: (status) => status != null && status < 600,
            ),
          );

  final Dio _dio;

  @override
  Future<StreamValidationResult> validate(
    String source,
    Map<String, String> headers, {
    bool isHls = false,
  }) async {
    final uri = Uri.tryParse(source);
    if (uri == null) {
      return const StreamValidationResult(
        playable: false,
        kind: StreamContentKind.unknown,
        failureReason: 'Invalid URL',
      );
    }

    if (!uri.hasScheme || uri.scheme == 'file') {
      final path = uri.scheme == 'file' ? uri.toFilePath() : source;
      final exists = File(path).existsSync();
      return StreamValidationResult(
        playable: exists,
        kind: _kindFromUrl(source, isHls: isHls),
        finalUrl: source,
        failureReason: exists ? null : 'Local file does not exist',
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return StreamValidationResult(
        playable: true,
        kind: _kindFromUrl(source, isHls: isHls),
        finalUrl: source,
      );
    }

    try {
      if (isHls || _isHlsUrl(source)) {
        final response = await _dio.get<String>(
          source,
          options: Options(
            headers: {
              ...headers,
              'Accept':
                  'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
            },
            responseType: ResponseType.plain,
            followRedirects: true,
          ),
        );
        final status = response.statusCode ?? 0;
        final contentType = response.headers.value(Headers.contentTypeHeader);
        final body = response.data ?? '';
        final kind = _classify(
          source: source,
          contentType: contentType,
          bodyPreview: body,
          isHlsHint: true,
        );
        final failure = _failureReason(
          statusCode: status,
          kind: kind,
          contentType: contentType,
          bodyPreview: body,
          requirePlaylist: true,
        );
        final segmentFailure = failure == null
            ? await _validateHlsSegment(
                playlistUrl: response.realUri,
                playlistBody: body,
                headers: headers,
              )
            : null;
        return StreamValidationResult(
          playable: failure == null && segmentFailure == null,
          kind: kind,
          statusCode: status,
          contentType: contentType,
          finalUrl: response.realUri.toString(),
          failureReason: failure ?? segmentFailure,
        );
      }

      final response = await _dio.get<List<int>>(
        source,
        options: Options(
          headers: {...headers, 'Range': 'bytes=0-1'},
          responseType: ResponseType.bytes,
          followRedirects: true,
        ),
      );
      final status = response.statusCode ?? 0;
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final bodyPreview = _decodePreview(response.data ?? const []);
      final kind = _classify(
        source: source,
        contentType: contentType,
        bodyPreview: bodyPreview,
        isHlsHint: false,
      );
      final failure = _failureReason(
        statusCode: status,
        kind: kind,
        contentType: contentType,
        bodyPreview: bodyPreview,
        requirePlaylist: false,
      );
      return StreamValidationResult(
        playable: failure == null,
        kind: kind,
        statusCode: status,
        contentType: contentType,
        finalUrl: response.realUri.toString(),
        failureReason: failure,
      );
    } on DioException {
      return const StreamValidationResult(
        playable: false,
        kind: StreamContentKind.unknown,
        failureReason: 'Network validation failed',
      );
    } on FileSystemException {
      return const StreamValidationResult(
        playable: false,
        kind: StreamContentKind.unknown,
        failureReason: 'Filesystem validation failed',
      );
    }
  }

  static bool _isHlsUrl(String source) {
    final lower = source.toLowerCase();
    return lower.contains('.m3u8') || lower.contains('m3u8');
  }

  static StreamContentKind _kindFromUrl(String source, {required bool isHls}) {
    final lower = source.toLowerCase();
    if (isHls || lower.contains('.m3u8')) return StreamContentKind.hls;
    if (lower.contains('.mpd')) return StreamContentKind.dash;
    if (lower.contains('.mp4') || lower.contains('.mkv')) {
      return StreamContentKind.mp4;
    }
    return StreamContentKind.unknown;
  }

  static StreamContentKind _classify({
    required String source,
    required String? contentType,
    required String bodyPreview,
    required bool isHlsHint,
  }) {
    final lowerType = (contentType ?? '').toLowerCase();
    final lowerSource = source.toLowerCase();
    final lowerBody = bodyPreview.toLowerCase();
    if (lowerBody.contains('<html') ||
        lowerBody.contains('<!doctype html') ||
        lowerType.contains('text/html')) {
      return StreamContentKind.html;
    }
    if (lowerBody.contains('#extm3u') ||
        isHlsHint ||
        lowerSource.contains('.m3u8') ||
        lowerType.contains('mpegurl') ||
        lowerType.contains('vnd.apple.mpegurl')) {
      return StreamContentKind.hls;
    }
    if (lowerSource.contains('.mpd') || lowerType.contains('dash+xml')) {
      return StreamContentKind.dash;
    }
    if (lowerSource.contains('.mp4') ||
        lowerSource.contains('.mkv') ||
        lowerType.startsWith('video/') ||
        lowerType.contains('octet-stream')) {
      return StreamContentKind.mp4;
    }
    return StreamContentKind.unknown;
  }

  static String? _failureReason({
    required int statusCode,
    required StreamContentKind kind,
    required String? contentType,
    required String bodyPreview,
    required bool requirePlaylist,
  }) {
    if (statusCode < 200 || statusCode >= 400) {
      return 'HTTP $statusCode';
    }
    final lower = bodyPreview.toLowerCase();
    if (kind == StreamContentKind.html) {
      if (lower.contains('cloudflare') ||
          lower.contains('cf-browser-verification') ||
          lower.contains('just a moment')) {
        return 'Cloudflare/browser challenge HTML';
      }
      if (lower.contains('login') || lower.contains('sign in')) {
        return 'Login page HTML';
      }
      return 'HTML page returned instead of media';
    }
    if (requirePlaylist && !lower.contains('#extm3u')) {
      return 'HLS URL did not return an M3U8 playlist';
    }
    if (kind == StreamContentKind.unknown) {
      return 'Unknown media type (${contentType ?? 'no content-type'})';
    }
    return null;
  }

  static String _decodePreview(List<int> bytes) {
    if (bytes.isEmpty) return '';
    return String.fromCharCodes(bytes.take(512));
  }

  Future<String?> _validateHlsSegment({
    required Uri playlistUrl,
    required String playlistBody,
    required Map<String, String> headers,
  }) async {
    final firstMedia = _firstPlaylistUri(playlistBody);
    if (firstMedia == null) return 'HLS playlist has no media entries';

    final firstUri = playlistUrl.resolve(firstMedia);
    final isNestedPlaylist = firstMedia.toLowerCase().contains('.m3u8');
    final segmentUri = isNestedPlaylist
        ? await _firstNestedSegment(firstUri, headers)
        : firstUri;
    if (segmentUri == null) {
      return 'HLS variant playlist has no media segments';
    }

    try {
      final response = await _dio.get<List<int>>(
        segmentUri.toString(),
        options: Options(
          headers: {...headers, 'Range': 'bytes=0-1'},
          responseType: ResponseType.bytes,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      final status = response.statusCode ?? 0;
      final contentType = response.headers.value(Headers.contentTypeHeader);
      final preview = _decodePreview(response.data ?? const []);
      final kind = _classify(
        source: segmentUri.toString(),
        contentType: contentType,
        bodyPreview: preview,
        isHlsHint: false,
      );
      _streamRuntimeLog('Segment URL: $segmentUri');
      _streamRuntimeLog('Segment HTTP Status: $status');
      _streamRuntimeLog('Segment Content-Type: ${contentType ?? 'unknown'}');
      if (status < 200 || status >= 400) return 'Segment HTTP $status';
      if (kind == StreamContentKind.html) {
        return 'Segment returned HTML instead of media';
      }
      return null;
    } on DioException catch (error) {
      _streamRuntimeLog('Segment request failed: ${error.message}');
      return 'Segment request failed';
    }
  }

  Future<Uri?> _firstNestedSegment(
    Uri nestedPlaylistUri,
    Map<String, String> headers,
  ) async {
    try {
      final response = await _dio.get<String>(
        nestedPlaylistUri.toString(),
        options: Options(
          headers: {
            ...headers,
            'Accept':
                'application/vnd.apple.mpegurl, application/x-mpegURL, */*',
          },
          responseType: ResponseType.plain,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 600,
        ),
      );
      _streamRuntimeLog('Variant Playlist URL: ${response.realUri}');
      _streamRuntimeLog(
        'Variant HTTP Status: ${response.statusCode ?? 'unknown'}',
      );
      _streamRuntimeLog(
        'Variant Content-Type: '
        '${response.headers.value(Headers.contentTypeHeader) ?? 'unknown'}',
      );
      final status = response.statusCode ?? 0;
      if (status < 200 || status >= 400) return null;
      final media = _firstPlaylistUri(response.data ?? '');
      return media == null ? null : response.realUri.resolve(media);
    } on DioException catch (error) {
      _streamRuntimeLog('Variant playlist request failed: ${error.message}');
      return null;
    }
  }

  static String? _firstPlaylistUri(String playlist) {
    for (final raw in playlist.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      return line;
    }
    return null;
  }
}

class DesktopStreamingService implements StreamResolver {
  DesktopStreamingService({
    NetMirrorStreamProvider? netMirror,
    List<AnimeStreamProvider>? animeProviders,
    ProviderRegistry? providerRegistry,
    StreamHealthChecker? healthChecker,
    BuiltInLiveTvProviders? builtInLiveTvProviders,
  }) : _registry =
           providerRegistry ??
           ProviderRegistry.androidParity(
             netMirror: netMirror,
             animeProviders: animeProviders,
           ),
       _healthChecker = healthChecker ?? DesktopStreamHealthChecker(),
       _builtInLiveTvProviders =
           builtInLiveTvProviders ?? BuiltInLiveTvProviders();

  final ProviderRegistry _registry;
  final StreamHealthChecker _healthChecker;
  final BuiltInLiveTvProviders _builtInLiveTvProviders;
  String? _lastFailure;
  String? _enumeratedSourcesKey;
  List<PlaybackSourceOption>? _enumeratedSources;

  @override
  Future<List<PlaybackSourceOption>> availableSources(
    PlaybackRequest request,
  ) async {
    if (request.hasPlayableSource) return const [];
    final key = _sourcesKey(request);
    final enumerated = _enumeratedSources;
    if (_enumeratedSourcesKey == key && enumerated != null) {
      _enumeratedSourcesKey = null;
      _enumeratedSources = null;
      PlaybackRuntimeDiagnostics.streamLog(
        'Reused source enumeration count=${enumerated.length}',
      );
      return enumerated;
    }
    return _sourcesFor(request);
  }

  @override
  Future<StreamResult> resolve(
    PlaybackRequest request, {
    StreamResolutionStatus? onStatus,
  }) async {
    final resolveClock = Stopwatch()..start();
    PlaybackRuntimeDiagnostics.streamLog(
      'Resolver entered media=${request.mediaId}',
      clock: resolveClock,
    );
    if (request.hasPlayableSource) {
      onStatus?.call(
        request.mediaType == PlaybackMediaType.liveTv
            ? 'Opening live stream...'
            : 'Opening downloaded media...',
      );
      if (request.mediaType == PlaybackMediaType.liveTv &&
          BuiltInLiveTvProviders.isBuiltInSource(request.source!)) {
        final resolved = await _builtInLiveTvProviders.resolve(request.source!);
        if (resolved == null) {
          throw const StreamResolutionException(
            'The built-in live channel stream is unavailable.',
          );
        }
        final playable = await _selectPlayableSource(
          resolved,
          PlaybackSourceOption(
            index: 0,
            provider: resolved.provider,
            server: resolved.serverName ?? resolved.provider,
            group: resolved.provider,
          ),
        );
        if (playable != null) {
          PlaybackRuntimeDiagnostics.streamLog(
            'Built-in live source validated provider=${resolved.provider}',
            clock: resolveClock,
          );
          return playable;
        }
        throw const StreamResolutionException(
          'The built-in live channel stream is unavailable.',
        );
      }
      final direct = StreamResult(
        url: request.source!,
        quality: 'auto',
        provider: request.mediaType == PlaybackMediaType.liveTv
            ? 'IPTV'
            : 'Local',
        isM3U8: _isHls(request.source!),
        headers: request.httpHeaders,
      );
      final playable = await _selectPlayableSource(
        direct,
        PlaybackSourceOption(
          index: 0,
          provider: direct.provider,
          server: direct.provider,
        ),
      );
      if (playable != null) {
        PlaybackRuntimeDiagnostics.streamLog(
          'Direct source validated',
          clock: resolveClock,
        );
        return playable;
      }
      throw StreamResolutionException(
        request.mediaType == PlaybackMediaType.liveTv
            ? 'The live channel stream is unavailable.'
            : 'The downloaded media file is missing or unreadable.',
      );
    }

    if (request.numericMediaId == null) {
      throw const StreamResolutionException(
        'The selected media has an invalid identifier.',
        canRetry: false,
      );
    }

    final result = await _resolveRegistered(request, onStatus);
    PlaybackRuntimeDiagnostics.streamLog(
      'Resolver completed provider=${result.provider}',
      clock: resolveClock,
    );
    return result;
  }

  Future<StreamResult> resolveDownloadable(
    PlaybackRequest request, {
    StreamResolutionStatus? onStatus,
  }) async {
    if (request.numericMediaId == null) {
      throw const StreamResolutionException(
        'The selected media has an invalid identifier.',
        canRetry: false,
      );
    }

    _lastFailure = null;
    final providers = _registry.providersFor(request);
    final allSources =
        (await _sourcesFor(
              request,
              respectPreferredAnimeSource: request.providerIndex == null,
            ))
            .where((source) => source.directMedia && !source.iframeOnly)
            .toList(growable: false);
    if (allSources.isEmpty) {
      throw const StreamResolutionException(
        'No downloadable providers are available for this media.',
        canRetry: false,
      );
    }
    final requestedIndex = request.providerIndex;
    final sources = requestedIndex == null
        ? allSources
        : allSources
              .where((source) => source.index == requestedIndex)
              .toList(growable: false);
    if (sources.isEmpty) {
      throw const StreamResolutionException(
        'Selected server is not downloadable.',
        canRetry: false,
      );
    }

    for (final source in sources) {
      final provider = providers
          .where((provider) => provider.metadata.id == source.providerId)
          .firstOrNull;
      if (provider == null ||
          !provider.capabilities.download ||
          !provider.capabilities.directMedia) {
        continue;
      }

      onStatus?.call('Preparing ${source.label} download...');
      final resolution = await provider
          .resolve(request, source: source)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      final result = resolution?.result;
      if (result == null || result.isIframe) {
        _lastFailure =
            '${source.provider} / ${source.server} returned no direct stream.';
        continue;
      }

      final playable = await _selectPlayableSource(result, source);
      if (playable != null) return playable;
    }

    throw StreamResolutionException(
      _lastFailure ??
          'No downloadable stream is currently available from the configured providers.',
    );
  }

  Future<StreamResult> _resolveRegistered(
    PlaybackRequest request,
    StreamResolutionStatus? onStatus,
  ) async {
    _lastFailure = null;
    final sources = await _sourcesFor(
      request,
      respectPreferredAnimeSource: request.providerIndex == null,
    );
    _enumeratedSourcesKey = _sourcesKey(request);
    _enumeratedSources = List.unmodifiable(sources);
    if (sources.isEmpty) {
      throw const StreamResolutionException(
        'No providers are available for this media.',
        canRetry: false,
      );
    }

    final requestedIndex = request.providerIndex;
    final orderedSources = requestedIndex == null
        ? sources
        : sources.where((source) => source.index >= requestedIndex).toList();
    final fallbackSources = orderedSources.isEmpty ? sources : orderedSources;

    for (final source in fallbackSources) {
      onStatus?.call('Trying ${source.label}...');
      _runtimeLog('Provider: ${source.provider}');
      _runtimeLog('Server: ${source.server}');
      final provider = _registry
          .providersFor(request)
          .where((provider) => provider.metadata.id == source.providerId)
          .firstOrNull;
      if (provider == null) {
        _lastFailure = 'Provider ${source.provider} is not registered.';
        continue;
      }

      final resolution = await provider
          .resolve(request, source: source)
          .timeout(const Duration(seconds: 25), onTimeout: () => null);
      final result = resolution?.result;
      if (result == null) {
        _lastFailure =
            '${source.provider} / ${source.server} returned no stream.';
        _runtimeLog('Failure Reason: $_lastFailure');
        continue;
      }
      _runtimeLog('Resolved URL: ${result.url}');
      _runtimeLog('Resolved stream type: ${_resultType(result)}');
      if (source.iframeOnly || result.isIframe) {
        _runtimeLog('Backend Selected: WebPlaybackEngine');
        return result;
      }
      final playable = await _selectPlayableSource(result, source);
      if (playable != null) return playable;
    }

    throw StreamResolutionException(
      _lastFailure ??
          'No stream is currently available from the configured providers.',
    );
  }

  Future<List<PlaybackSourceOption>> _sourcesFor(
    PlaybackRequest request, {
    bool respectPreferredAnimeSource = true,
  }) async {
    final preferredAnimeProvider = request.mediaType == PlaybackMediaType.anime
        ? await _preferredAnimeSourceId()
        : null;
    final requestedAnimeProvider = request.mediaType == PlaybackMediaType.anime
        ? _animeProviderIdForIndex(request.providerIndex)
        : null;
    final scopedAnimeProvider =
        requestedAnimeProvider ??
        (respectPreferredAnimeSource ? preferredAnimeProvider : null);
    final sources = scopedAnimeProvider == null
        ? await _registry.sourcesFor(request)
        : await _registry.sourcesFor(
            request,
            providerIds: {scopedAnimeProvider},
          );
    if (sources.isEmpty && scopedAnimeProvider != null) {
      return _registry.sourcesFor(request);
    }
    if (!respectPreferredAnimeSource ||
        request.mediaType != PlaybackMediaType.anime ||
        sources.length < 2) {
      return sources;
    }

    final preferred = preferredAnimeProvider;
    if (preferred == null) return sources;

    final ordered = [...sources]
      ..sort((a, b) {
        final aPreferred = a.providerId == preferred;
        final bPreferred = b.providerId == preferred;
        if (aPreferred == bPreferred) return a.index.compareTo(b.index);
        return aPreferred ? -1 : 1;
      });
    return ordered;
  }

  Future<String?> _preferredAnimeSourceId() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        const Duration(milliseconds: 250),
      );
      final preferred = prefs.getString('preferred_anime_source')?.trim();
      if (preferred == null || preferred.isEmpty) return null;
      return preferred.toLowerCase();
    } catch (_) {
      return null;
    }
  }

  String? _animeProviderIdForIndex(int? providerIndex) {
    if (providerIndex == null) return null;
    if (providerIndex >= 10000 && providerIndex < 11000) return 'animex';
    if (providerIndex >= 11000 && providerIndex < 12000) return 'xon';
    return null;
  }

  static String _sourcesKey(PlaybackRequest request) {
    return '${request.mediaId}|${request.mediaTypeName}|${request.title}|'
        '${request.season}|${request.episode}|${request.providerIndex}|'
        '${request.preferredQuality}|${request.preferredAudioTrack}';
  }

  Future<StreamResult?> _selectPlayableSource(
    StreamResult result,
    PlaybackSourceOption sourceOption,
  ) async {
    final candidates = <StreamSource>[
      StreamSource(
        url: result.url,
        quality: result.quality,
        isM3U8: result.isM3U8,
      ),
      ...result.sources.where((source) => source.url != result.url),
    ];

    for (final source in candidates) {
      if (source.url.trim().isEmpty) continue;
      _runtimeLog('Validating final URL: ${source.url}');
      final validation = await _healthChecker
          .validate(
            source.url,
            result.headers,
            isHls: source.isM3U8 || _isHls(source.url),
          )
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => const StreamValidationResult(
              playable: false,
              kind: StreamContentKind.unknown,
              failureReason: 'Validation timed out',
            ),
          );
      _runtimeLog('HTTP Status: ${validation.statusCode ?? 'unknown'}');
      _runtimeLog('Content-Type: ${validation.contentType ?? 'unknown'}');
      _runtimeLog('Final URL: ${validation.finalUrl ?? source.url}');
      _runtimeLog('Detected Type: ${validation.kind.name}');
      if (validation.playable) {
        _runtimeLog('Backend Selected: media_kit');
        return result.copyWith(
          url: source.url,
          quality: source.quality,
          isM3U8: source.isM3U8 || _isHls(source.url),
          isDirect: true,
          isIframe: false,
        );
      }
      _runtimeLog(
        'Failure Reason: ${validation.failureReason ?? 'Not playable'} '
        '(${sourceOption.provider} / ${sourceOption.server})',
      );
      _lastFailure =
          '${sourceOption.provider} / ${sourceOption.server}: '
          '${validation.failureReason ?? 'Not playable'}';
    }
    return null;
  }

  static bool _isHls(String source) => source.toLowerCase().contains('.m3u8');

  static String _resultType(StreamResult result) {
    if (result.isIframe) return 'iframe page';
    if (result.isM3U8 || _isHls(result.url)) return 'HLS (.m3u8)';
    final lower = result.url.toLowerCase();
    if (lower.contains('.mpd')) return 'DASH (.mpd)';
    if (lower.contains('.mp4')) return 'MP4';
    return result.isDirect ? 'direct media' : 'unknown';
  }

  static void _runtimeLog(String message) {
    _streamRuntimeLog(message);
  }
}

void _streamRuntimeLog(String message) {
  PlaybackRuntimeDiagnostics.streamLog(message);
}
