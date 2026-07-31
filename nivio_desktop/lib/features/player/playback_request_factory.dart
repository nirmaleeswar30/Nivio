import '../../shared/models/iptv_channel.dart';
import '../../shared/models/watch_party_models.dart';
import '../details/models/detail_models.dart';
import '../library/models/library_models.dart';
import '../search/models/search_media_item.dart';
import 'models/playback_request.dart';

class PlaybackRequestFactory {
  const PlaybackRequestFactory._();

  static PlaybackRequest fromCompositeId(String id, String title) {
    final type = id.contains(':') ? id.split(':').first : 'unknown';
    return PlaybackRequest(
      mediaId: id,
      title: title,
      mediaType: _fromName(type),
    );
  }

  static PlaybackRequest fromSearchItem(
    SearchMediaItem item, {
    int? season,
    int? episode,
  }) {
    return PlaybackRequest(
      mediaId: item.id,
      title: item.title,
      mediaType: _fromSearchType(item.mediaType),
      posterPath: item.posterPath ?? item.backdropPath,
      season: season,
      episode: episode,
    );
  }

  static PlaybackRequest fromDetail(
    DetailMedia media, {
    int? season,
    int? episode,
    int? totalEpisodes,
  }) {
    return PlaybackRequest(
      mediaId: media.id,
      title: media.title,
      mediaType: _fromDetailType(media.mediaType),
      posterPath: media.posterPath ?? media.backdropPath,
      season: season,
      episode: episode,
      totalSeasons: _seasonCount(media),
      totalEpisodes: totalEpisodes ?? _episodeCount(media, season),
    );
  }

  static PlaybackRequest fromHistory(Map<String, dynamic> item) {
    final type = (item['mediaType'] ?? item['type'] ?? 'movie').toString();
    final rawId = item['tmdbId'] ?? item['mediaId'] ?? item['id'];
    final idText = rawId?.toString() ?? '';
    final compositeId = idText.contains(':') ? idText : '$type:$idText';
    final mediaType = _fromName(type);
    final isSeries =
        mediaType == PlaybackMediaType.tv ||
        mediaType == PlaybackMediaType.anime;
    return PlaybackRequest(
      mediaId: compositeId,
      title: (item['title'] ?? item['name'] ?? 'Untitled').toString(),
      mediaType: mediaType,
      posterPath: (item['posterPath'] ?? item['poster_path'])?.toString(),
      season: isSeries ? _int(item['currentSeason'] ?? item['season']) : null,
      episode: isSeries
          ? _int(item['currentEpisode'] ?? item['episode'])
          : null,
      totalSeasons: _int(item['totalSeasons']) ?? 1,
      totalEpisodes: _int(item['totalEpisodes']),
      providerIndex: _int(item['preferredProviderIndex']),
      preferredAudioTrack: item['preferredAudioTrack']?.toString(),
      preferredSubtitleTrack: item['preferredSubtitleTrack']?.toString(),
      preferredQuality: item['preferredResolution']?.toString(),
    );
  }

  static PlaybackRequest fromWatchlist(LibraryWatchlistItem item) {
    return PlaybackRequest(
      mediaId: '${item.mediaType}:${item.id}',
      title: item.title,
      mediaType: _fromName(item.mediaType),
      posterPath: item.posterPath,
    );
  }

  static PlaybackRequest fromDownload(LibraryDownloadItem item) {
    return PlaybackRequest(
      mediaId: '${item.mediaType}:${item.mediaId}',
      title: item.title.split('|||').first,
      mediaType: _fromName(item.mediaType),
      posterPath: item.posterPath,
      source: item.savePath,
      httpHeaders: item.headers ?? const {},
      season: item.season,
      episode: item.episode,
    );
  }

  static PlaybackRequest fromIptv(IptvChannel channel) {
    return PlaybackRequest(
      mediaId:
          'live:${channel.tvgId.isEmpty ? channel.name.hashCode : channel.tvgId}',
      title: channel.name,
      mediaType: PlaybackMediaType.liveTv,
      source: channel.url,
      isLive: true,
    );
  }

  static PlaybackRequest fromParty(
    WatchPartyPlaybackState state, {
    String? partyCode,
    String? partyRole,
  }) {
    return PlaybackRequest(
      mediaId: '${state.mediaType}:${state.mediaId}',
      title: 'Media ${state.mediaId}',
      mediaType: _fromName(state.mediaType),
      season: state.season,
      episode: state.episode,
      providerIndex: state.providerIndex,
      watchPartyCode: partyCode,
      watchPartyRole: partyRole,
      startPosition: Duration(milliseconds: state.expectedPositionMs),
    );
  }

  static PlaybackMediaType _fromSearchType(SearchMediaTypeFilter type) {
    return switch (type) {
      SearchMediaTypeFilter.movie => PlaybackMediaType.movie,
      SearchMediaTypeFilter.tv => PlaybackMediaType.tv,
      SearchMediaTypeFilter.anime => PlaybackMediaType.anime,
      SearchMediaTypeFilter.all => PlaybackMediaType.unknown,
    };
  }

  static PlaybackMediaType _fromDetailType(DetailMediaType type) {
    return switch (type) {
      DetailMediaType.movie => PlaybackMediaType.movie,
      DetailMediaType.tv => PlaybackMediaType.tv,
      DetailMediaType.anime => PlaybackMediaType.anime,
      DetailMediaType.live => PlaybackMediaType.liveTv,
    };
  }

  static PlaybackMediaType _fromName(String type) {
    return switch (type.trim().toLowerCase()) {
      'movie' => PlaybackMediaType.movie,
      'tv' => PlaybackMediaType.tv,
      'anime' => PlaybackMediaType.anime,
      'live' || 'livetv' || 'live_tv' => PlaybackMediaType.liveTv,
      _ => PlaybackMediaType.unknown,
    };
  }

  static int? _int(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static int? _episodeCount(DetailMedia media, int? season) {
    if (!media.isSeries || media.seasons.isEmpty) return null;
    final selected = season ?? media.seasons.first.number;
    for (final item in media.seasons) {
      if (item.number == selected) {
        if (item.episodes.isNotEmpty) return item.episodes.length;
        final count = item.episodeCount;
        return count != null && count > 0 ? count : null;
      }
    }
    return null;
  }

  static int _seasonCount(DetailMedia media) {
    if (!media.isSeries) return 1;
    final seasons = media.seasons.where((season) => season.number > 0).length;
    return seasons <= 0 ? 1 : seasons;
  }
}
