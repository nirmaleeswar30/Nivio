import '../../../shared/models/stream_result.dart';
import '../models/playback_request.dart';
import 'anime_stream_providers.dart';
import 'castle_tv_stream_provider.dart';
import 'moviebox_stream_provider.dart';
import 'netmirror_stream_provider.dart';
import 'stream_resolver.dart';
import 'streamflix_stream_provider.dart';

enum StreamProviderKind { direct, iframe }

enum StreamProviderErrorKind {
  unavailable,
  unsupported,
  authenticationRequired,
  network,
  timeout,
  invalidResponse,
}

class StreamProviderCapabilities {
  const StreamProviderCapabilities({
    required this.directMedia,
    required this.iframe,
    this.hls = false,
    this.dash = false,
    this.subtitles = false,
    this.audioTracks = false,
    this.qualitySelection = false,
    this.download = false,
  });

  final bool directMedia;
  final bool iframe;
  final bool hls;
  final bool dash;
  final bool subtitles;
  final bool audioTracks;
  final bool qualitySelection;
  final bool download;
}

class StreamProviderMetadata {
  const StreamProviderMetadata({
    required this.id,
    required this.displayName,
    required this.priority,
    required this.kind,
    required this.supportedMediaTypes,
  });

  final String id;
  final String displayName;
  final int priority;
  final StreamProviderKind kind;
  final Set<PlaybackMediaType> supportedMediaTypes;
}

class StreamProviderDiagnostics {
  const StreamProviderDiagnostics({
    required this.providerId,
    required this.providerName,
    required this.server,
    required this.capabilities,
    this.lastError,
    this.errorKind,
  });

  final String providerId;
  final String providerName;
  final String server;
  final StreamProviderCapabilities capabilities;
  final String? lastError;
  final StreamProviderErrorKind? errorKind;
}

class StreamResolution {
  const StreamResolution({required this.result, required this.diagnostics});

  final StreamResult result;
  final StreamProviderDiagnostics diagnostics;
}

abstract interface class RegisteredStreamProvider {
  StreamProviderMetadata get metadata;
  StreamProviderCapabilities get capabilities;

  bool supports(PlaybackRequest request);
  Map<String, String> requestHeaders(PlaybackRequest request);
  Future<List<PlaybackSourceOption>> enumerateServers(PlaybackRequest request);
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  });
}

class ProviderRegistry {
  ProviderRegistry(List<RegisteredStreamProvider> providers)
    : _providers = List.unmodifiable(
        [...providers]
          ..sort((a, b) => a.metadata.priority.compareTo(b.metadata.priority)),
      );

  factory ProviderRegistry.androidParity({
    NetMirrorStreamProvider? netMirror,
    CastleTvStreamProvider? castleTv,
    MovieBoxStreamProvider? movieBox,
    StreamFlixStreamProvider? streamFlix,
    List<AnimeStreamProvider>? animeProviders,
  }) {
    final anime =
        animeProviders ?? [AnimexStreamProvider(), XonStreamProvider()];
    return ProviderRegistry([
      NivioProviderAdapter(netMirror ?? NetMirrorStreamProvider()),
      CastleTvProviderAdapter(castleTv ?? CastleTvStreamProvider()),
      MovieBoxProviderAdapter(movieBox ?? MovieBoxStreamProvider()),
      StreamFlixProviderAdapter(streamFlix ?? StreamFlixStreamProvider()),
      const IframeProviderAdapter.vidUp(),
      const IframeProviderAdapter.vidLink(),
      const IframeProviderAdapter.vidCore(),
      for (var index = 0; index < anime.length; index++)
        AnimeProviderAdapter(
          priority: 100 + (index * 10),
          provider: anime[index],
        ),
    ]);
  }

  final List<RegisteredStreamProvider> _providers;

  List<RegisteredStreamProvider> providersFor(PlaybackRequest request) {
    return _providers
        .where((provider) => provider.supports(request))
        .toList(growable: false);
  }

  Future<List<PlaybackSourceOption>> sourcesFor(
    PlaybackRequest request, {
    Set<String>? providerIds,
  }) async {
    final options = <PlaybackSourceOption>[];
    for (final provider in providersFor(request)) {
      if (providerIds != null && !providerIds.contains(provider.metadata.id)) {
        continue;
      }
      options.addAll(await provider.enumerateServers(request));
    }
    options.sort((a, b) => a.index.compareTo(b.index));
    return options;
  }
}

class StreamFlixProviderAdapter implements RegisteredStreamProvider {
  const StreamFlixProviderAdapter(this._provider);

  final StreamFlixStreamProvider _provider;

  @override
  StreamProviderMetadata get metadata => const StreamProviderMetadata(
    id: 'streamflix',
    displayName: StreamFlixStreamProvider.providerName,
    priority: 8,
    kind: StreamProviderKind.direct,
    supportedMediaTypes: {PlaybackMediaType.movie, PlaybackMediaType.tv},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: true,
        iframe: false,
        subtitles: true,
        audioTracks: true,
        qualitySelection: false,
        download: true,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.tv ||
      request.mediaType == PlaybackMediaType.unknown;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return const [
      PlaybackSourceOption(
        index: 8,
        provider: StreamFlixStreamProvider.providerName,
        server: StreamFlixStreamProvider.providerName,
        providerId: 'streamflix',
        directMedia: true,
        iframeOnly: false,
      ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final result = await _provider.resolve(request);
    if (result == null) return null;
    return StreamResolution(
      result: result.copyWith(
        providerIndex: source.index,
        providerGroup: source.provider,
        serverName: source.server,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }
}

class MovieBoxProviderAdapter implements RegisteredStreamProvider {
  const MovieBoxProviderAdapter(this._provider);

  final MovieBoxStreamProvider _provider;

  @override
  StreamProviderMetadata get metadata => const StreamProviderMetadata(
    id: 'moviebox',
    displayName: MovieBoxStreamProvider.providerName,
    priority: 7,
    kind: StreamProviderKind.direct,
    supportedMediaTypes: {PlaybackMediaType.movie},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: true,
        iframe: false,
        subtitles: true,
        audioTracks: true,
        qualitySelection: true,
        download: true,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.unknown;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return const [
      PlaybackSourceOption(
        index: 7,
        provider: MovieBoxStreamProvider.providerName,
        server: MovieBoxStreamProvider.providerName,
        providerId: 'moviebox',
        directMedia: true,
        iframeOnly: false,
      ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final result = await _provider.resolve(request);
    if (result == null) return null;
    return StreamResolution(
      result: result.copyWith(
        providerIndex: source.index,
        providerGroup: source.provider,
        serverName: source.server,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }
}

class CastleTvProviderAdapter implements RegisteredStreamProvider {
  const CastleTvProviderAdapter(this._provider);

  final CastleTvStreamProvider _provider;

  @override
  StreamProviderMetadata get metadata => const StreamProviderMetadata(
    id: 'castletv',
    displayName: CastleTvStreamProvider.providerName,
    priority: 5,
    kind: StreamProviderKind.direct,
    supportedMediaTypes: {PlaybackMediaType.movie, PlaybackMediaType.tv},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: true,
        iframe: false,
        subtitles: true,
        audioTracks: true,
        qualitySelection: true,
        download: true,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.tv ||
      request.mediaType == PlaybackMediaType.unknown;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return const [
      PlaybackSourceOption(
        index: 5,
        provider: CastleTvStreamProvider.providerName,
        server: CastleTvStreamProvider.providerName,
        providerId: 'castletv',
        directMedia: true,
        iframeOnly: false,
      ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final result = await _provider.resolve(request);
    if (result == null) return null;
    return StreamResolution(
      result: result.copyWith(
        providerIndex: source.index,
        providerGroup: source.provider,
        serverName: source.server,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }
}

class NivioProviderAdapter implements RegisteredStreamProvider {
  const NivioProviderAdapter(this._provider);

  final NetMirrorStreamProvider _provider;

  @override
  StreamProviderMetadata get metadata => const StreamProviderMetadata(
    id: 'nivio',
    displayName: 'Nivio',
    priority: 0,
    kind: StreamProviderKind.direct,
    supportedMediaTypes: {PlaybackMediaType.movie, PlaybackMediaType.tv},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: true,
        iframe: false,
        hls: true,
        subtitles: true,
        audioTracks: true,
        qualitySelection: true,
        download: true,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.tv ||
      request.mediaType == PlaybackMediaType.unknown;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return const [
      PlaybackSourceOption(
        index: 0,
        provider: 'Nivio',
        server: 'Nivio',
        providerId: 'nivio',
        directMedia: true,
        iframeOnly: false,
      ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final result = await _provider.resolve(request);
    if (result == null) return null;
    return StreamResolution(
      result: result.copyWith(
        providerIndex: source.index,
        providerGroup: source.provider,
        serverName: source.server,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }
}

class AnimeProviderAdapter implements RegisteredStreamProvider {
  const AnimeProviderAdapter({required this.priority, required this.provider});

  final int priority;
  final AnimeStreamProvider provider;

  @override
  StreamProviderMetadata get metadata => StreamProviderMetadata(
    id: provider.name.toLowerCase(),
    displayName: provider.name,
    priority: priority,
    kind: StreamProviderKind.direct,
    supportedMediaTypes: const {PlaybackMediaType.anime},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: true,
        iframe: false,
        hls: true,
        subtitles: true,
        audioTracks: true,
        qualitySelection: true,
        download: true,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.anime;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    final servers = await provider.availableServers(request);
    final resolvedServers = provider is XonStreamProvider
        ? servers
        : provider is AnimetsuStreamProvider
        ? const ['auto', 'kite', 'dio', 'sage', 'meg']
        : servers.isEmpty
        ? [provider is MiruroStreamProvider ? 'zoro' : 'mimi']
        : servers;

    final base = priority * 100;
    return [
      for (var i = 0; i < resolvedServers.length; i++)
        PlaybackSourceOption(
          index: base + i,
          provider: provider.name,
          server: resolvedServers[i],
          group: provider.name,
          providerId: provider.name.toLowerCase(),
          directMedia: true,
          iframeOnly: false,
        ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final result = await provider.resolve(request, server: source.server);
    if (result == null) return null;
    return StreamResolution(
      result: result.copyWith(
        providerIndex: source.index,
        providerGroup: provider.name,
        serverName: source.server,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: metadata.id,
        providerName: metadata.displayName,
        server: source.server,
        capabilities: capabilities,
      ),
    );
  }
}

class IframeProviderAdapter implements RegisteredStreamProvider {
  const IframeProviderAdapter({
    required this.id,
    required this.name,
    required this.priority,
    required this.movieUrl,
    required this.tvUrl,
  });

  const IframeProviderAdapter.vidUp()
    : this(
        id: 'vidup',
        name: 'VidUp (FAST)',
        priority: 10,
        movieUrl: 'https://vidup.to/movie/{id}',
        tvUrl: 'https://vidup.to/tv/{id}/{season}/{episode}',
      );

  const IframeProviderAdapter.vidLink()
    : this(
        id: 'vidlink',
        name: 'VidLink',
        priority: 20,
        movieUrl: 'https://vidlink.pro/movie/{id}',
        tvUrl: 'https://vidlink.pro/tv/{id}/{season}/{episode}',
      );

  const IframeProviderAdapter.vidCore()
    : this(
        id: 'vidcore',
        name: 'VidCore (ACTIVE)',
        priority: 30,
        movieUrl: 'https://vidcore.net/movie/{id}',
        tvUrl: 'https://vidcore.net/tv/{id}/{season}/{episode}',
      );

  const IframeProviderAdapter.vidPlus()
    : this(
        id: 'vidplus',
        name: 'VidPlus',
        priority: 40,
        movieUrl: 'https://player.vidplus.to/embed/movie/{id}',
        tvUrl: 'https://player.vidplus.to/embed/tv/{id}/{season}/{episode}',
      );

  final String id;
  final String name;
  final int priority;
  final String movieUrl;
  final String tvUrl;

  @override
  StreamProviderMetadata get metadata => StreamProviderMetadata(
    id: id,
    displayName: name,
    priority: priority,
    kind: StreamProviderKind.iframe,
    supportedMediaTypes: const {PlaybackMediaType.movie, PlaybackMediaType.tv},
  );

  @override
  StreamProviderCapabilities get capabilities =>
      const StreamProviderCapabilities(
        directMedia: false,
        iframe: true,
        subtitles: false,
        audioTracks: false,
        qualitySelection: false,
        download: false,
      );

  @override
  bool supports(PlaybackRequest request) =>
      request.mediaType == PlaybackMediaType.movie ||
      request.mediaType == PlaybackMediaType.tv ||
      request.mediaType == PlaybackMediaType.unknown;

  @override
  Map<String, String> requestHeaders(PlaybackRequest request) => const {};

  @override
  Future<List<PlaybackSourceOption>> enumerateServers(
    PlaybackRequest request,
  ) async {
    return [
      PlaybackSourceOption(
        index: priority,
        provider: name,
        server: name,
        providerId: id,
        directMedia: false,
        iframeOnly: true,
      ),
    ];
  }

  @override
  Future<StreamResolution?> resolve(
    PlaybackRequest request, {
    required PlaybackSourceOption source,
  }) async {
    final url = iframeUrl(request);
    if (url == null) return null;
    return StreamResolution(
      result: StreamResult(
        url: url,
        quality: 'Auto',
        provider: name,
        providerIndex: source.index,
        providerGroup: name,
        serverName: name,
        isDirect: false,
        isIframe: true,
      ),
      diagnostics: StreamProviderDiagnostics(
        providerId: id,
        providerName: name,
        server: name,
        capabilities: capabilities,
        lastError:
            'Iframe provider requires WebKitGTK fallback; direct media URL is not exposed by Android.',
        errorKind: StreamProviderErrorKind.unsupported,
      ),
    );
  }

  String? iframeUrl(PlaybackRequest request) {
    final id = request.numericMediaId;
    if (id == null) return null;
    final template = request.mediaType == PlaybackMediaType.movie
        ? movieUrl
        : tvUrl;
    return template
        .replaceAll('{id}', '$id')
        .replaceAll('{season}', '${request.season ?? 1}')
        .replaceAll('{episode}', '${request.episode ?? 1}');
  }
}
