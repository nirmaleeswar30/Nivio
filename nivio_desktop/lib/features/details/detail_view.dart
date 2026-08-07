import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import '../../core/network/image/tmdb_image_builder.dart';
import '../../core/interfaces/watch_history_repository.dart';
import '../../shared/models/stream_result.dart';
import '../library/services/watchlist_sync_controller.dart';
import '../library/models/library_models.dart';
import '../library/services/desktop_download_service.dart';
import '../library/services/library_persistence.dart';
import '../player/models/playback_request.dart';
import '../player/playback_request_factory.dart';
import '../player/services/desktop_streaming_service.dart';
import '../player/services/m3u8_parser.dart';
import '../player/services/stream_resolver.dart';
import 'models/detail_models.dart';
import 'models/detail_route_args.dart';
import 'controllers/detail_controller.dart';
import 'widgets/download_prompt.dart';

typedef WatchTogetherLauncher = void Function(DetailMedia media, int season);

class DetailView extends StatefulWidget {
  const DetailView({
    super.key,
    required this.args,
    required this.controller,
    required this.onBack,
    required this.onOpenDetail,
    required this.onPlay,
    required this.onWatchTogether,
    required this.watchHistoryRepository,
    this.homeOverlay = false,
  });

  final DetailRouteArgs args;
  final DetailController controller;
  final VoidCallback onBack;
  final ValueChanged<String> onOpenDetail;
  final ValueChanged<PlaybackRequest> onPlay;
  final WatchTogetherLauncher onWatchTogether;
  final WatchHistoryRepository watchHistoryRepository;
  final bool homeOverlay;

  @override
  State<DetailView> createState() => _DetailViewState();
}

class _DetailViewState extends State<DetailView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _moreLikeThisKey = GlobalKey();
  final WatchlistSyncController _watchlistController =
      WatchlistSyncController.instance;
  DetailMedia? _media;
  double _watchProgress = 0;
  int _selectedSeason = 1;
  int _resumeEpisode = 1;
  bool _inlineTrailerActive = false;

  @override
  void initState() {
    super.initState();
    _syncMedia();
    widget.controller.addListener(_onControllerChanged);
    _watchlistController.addListener(_onWatchlistChanged);
    if (widget.watchHistoryRepository case final Listenable listenable) {
      listenable.addListener(_onHistoryChanged);
    }
    unawaited(_syncWatchProgress());
  }

  @override
  void didUpdateWidget(covariant DetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.args != widget.args) {
      _syncMedia();
      unawaited(_syncWatchProgress());
    }
    if (oldWidget.watchHistoryRepository != widget.watchHistoryRepository) {
      if (oldWidget.watchHistoryRepository case final Listenable listenable) {
        listenable.removeListener(_onHistoryChanged);
      }
      if (widget.watchHistoryRepository case final Listenable listenable) {
        listenable.addListener(_onHistoryChanged);
      }
      unawaited(_syncWatchProgress());
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _watchlistController.removeListener(_onWatchlistChanged);
    if (widget.watchHistoryRepository case final Listenable listenable) {
      listenable.removeListener(_onHistoryChanged);
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _syncMedia() {
    final m = widget.controller.media;
    if (m != null) {
      if (_media?.id != m.id) {
        _inlineTrailerActive = false;
      }
      _media = _withWatchlistState(m);
      _watchProgress = m.resumeProgress;
      if (m.seasons.isNotEmpty) {
        _selectedSeason = _firstPlayableSeason(m);
      }
    }
  }

  void _onHistoryChanged() => unawaited(_syncWatchProgress());

  Future<void> _syncWatchProgress() async {
    final history = await widget.watchHistoryRepository.getWatchProgress(
      mediaId: widget.args.mediaId,
      mediaType: widget.args.mediaType,
    );
    if (!mounted || history == null) return;
    final position = (history['lastPositionSeconds'] as num?)?.toDouble() ?? 0;
    final duration = (history['totalDurationSeconds'] as num?)?.toDouble() ?? 0;
    final completed = history['isCompleted'] == true;
    final season = (history['currentSeason'] as num?)?.toInt() ?? 1;
    final episode = (history['currentEpisode'] as num?)?.toInt() ?? 1;
    final shouldLoadSeason =
        _media?.isSeries == true && _selectedSeason != season;
    setState(() {
      _watchProgress = completed || duration <= 0
          ? 0
          : (position / duration).clamp(0.0, 1.0);
      _resumeEpisode = episode;
      if (_media?.isSeries == true) _selectedSeason = season;
    });
    if (shouldLoadSeason) {
      widget.controller.loadSeasonEpisodes(widget.args.mediaId, season);
    }
  }

  void _onControllerChanged() {
    final m = widget.controller.media;
    if (m != null) {
      setState(() {
        _media = _withWatchlistState(m);
        if (m.seasons.isNotEmpty &&
            !m.seasons.any((season) => season.number == _selectedSeason)) {
          _selectedSeason = _firstPlayableSeason(m);
        }
      });
      unawaited(_syncWatchProgress());
    }
  }

  void _onWatchlistChanged() {
    final media = _media;
    if (media == null || !mounted) return;
    final inWatchlist = _watchlistController.isInWatchlist(media.id);
    if (media.isInWatchlist == inWatchlist) return;
    setState(() {
      _media = media.copyWith(isInWatchlist: inWatchlist);
    });
  }

  DetailMedia _withWatchlistState(DetailMedia media) {
    return media.copyWith(
      isInWatchlist: _watchlistController.isInWatchlist(media.id),
    );
  }

  int _firstPlayableSeason(DetailMedia media) {
    return media.seasons
        .firstWhere(
          (season) => season.number > 0,
          orElse: () => media.seasons.first,
        )
        .number;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final status = widget.controller.status;
        final media = widget.controller.media;

        if (status == DetailStatus.loading || status == DetailStatus.retrying) {
          if (widget.homeOverlay) {
            return _HomeOverlayStatus(
              onClose: widget.onBack,
              child: const CircularProgressIndicator(color: AppColors.primary),
            );
          }
          return const Scaffold(
            backgroundColor: AppColors.background,
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        if (status == DetailStatus.offline) {
          if (widget.homeOverlay) {
            return _HomeOverlayStatus(
              onClose: widget.onBack,
              child: _OverlayMessage(
                icon: LucideIcons.wifiOff,
                title: 'Offline',
                message:
                    widget.controller.errorMessage ?? 'No internet connection',
                actionLabel: 'Retry',
                onAction: widget.controller.retry,
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.wifiOff,
                        size: 64,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text('Offline', style: AppTypography.sectionTitle),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.controller.errorMessage ??
                            'No internet connection',
                        style: AppTypography.body,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: widget.controller.retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: AppSpacing.xl,
                  left: AppSpacing.xl,
                  child: _FloatingBackButton(onTap: widget.onBack),
                ),
              ],
            ),
          );
        }

        if (status == DetailStatus.apiError || status == DetailStatus.error) {
          if (widget.homeOverlay) {
            return _HomeOverlayStatus(
              onClose: widget.onBack,
              child: _OverlayMessage(
                icon: LucideIcons.alertTriangle,
                title: 'Error Loading Details',
                message: widget.controller.errorMessage ?? 'An error occurred',
                actionLabel: 'Retry',
                onAction: widget.controller.retry,
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        LucideIcons.alertTriangle,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Error Loading Details',
                        style: AppTypography.sectionTitle,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: Text(
                          widget.controller.errorMessage ?? 'An error occurred',
                          style: AppTypography.body,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      ElevatedButton(
                        onPressed: widget.controller.retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textPrimary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: AppSpacing.xl,
                  left: AppSpacing.xl,
                  child: _FloatingBackButton(onTap: widget.onBack),
                ),
              ],
            ),
          );
        }

        if (media == null || status == DetailStatus.empty) {
          if (widget.homeOverlay) {
            return _HomeOverlayStatus(
              onClose: widget.onBack,
              child: const _OverlayMessage(
                icon: LucideIcons.info,
                title: 'No details found',
                message: 'This title does not have details yet.',
              ),
            );
          }
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Stack(
              children: [
                const Center(child: Text('No details found')),
                Positioned(
                  top: AppSpacing.xl,
                  left: AppSpacing.xl,
                  child: _FloatingBackButton(onTap: widget.onBack),
                ),
              ],
            ),
          );
        }

        final displayMedia = _media?.id == media.id
            ? _media!
            : _withWatchlistState(media);
        _media = displayMedia;
        if (widget.homeOverlay) {
          return _buildHomeOverlayDetail(displayMedia);
        }

        return _buildFullPageDetail(displayMedia);
      },
    );
  }

  Widget _buildFullPageDetail(DetailMedia displayMedia) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final heroHeight = constraints.maxHeight.clamp(620.0, 820.0).toDouble();

        return Scaffold(
          backgroundColor: const Color(0xFF0F1016),
          body: Stack(
            children: [
              DesktopScrollbar(
                controller: _scrollController,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _HotstarModalHero(
                        media: displayMedia,
                        watchProgress: _watchProgress,
                        height: heroHeight,
                        contentLeft: AppSpacing.massive,
                        contentBottom: AppSpacing.massive,
                        contentWidth: 520,
                        logoWidth: 300,
                        titleFontSize: 54,
                        onPlay: () => _playMedia(
                          season: displayMedia.isSeries
                              ? _selectedSeason
                              : null,
                          episode: displayMedia.isSeries
                              ? _resumeEpisode
                              : null,
                        ),
                        onToggleWatchlist: _toggleWatchlist,
                        onDownload: () => _downloadFromHero(displayMedia),
                        inlineTrailerActive: _inlineTrailerActive,
                        onInlineTrailerExit: _stopInlineTrailer,
                        onWatchTrailer: displayMedia.trailers.isEmpty
                            ? null
                            : () => _playInlineTrailer(displayMedia),
                        onWatchTogether: () => widget.onWatchTogether(
                          displayMedia,
                          _selectedSeason,
                        ),
                      ),
                      _ModalTabsHeader(
                        primaryLabel: displayMedia.isSeries
                            ? 'Episodes'
                            : 'More Like This',
                        secondaryLabel: 'More Like This',
                        onSecondaryTap: _scrollToMoreLikeThis,
                      ),
                      if (displayMedia.isSeries)
                        _EpisodePlaybackSection(
                          media: displayMedia,
                          controller: widget.controller,
                          selectedSeason: _selectedSeason,
                          modalStyle: true,
                          onSeasonSelected: _selectSeason,
                          onPlayEpisode: (episode) => _playMedia(
                            season: _selectedSeason,
                            episode: episode.number,
                          ),
                          onDownloadEpisode: (episode) => _queueDownload(
                            displayMedia,
                            season: _selectedSeason,
                            episode: episode.number,
                            stillPath: episode.stillPath,
                          ),
                          onDownloadSeason: (episodes) => _queueSeasonDownload(
                            displayMedia,
                            season: _selectedSeason,
                            episodes: episodes,
                          ),
                        ),
                      _DetailBadgesSection(media: displayMedia),
                      _CastSection(media: displayMedia),
                      _RecommendationsSection(
                        key: _moreLikeThisKey,
                        media: displayMedia,
                        onOpenDetail: widget.onOpenDetail,
                        onPlay: widget.onPlay,
                      ),
                      const SizedBox(height: AppSpacing.xxxl),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: AppSpacing.xl,
                left: AppSpacing.xl,
                child: _FloatingBackButton(onTap: widget.onBack),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHomeOverlayDetail(DetailMedia displayMedia) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.massive,
            vertical: AppSpacing.xxl,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(760.0, 960.0).toDouble();
              final height = constraints.maxHeight
                  .clamp(620.0, 900.0)
                  .toDouble();

              return SizedBox(
                width: width,
                height: height,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F1016),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.7),
                          blurRadius: 54,
                          spreadRadius: -12,
                          offset: const Offset(0, 28),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        DesktopScrollbar(
                          controller: _scrollController,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            physics: const BouncingScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _HotstarModalHero(
                                  media: displayMedia,
                                  watchProgress: _watchProgress,
                                  onPlay: () => _playMedia(
                                    season: displayMedia.isSeries
                                        ? _selectedSeason
                                        : null,
                                    episode: displayMedia.isSeries
                                        ? _resumeEpisode
                                        : null,
                                  ),
                                  onToggleWatchlist: _toggleWatchlist,
                                  onDownload: () =>
                                      _downloadFromHero(displayMedia),
                                  inlineTrailerActive: _inlineTrailerActive,
                                  onInlineTrailerExit: _stopInlineTrailer,
                                  onWatchTrailer: displayMedia.trailers.isEmpty
                                      ? null
                                      : () => _playInlineTrailer(displayMedia),
                                  onWatchTogether: () => widget.onWatchTogether(
                                    displayMedia,
                                    _selectedSeason,
                                  ),
                                ),
                                _ModalTabsHeader(
                                  primaryLabel: displayMedia.isSeries
                                      ? 'Episodes'
                                      : 'More Like This',
                                  secondaryLabel: 'More Like This',
                                  onSecondaryTap: _scrollToMoreLikeThis,
                                ),
                                if (displayMedia.isSeries)
                                  _EpisodePlaybackSection(
                                    media: displayMedia,
                                    controller: widget.controller,
                                    selectedSeason: _selectedSeason,
                                    modalStyle: true,
                                    onSeasonSelected: _selectSeason,
                                    onPlayEpisode: (episode) => _playMedia(
                                      season: _selectedSeason,
                                      episode: episode.number,
                                    ),
                                    onDownloadEpisode: (episode) =>
                                        _queueDownload(
                                          displayMedia,
                                          season: _selectedSeason,
                                          episode: episode.number,
                                          stillPath: episode.stillPath,
                                        ),
                                    onDownloadSeason: (episodes) =>
                                        _queueSeasonDownload(
                                          displayMedia,
                                          season: _selectedSeason,
                                          episodes: episodes,
                                        ),
                                  ),
                                _DetailBadgesSection(media: displayMedia),
                                _CastSection(media: displayMedia),
                                _RecommendationsSection(
                                  key: _moreLikeThisKey,
                                  media: displayMedia,
                                  onOpenDetail: widget.onOpenDetail,
                                  onPlay: widget.onPlay,
                                ),
                                const SizedBox(height: AppSpacing.xxxl),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          top: AppSpacing.xl,
                          right: AppSpacing.xl,
                          child: IconButton(
                            tooltip: 'Close details',
                            onPressed: widget.onBack,
                            icon: const Icon(LucideIcons.x),
                            color: Colors.white,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(40),
                              backgroundColor: Colors.black.withValues(
                                alpha: 0.16,
                              ),
                              hoverColor: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _toggleWatchlist() async {
    final media = _media;
    if (media == null) return;

    await _watchlistController.toggleDetailMedia(media);
    final isInWatchlist = _watchlistController.isInWatchlist(media.id);
    if (!mounted) return;
    setState(() => _media = media.copyWith(isInWatchlist: isInWatchlist));
    _showActionFeedback(
      isInWatchlist ? 'Added to watchlist' : 'Removed from watchlist',
    );
  }

  Future<void> _queueDownload(
    DetailMedia media, {
    int? season,
    int? episode,
    String? stillPath,
  }) async {
    await LibraryPersistence.init();
    final id = _numericMediaId(media);
    if (id == null) {
      _showActionFeedback('Download unavailable for this title');
      return;
    }
    final downloadId = _downloadId(media, id, season: season, episode: episode);
    final title = _downloadTitle(media, season: season, episode: episode);
    final existing = LibraryPersistence.downloadsBox.get(downloadId);
    if (existing != null) {
      _showActionFeedback('Already in downloads');
      return;
    }

    _showActionFeedback('Preparing download...');
    final service = DesktopStreamingService();
    final request = await _downloadRequest(
      media,
      season: season,
      episode: episode,
    );
    try {
      final servers = (await service.availableSources(request))
          .where((source) => source.directMedia && !source.iframeOnly)
          .toList(growable: false);
      final result = await service.resolveDownloadable(request);
      if (!mounted) return;
      final selection = await DesktopDownloadPrompt.show(
        context: context,
        request: request,
        initialResult: result,
        streamingService: service,
        servers: servers,
      );
      if (selection == null) return;
      await DesktopDownloadService.instance.queueDownload(
        LibraryDownloadItem(
          id: downloadId,
          mediaId: id,
          title: title,
          mediaType: media.mediaType.label.toLowerCase(),
          savePath: '',
          createdAt: DateTime.now(),
          posterPath: _downloadPoster(media, stillPath),
          season: season,
          episode: episode,
          streamUrl: selection.streamUrl,
          headers: selection.result.headers,
          selectedAudioLanguage: selection.audioLanguage,
          selectedSubtitleLanguage: selection.subtitleLanguage,
          subtitleUrl: selection.subtitleUrl,
        ),
      );
      if (!mounted) return;
      _showActionFeedback('Download started');
    } on StreamResolutionException catch (error) {
      if (!mounted) return;
      _showActionFeedback(error.message);
    } catch (_) {
      if (!mounted) return;
      _showActionFeedback('Download failed to start');
    }
  }

  Future<void> _queueSeasonDownload(
    DetailMedia media, {
    required int season,
    required List<DetailEpisode> episodes,
  }) async {
    if (episodes.isEmpty) {
      _showActionFeedback('No episodes available to download');
      return;
    }
    await LibraryPersistence.init();
    final id = _numericMediaId(media);
    if (id == null) {
      _showActionFeedback('Download unavailable for this title');
      return;
    }
    final pending = episodes
        .where(
          (episode) => !LibraryPersistence.downloadsBox.containsKey(
            _downloadId(media, id, season: season, episode: episode.number),
          ),
        )
        .toList(growable: false);
    if (pending.isEmpty) {
      _showActionFeedback('Season already in downloads');
      return;
    }

    _showActionFeedback('Preparing season download...');
    final service = DesktopStreamingService();
    final first = pending.first;
    final firstRequest = await _downloadRequest(
      media,
      season: season,
      episode: first.number,
    );

    try {
      final servers = (await service.availableSources(firstRequest))
          .where((source) => source.directMedia && !source.iframeOnly)
          .toList(growable: false);
      final firstResult = await service.resolveDownloadable(firstRequest);
      if (!mounted) return;
      final selection = await DesktopDownloadPrompt.show(
        context: context,
        title: 'Download Season $season',
        request: firstRequest,
        initialResult: firstResult,
        streamingService: service,
        servers: servers,
      );
      if (selection == null) return;

      var queued = 0;
      for (final episodeItem in pending) {
        final episodeRequest = await _downloadRequest(
          media,
          season: season,
          episode: episodeItem.number,
          serverIndex: selection.server?.index,
          quality: selection.quality,
          audio: selection.audioLanguage,
          subtitle: selection.subtitleLanguage,
        );
        final result = episodeItem == first
            ? selection.result
            : await service.resolveDownloadable(episodeRequest);
        final streamUrl = episodeItem == first
            ? selection.streamUrl
            : await _streamUrlForQuality(result, selection.quality);
        await DesktopDownloadService.instance.queueDownload(
          LibraryDownloadItem(
            id: _downloadId(
              media,
              id,
              season: season,
              episode: episodeItem.number,
            ),
            mediaId: id,
            title: _downloadTitle(
              media,
              season: season,
              episode: episodeItem.number,
            ),
            mediaType: media.mediaType.label.toLowerCase(),
            savePath: '',
            createdAt: DateTime.now(),
            posterPath: _downloadPoster(media, episodeItem.stillPath),
            season: season,
            episode: episodeItem.number,
            streamUrl: streamUrl,
            headers: result.headers,
            selectedAudioLanguage: selection.audioLanguage,
            selectedSubtitleLanguage: selection.subtitleLanguage,
            subtitleUrl: _subtitleUrlFor(result, selection.subtitleLanguage),
          ),
        );
        queued++;
      }
      if (!mounted) return;
      _showActionFeedback('Queued $queued episode downloads');
    } on StreamResolutionException catch (error) {
      if (!mounted) return;
      _showActionFeedback(error.message);
    } catch (_) {
      if (!mounted) return;
      _showActionFeedback('Season download failed to start');
    }
  }

  Future<PlaybackRequest> _downloadRequest(
    DetailMedia media, {
    int? season,
    int? episode,
    int? serverIndex,
    String? quality,
    String? audio,
    String? subtitle,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return PlaybackRequestFactory.fromDetail(
      media,
      season: season,
      episode: episode,
    ).copyWith(
      providerIndex: serverIndex,
      preferredQuality:
          quality ?? prefs.getString('download_quality') ?? 'auto',
      preferredAudioTrack:
          audio ??
          _downloadPreference(
            prefs.getString('preferred_download_audio_language'),
            ignored: const {'', 'original', 'auto'},
          ),
      preferredSubtitleTrack:
          subtitle ??
          _downloadPreference(
            prefs.getString('preferred_download_subtitle_language'),
            ignored: const {'', 'auto'},
          ),
    );
  }

  void _scrollToMoreLikeThis() {
    final context = _moreLikeThisKey.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 520),
        curve: AppAnimation.emphasized,
        alignment: 0.02,
      );
      return;
    }
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 520),
      curve: AppAnimation.emphasized,
    );
  }

  int? _numericMediaId(DetailMedia media) {
    final raw = media.id.contains(':') ? media.id.split(':').last : media.id;
    return int.tryParse(raw);
  }

  String _downloadId(DetailMedia media, int id, {int? season, int? episode}) {
    return [
      media.mediaType.label.toLowerCase(),
      id,
      if (season != null) 's$season',
      if (episode != null) 'e$episode',
    ].join('_');
  }

  String _downloadTitle(DetailMedia media, {int? season, int? episode}) {
    return episode == null
        ? media.title
        : '${media.title}|||S$season E$episode';
  }

  String? _downloadPoster(DetailMedia media, String? stillPath) {
    if (stillPath == null || stillPath.isEmpty) return media.posterPath;
    return '${media.posterPath ?? ''}|||$stillPath';
  }

  String? _downloadPreference(String? value, {required Set<String> ignored}) {
    final normalized = value?.trim();
    if (normalized == null || ignored.contains(normalized.toLowerCase())) {
      return null;
    }
    if (normalized.toLowerCase() == 'off') return null;
    return normalized;
  }

  String? _subtitleUrlFor(StreamResult result, String? selectedSubtitle) {
    if (selectedSubtitle == null || selectedSubtitle.toLowerCase() == 'off') {
      return null;
    }
    if (result.subtitles.isEmpty) return null;
    final preferred = selectedSubtitle.toLowerCase();
    for (final subtitle in result.subtitles) {
      if (subtitle.lang.toLowerCase().contains(preferred)) {
        return subtitle.url;
      }
    }
    return result.subtitles.first.url;
  }

  Future<String> _streamUrlForQuality(
    StreamResult result,
    String quality,
  ) async {
    for (final source in result.sources) {
      if (source.quality.toLowerCase() == quality.toLowerCase()) {
        return source.url;
      }
    }
    final url = result.sources.firstOrNull?.url ?? result.url;
    if (result.isM3U8 || url.toLowerCase().contains('.m3u8')) {
      final resolutions = await M3u8Parser.parseVideoResolutions(
        url,
        result.headers,
      );
      for (final resolution in resolutions) {
        if (resolution.quality.toLowerCase() == quality.toLowerCase()) {
          return resolution.url;
        }
      }
    }
    return url;
  }

  Future<void> _downloadFromHero(DetailMedia media) async {
    if (media.isSeries) {
      await _queueSeasonDownload(
        media,
        season: _selectedSeason,
        episodes: widget.controller.episodes,
      );
      return;
    }
    await _queueDownload(media);
  }

  void _playInlineTrailer(DetailMedia media) {
    final trailerKey = media.trailers.firstOrNull;
    if (trailerKey == null || trailerKey.trim().isEmpty) {
      _showActionFeedback('Trailer unavailable');
      return;
    }
    setState(() => _inlineTrailerActive = true);
  }

  void _stopInlineTrailer() {
    if (!_inlineTrailerActive || !mounted) return;
    setState(() => _inlineTrailerActive = false);
  }

  void _playMedia({int? season, int? episode}) {
    final media = _media;
    if (media == null) return;
    final totalEpisodes = _selectedSeasonEpisodeCount(media, season);
    widget.onPlay(
      PlaybackRequestFactory.fromDetail(
        media,
        season: season,
        episode: episode,
        totalEpisodes: totalEpisodes == 0 ? null : totalEpisodes,
      ),
    );
  }

  int? _selectedSeasonEpisodeCount(DetailMedia media, int? season) {
    if (!media.isSeries) return null;
    final selected = season ?? _selectedSeason;
    if (selected == _selectedSeason && widget.controller.episodes.isNotEmpty) {
      return widget.controller.episodes.length;
    }
    for (final item in media.seasons) {
      if (item.number != selected) continue;
      if (item.episodes.isNotEmpty) return item.episodes.length;
      final count = item.episodeCount;
      return count != null && count > 0 ? count : null;
    }
    return null;
  }

  void _selectSeason(int season) {
    setState(() {
      _selectedSeason = season;
      _resumeEpisode = 1;
      _watchProgress = 0;
    });
    widget.controller.loadSeasonEpisodes(widget.args.mediaId, season);
  }

  void _showActionFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HomeOverlayStatus extends StatelessWidget {
  const _HomeOverlayStatus({required this.child, required this.onClose});

  final Widget child;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Center(
        child: SizedBox(
          width: 520,
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1016),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Stack(
                children: [
                  Center(child: child),
                  Positioned(
                    top: AppSpacing.md,
                    right: AppSpacing.md,
                    child: IconButton(
                      tooltip: 'Close details',
                      onPressed: onClose,
                      icon: const Icon(LucideIcons.x),
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OverlayMessage extends StatelessWidget {
  const _OverlayMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xxxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 44, color: AppColors.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppTypography.title.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.body.copyWith(color: AppColors.textMuted),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.lg),
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class _FloatingBackButton extends StatefulWidget {
  const _FloatingBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_FloatingBackButton> createState() => _FloatingBackButtonState();
}

class _FloatingBackButtonState extends State<_FloatingBackButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppAnimation.hover,
            curve: AppAnimation.standard,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isHovered
                  ? AppColors.primary
                  : Colors.black.withValues(alpha: 0.5),
              border: Border.all(
                color: _isHovered ? AppColors.primary : AppColors.borderSubtle,
                width: 1.5,
              ),
              boxShadow: AppShadows.hover,
            ),
            child: Icon(
              LucideIcons.arrowLeft,
              color: _isHovered ? AppColors.background : AppColors.textPrimary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}

class _HotstarModalHero extends StatelessWidget {
  const _HotstarModalHero({
    required this.media,
    required this.watchProgress,
    required this.onPlay,
    required this.onToggleWatchlist,
    required this.onDownload,
    required this.onWatchTogether,
    required this.inlineTrailerActive,
    required this.onInlineTrailerExit,
    this.onWatchTrailer,
    this.height = 470,
    this.contentLeft = AppSpacing.huge,
    this.contentBottom = AppSpacing.massive,
    this.contentWidth = 430,
    this.logoWidth = 190,
    this.titleFontSize = 46,
  });

  final DetailMedia media;
  final double watchProgress;
  final VoidCallback onPlay;
  final VoidCallback onToggleWatchlist;
  final VoidCallback onDownload;
  final VoidCallback onWatchTogether;
  final bool inlineTrailerActive;
  final VoidCallback onInlineTrailerExit;
  final VoidCallback? onWatchTrailer;
  final double height;
  final double contentLeft;
  final double contentBottom;
  final double contentWidth;
  final double logoWidth;
  final double titleFontSize;

  @override
  Widget build(BuildContext context) {
    final backdropUrl = TmdbImageBuilder.backdrop(
      media.backdropPath ?? media.posterPath,
      size: 'w1280',
    );
    final logoUrl = TmdbImageBuilder.logo(media.logoPath, size: 'w300');
    final seasonCount = media.seasons
        .where((season) => season.number > 0)
        .length;
    final languageCount = media.languages.length;
    final fallbackColors = DynamicArtworkColors(
      dominant: context.appAccent,
      darkMuted: AppColors.background,
      darkVibrant: context.appAccentSecondary,
      lightVibrant: context.appAccent,
      lightMuted: AppColors.surfaceVariant,
      onSurface: Colors.white,
    );

    return SizedBox(
      height: height,
      child: FutureBuilder<DynamicArtworkColors>(
        future: dynamicArtworkColorsForUrl(
          backdropUrl.isNotEmpty
              ? backdropUrl
              : TmdbImageBuilder.poster(media.posterPath, size: 'w500'),
        ),
        builder: (context, snapshot) {
          final artworkColors = snapshot.data ?? fallbackColors;
          final accent = artworkColors.dominant;
          final background = Color.lerp(
            const Color(0xFF0F1016),
            artworkColors.darkMuted,
            0.35,
          )!;
          return LayoutBuilder(
            builder: (context, constraints) {
              final maxPreviewLeft = (constraints.maxWidth - 260)
                  .clamp(0.0, double.infinity)
                  .toDouble();
              final previewLeft = (contentLeft + contentWidth + AppSpacing.xl)
                  .clamp(0.0, maxPreviewLeft)
                  .toDouble();

              return Stack(
                fit: StackFit.expand,
                children: [
                  if (backdropUrl.isNotEmpty)
                    Image.network(
                      backdropUrl,
                      fit: BoxFit.cover,
                      alignment: Alignment.centerRight,
                      errorBuilder: (_, _, _) =>
                          const ColoredBox(color: AppColors.surfaceVariant),
                    )
                  else
                    const ColoredBox(color: AppColors.surfaceVariant),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(
                        center: const Alignment(0.36, -0.18),
                        radius: 1.05,
                        colors: [
                          accent.withValues(alpha: 0.28),
                          accent.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: previewLeft,
                    top: 0,
                    right: 0,
                    bottom: 0,
                    child: MouseRegion(
                      onExit: (_) {
                        if (inlineTrailerActive) onInlineTrailerExit();
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          NativeTrailerPreviewOverlay(
                            key: ValueKey(
                              inlineTrailerActive
                                  ? 'inline-${media.id}'
                                  : 'hover-${media.id}',
                            ),
                            mediaId: media.id,
                            startDelay: inlineTrailerActive
                                ? Duration.zero
                                : const Duration(seconds: 2),
                            trigger: inlineTrailerActive
                                ? NativeTrailerPreviewTrigger.immediate
                                : NativeTrailerPreviewTrigger.hover,
                            showCloseButton: inlineTrailerActive,
                            onCloseRequested: onInlineTrailerExit,
                          ),
                        ],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        colors: [
                          background,
                          background.withValues(alpha: 0.86),
                          accent.withValues(alpha: 0.2),
                        ],
                        stops: const [0, 0.42, 1],
                      ),
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          background.withValues(alpha: 0),
                          background.withValues(alpha: 0.35),
                          background,
                        ],
                        stops: const [0.38, 0.72, 1],
                      ),
                    ),
                  ),
                  Positioned(
                    left: contentLeft,
                    bottom: contentBottom,
                    width: contentWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (logoUrl.isNotEmpty)
                          Image.network(
                            logoUrl,
                            width: logoWidth,
                            fit: BoxFit.contain,
                            alignment: Alignment.centerLeft,
                            errorBuilder: (_, _, _) => _ModalTitle(
                              title: media.title,
                              fontSize: titleFontSize,
                            ),
                          )
                        else
                          _ModalTitle(
                            title: media.title,
                            fontSize: titleFontSize,
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        _ModalMetadataRow(
                          items: [
                            media.releaseYear,
                            media.certification,
                            if (media.isSeries && seasonCount > 0)
                              '$seasonCount ${seasonCount == 1 ? 'Season' : 'Seasons'}'
                            else
                              media.runtime,
                            if (languageCount > 0)
                              '$languageCount ${languageCount == 1 ? 'Language' : 'Languages'}',
                          ],
                        ),
                        if (media.overview.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          Text(
                            media.overview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: Colors.white.withValues(alpha: 0.84),
                              fontSize: 15,
                              height: 1.42,
                            ),
                          ),
                        ],
                        if (media.genres.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.lg),
                          _ModalMetadataRow(
                            items: media.genres.take(4).toList(),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xl),
                        Row(
                          children: [
                            _GradientPlayButton(
                              label: watchProgress > 0 ? 'Resume' : 'Watch Now',
                              accent: accent,
                              onTap: onPlay,
                            ),
                            const SizedBox(width: AppSpacing.md),
                            _SquareOverlayButton(
                              icon: media.isInWatchlist
                                  ? LucideIcons.check
                                  : LucideIcons.plus,
                              tooltip: media.isInWatchlist
                                  ? 'In watchlist'
                                  : 'Add to watchlist',
                              onTap: onToggleWatchlist,
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Wrap(
                          spacing: AppSpacing.sm,
                          runSpacing: AppSpacing.sm,
                          children: [
                            _HeroUtilityButton(
                              icon: LucideIcons.download,
                              label: media.isSeries
                                  ? 'Download Season'
                                  : 'Download',
                              accent: accent,
                              onTap: onDownload,
                            ),
                            if (onWatchTrailer != null)
                              _HeroUtilityButton(
                                icon: LucideIcons.circlePlay,
                                label: 'Watch Trailer',
                                accent: accent,
                                onTap: onWatchTrailer!,
                              ),
                            _HeroUtilityButton(
                              icon: LucideIcons.users,
                              label: 'Watch Together',
                              accent: accent,
                              onTap: onWatchTogether,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ModalTitle extends StatelessWidget {
  const _ModalTitle({required this.title, this.fontSize = 46});

  final String title;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: AppTypography.display.copyWith(
        color: Colors.white,
        fontSize: fontSize,
        height: 0.95,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _ModalMetadataRow extends StatelessWidget {
  const _ModalMetadataRow({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    final visible = items
        .where((item) => item.trim().isNotEmpty && item.trim() != 'N/A')
        .toList(growable: false);

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      children: [
        for (var index = 0; index < visible.length; index++) ...[
          if (index > 0)
            Text(
              '|',
              style: AppTypography.body.copyWith(
                color: Colors.white.withValues(alpha: 0.62),
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            visible[index],
            style: AppTypography.body.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ],
    );
  }
}

class _GradientPlayButton extends StatelessWidget {
  const _GradientPlayButton({
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final secondary = Color.lerp(accent, Colors.white, 0.32)!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Ink(
          width: 320,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: [secondary, accent]),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.play, color: Colors.white, size: 19),
              const SizedBox(width: AppSpacing.md),
              Text(
                label,
                style: AppTypography.body.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SquareOverlayButton extends StatelessWidget {
  const _SquareOverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon),
        color: Colors.white,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(52),
          backgroundColor: Colors.white.withValues(alpha: 0.13),
          hoverColor: Colors.white.withValues(alpha: 0.22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
    );
  }
}

class _HeroUtilityButton extends StatefulWidget {
  const _HeroUtilityButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  State<_HeroUtilityButton> createState() => _HeroUtilityButtonState();
}

class _HeroUtilityButtonState extends State<_HeroUtilityButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppAnimation.hover,
          curve: AppAnimation.standard,
          height: 38,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: _hovered
                ? widget.accent.withValues(alpha: 0.24)
                : Colors.white.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: _hovered
                  ? widget.accent.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 16, color: Colors.white),
              const SizedBox(width: AppSpacing.xs),
              Text(
                widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModalTabsHeader extends StatelessWidget {
  const _ModalTabsHeader({
    required this.primaryLabel,
    this.secondaryLabel,
    this.onSecondaryTap,
  });

  final String primaryLabel;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xxxl,
        AppSpacing.huge,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                primaryLabel,
                style: AppTypography.title.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (secondaryLabel != null) ...[
                const SizedBox(width: AppSpacing.massive),
                InkWell(
                  onTap: onSecondaryTap,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      secondaryLabel!,
                      style: AppTypography.title.copyWith(
                        color: onSecondaryTap == null
                            ? AppColors.textMuted
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xxxl),
          Divider(color: Colors.white.withValues(alpha: 0.12), height: 1),
        ],
      ),
    );
  }
}

class _EpisodePlaybackSection extends StatefulWidget {
  const _EpisodePlaybackSection({
    required this.media,
    required this.controller,
    required this.selectedSeason,
    required this.onSeasonSelected,
    required this.onPlayEpisode,
    required this.onDownloadEpisode,
    required this.onDownloadSeason,
    this.modalStyle = false,
  });

  final DetailMedia media;
  final DetailController controller;
  final int selectedSeason;
  final ValueChanged<int> onSeasonSelected;
  final ValueChanged<DetailEpisode> onPlayEpisode;
  final ValueChanged<DetailEpisode> onDownloadEpisode;
  final ValueChanged<List<DetailEpisode>> onDownloadSeason;
  final bool modalStyle;

  @override
  State<_EpisodePlaybackSection> createState() =>
      _EpisodePlaybackSectionState();
}

class _EpisodePlaybackSectionState extends State<_EpisodePlaybackSection> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _expanded = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.controller.episodes
        .where((episode) {
          if (_query.isEmpty) return true;
          final query = _query.toLowerCase();
          return episode.title.toLowerCase().contains(query) ||
              episode.overview.toLowerCase().contains(query) ||
              episode.number.toString().contains(query);
        })
        .toList(growable: false);

    if (widget.modalStyle) {
      return _buildModalEpisodes(context, widget.controller.episodes);
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.massive),
      child: _EditorialSection(
        title: 'Episodes',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (widget.media.seasons.length > 1)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.glassFill,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: AppColors.borderSubtle),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: widget.selectedSeason,
                        dropdownColor: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        items: [
                          for (final season in widget.media.seasons)
                            DropdownMenuItem(
                              value: season.number,
                              child: Text(season.name),
                            ),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            _searchController.clear();
                            setState(() => _query = '');
                            widget.onSeasonSelected(value);
                          }
                        },
                      ),
                    ),
                  ),
                if (widget.controller.episodes.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  OutlinedButton.icon(
                    onPressed: widget.controller.isLoadingEpisodes
                        ? null
                        : () => widget.onDownloadSeason(
                            widget.controller.episodes,
                          ),
                    icon: const Icon(Icons.download_for_offline_outlined),
                    label: Text('Season ${widget.selectedSeason}'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.borderSubtle),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  width: 320,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search episodes',
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AppColors.textMuted,
                        size: 20,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close, size: 18),
                            ),
                      filled: true,
                      fillColor: const Color(0x1FFFFFFF),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: Color(0x26FFFFFF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(999),
                        borderSide: const BorderSide(color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (widget.controller.isLoadingEpisodes)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            else if (widget.controller.episodesError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  'Episodes unavailable: ${widget.controller.episodesError}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        _query.isEmpty
                            ? Icons.event_busy_outlined
                            : Icons.search_off,
                        color: AppColors.textMuted,
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _query.isEmpty
                            ? 'Season ${widget.selectedSeason} episodes are not available yet.'
                            : 'No episodes match "$_query"',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              for (final episode in filtered)
                _EpisodeCard(
                  media: widget.media,
                  episode: episode,
                  seasonNumber: widget.selectedSeason,
                  onPlay: () => widget.onPlayEpisode(episode),
                  onDownload: () => widget.onDownloadEpisode(episode),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildModalEpisodes(
    BuildContext context,
    List<DetailEpisode> episodes,
  ) {
    if (widget.controller.isLoadingEpisodes) {
      return _buildModalShell(
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    if (widget.controller.episodesError != null) {
      return _buildModalShell(
        child: Text(
          'Episodes unavailable: ${widget.controller.episodesError}',
          style: AppTypography.caption.copyWith(color: AppColors.danger),
        ),
      );
    }

    if (episodes.isEmpty) {
      return _buildModalShell(
        child: Row(
          children: [
            const Icon(
              Icons.event_busy_outlined,
              color: AppColors.textMuted,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Season ${widget.selectedSeason} episodes are not available yet.',
                style: AppTypography.body.copyWith(color: AppColors.textMuted),
              ),
            ),
          ],
        ),
      );
    }

    final visibleEpisodes = _expanded || episodes.length <= 4
        ? episodes
        : episodes.take(4).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xl,
        AppSpacing.huge,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasModalSeasonTabs) ...[
            _buildModalSeasonTabs(),
            const SizedBox(height: AppSpacing.xl),
          ],
          Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Column(
                children: [
                  for (final episode in visibleEpisodes)
                    _EpisodeCard(
                      media: widget.media,
                      episode: episode,
                      seasonNumber: widget.selectedSeason,
                      modalStyle: true,
                      onPlay: () => widget.onPlayEpisode(episode),
                      onDownload: () => widget.onDownloadEpisode(episode),
                    ),
                ],
              ),
              if (!_expanded && episodes.length > visibleEpisodes.length)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    height: 116,
                    alignment: Alignment.bottomCenter,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x000F1016), Color(0xFF0F1016)],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: TextButton.icon(
                        onPressed: () => setState(() => _expanded = true),
                        icon: const Icon(LucideIcons.chevronDown, size: 18),
                        label: const Text('View More'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: const Color(0xFF272B36),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (_expanded && episodes.length > 4)
            Align(
              alignment: Alignment.center,
              child: TextButton.icon(
                onPressed: () => setState(() => _expanded = false),
                icon: const Icon(LucideIcons.chevronUp, size: 18),
                label: const Text('Show Less'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ),
        ],
      ),
    );
  }

  bool get _hasModalSeasonTabs => widget.media.seasons.length > 1;

  Widget _buildModalShell({required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xl,
        AppSpacing.huge,
        AppSpacing.xxxl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_hasModalSeasonTabs) ...[
            _buildModalSeasonTabs(),
            const SizedBox(height: AppSpacing.xl),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildModalSeasonTabs() {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widget.media.seasons.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xxxl),
        itemBuilder: (context, index) {
          final season = widget.media.seasons[index];
          final selected = season.number == widget.selectedSeason;
          return InkWell(
            onTap: () {
              setState(() {
                _expanded = false;
                _query = '';
              });
              _searchController.clear();
              widget.onSeasonSelected(season.number);
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xs,
              ),
              child: Text(
                season.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.body.copyWith(
                  color: selected ? Colors.white : AppColors.textMuted,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.media,
    required this.episode,
    required this.onPlay,
    required this.onDownload,
    this.seasonNumber = 1,
    this.modalStyle = false,
  });

  final DetailMedia media;
  final DetailEpisode episode;
  final VoidCallback onPlay;
  final VoidCallback onDownload;
  final int seasonNumber;
  final bool modalStyle;

  @override
  Widget build(BuildContext context) {
    final still = episode.stillPath ?? media.backdropPath ?? media.posterPath;
    final stillUrl = TmdbImageBuilder.still(still, size: 'w300');
    final isCurrent = episode.progress > 0 && episode.progress < 0.95;

    return Container(
      margin: EdgeInsets.only(bottom: modalStyle ? AppSpacing.xxl : 12),
      decoration: BoxDecoration(
        color: modalStyle
            ? (isCurrent
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.transparent)
            : (isCurrent
                  ? AppColors.primary.withValues(alpha: 0.13)
                  : const Color(0x14FFFFFF)),
        borderRadius: BorderRadius.circular(modalStyle ? 6 : 12),
        border: modalStyle
            ? null
            : Border.all(
                color: isCurrent ? AppColors.primary : AppColors.borderSubtle,
                width: isCurrent ? 1.5 : 1,
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(modalStyle ? 6 : 12),
        onTap: onPlay,
        child: Padding(
          padding: EdgeInsets.all(modalStyle ? 0 : 10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(modalStyle ? 4 : 8),
                child: SizedBox(
                  width: modalStyle ? 220 : 148,
                  height: modalStyle ? 124 : 84,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (stillUrl.isNotEmpty)
                        Image.network(
                          stillUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const ColoredBox(color: AppColors.surfaceVariant),
                        )
                      else
                        const ColoredBox(color: AppColors.surfaceVariant),
                      Center(
                        child: Container(
                          width: modalStyle ? 34 : 38,
                          height: modalStyle ? 34 : 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.62),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isCurrent ? Icons.equalizer : Icons.play_arrow,
                            color: isCurrent ? AppColors.primary : Colors.white,
                            size: 22,
                          ),
                        ),
                      ),
                      if (episode.progress > 0)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: LinearProgressIndicator(
                            value: episode.progress.clamp(0, 1),
                            color: AppColors.primary,
                            backgroundColor: Colors.white24,
                            minHeight: 3,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: modalStyle ? AppSpacing.xxxl : 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (isCurrent) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'NOW',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Text(
                            modalStyle
                                ? episode.title
                                : 'E${episode.number} - ${episode.title}',
                            maxLines: modalStyle ? 2 : 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.body.copyWith(
                              color: isCurrent
                                  ? AppColors.primary
                                  : AppColors.textPrimary,
                              fontSize: modalStyle ? 18 : null,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _episodeMeta(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption.copyWith(
                        color: const Color(0xFF9EA8C3),
                        fontSize: modalStyle ? 16 : null,
                        fontWeight: modalStyle ? FontWeight.w800 : null,
                      ),
                    ),
                    if (episode.overview.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        episode.overview,
                        maxLines: modalStyle ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: modalStyle
                              ? const Color(0xFFA0A7B8)
                              : AppColors.textMuted,
                          fontSize: modalStyle ? 14 : null,
                          height: modalStyle ? 1.45 : 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Download episode ${episode.number}',
                onPressed: onDownload,
                icon: const Icon(Icons.download_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _episodeMeta() {
    final parts = <String>['S$seasonNumber E${episode.number}'];
    if (episode.airDate?.trim().isNotEmpty == true) {
      parts.add(episode.airDate!.trim());
    }
    if (episode.runtime.trim().isNotEmpty) {
      parts.add(episode.runtime.trim());
    }
    return parts.join(' | ');
  }
}

class _DetailBadgesSection extends StatelessWidget {
  const _DetailBadgesSection({required this.media});

  final DetailMedia media;

  @override
  Widget build(BuildContext context) {
    final badges = _detailBadges(media);
    final providers = media.providers
        .where(
          (provider) =>
              provider.trim().isNotEmpty && provider.trim() != 'Not Available',
        )
        .take(8)
        .toList(growable: false);
    if (badges.isEmpty && providers.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xxl,
        AppSpacing.huge,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (badges.isNotEmpty)
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final badge in badges) _DetailInfoChip(label: badge),
              ],
            ),
          if (providers.isNotEmpty) ...[
            if (badges.isNotEmpty) const SizedBox(height: AppSpacing.lg),
            Text(
              'Available On',
              style: AppTypography.caption.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final provider in providers)
                  _DetailInfoChip(label: provider, muted: true),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<String> _detailBadges(DetailMedia media) {
    final badges = <String>[
      media.mediaType.label,
      if (media.isSeries)
        _episodeCountLabel(media)
      else if (media.runtime.trim().isNotEmpty && media.runtime != 'N/A')
        media.runtime,
      if (media.releaseYear.trim().isNotEmpty && media.releaseYear != 'N/A')
        media.releaseYear,
      if (media.status.trim().isNotEmpty) media.status,
      if (media.rating > 0) '${(media.rating * 10).round()}%',
      if (media.certification.trim().isNotEmpty && media.certification != 'N/A')
        media.certification,
    ];
    return badges.toSet().toList(growable: false);
  }

  String _episodeCountLabel(DetailMedia media) {
    final total = media.seasons.fold<int>(
      0,
      (sum, season) =>
          sum +
          (season.episodes.isNotEmpty
              ? season.episodes.length
              : season.episodeCount ?? 0),
    );
    if (total > 0) return '$total Episodes';
    final seasonCount = media.seasons
        .where((season) => season.number > 0)
        .length;
    if (seasonCount > 0) {
      return '$seasonCount ${seasonCount == 1 ? 'Season' : 'Seasons'}';
    }
    return 'Series';
  }
}

class _DetailInfoChip extends StatelessWidget {
  const _DetailInfoChip({required this.label, this.muted = false});

  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: muted
            ? Colors.white.withValues(alpha: 0.06)
            : AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: muted
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.primary.withValues(alpha: 0.36),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(
            color: muted ? AppColors.textSecondary : AppColors.textPrimary,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _CastSection extends StatelessWidget {
  const _CastSection({required this.media});

  final DetailMedia media;

  @override
  Widget build(BuildContext context) {
    final cast = media.cast
        .where((person) => person.name.trim().isNotEmpty)
        .take(20)
        .toList(growable: false);
    if (cast.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xxl,
        AppSpacing.huge,
        0,
      ),
      child: PersonCarousel(
        title: 'Cast',
        itemCount: cast.length,
        height: 260,
        itemWidth: 150,
        itemBuilder: (context, index) {
          final person = cast[index];
          return PersonCard(
            title: person.name,
            subtitle: person.role,
            profilePath: person.profilePath,
          );
        },
      ),
    );
  }
}

class _RecommendationsSection extends StatelessWidget {
  const _RecommendationsSection({
    super.key,
    required this.media,
    required this.onOpenDetail,
    required this.onPlay,
  });

  final DetailMedia media;
  final ValueChanged<String> onOpenDetail;
  final ValueChanged<PlaybackRequest> onPlay;

  @override
  Widget build(BuildContext context) {
    final recommendations = _recommendationsFor(media);
    if (recommendations.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.huge,
        AppSpacing.xxl,
        AppSpacing.huge,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More Like This',
            style: AppTypography.title.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          MediaRail(
            itemWidth: 236,
            height: 420,
            spacing: AppSpacing.sm,
            children: [
              for (final item in recommendations)
                _RecommendationMediaCard(
                  media: media,
                  item: item,
                  onOpenDetail: onOpenDetail,
                  onPlay: onPlay,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecommendationMediaCard extends StatelessWidget {
  const _RecommendationMediaCard({
    required this.media,
    required this.item,
    required this.onOpenDetail,
    required this.onPlay,
  });

  final DetailMedia media;
  final DetailPosterItem item;
  final ValueChanged<String> onOpenDetail;
  final ValueChanged<PlaybackRequest> onPlay;

  @override
  Widget build(BuildContext context) {
    final itemId = _openableRecommendationId(media, item);
    return MediaCard(
      mediaId: itemId,
      title: item.title,
      posterPath: item.posterPath,
      year: item.year == 'N/A' ? null : item.year,
      rating: item.rating == '0.0' ? null : item.rating,
      subtitle: item.subtitle,
      onTap: () => onOpenDetail(itemId),
      onPlay: () =>
          onPlay(PlaybackRequestFactory.fromCompositeId(itemId, item.title)),
    );
  }
}

List<DetailPosterItem> _recommendationsFor(DetailMedia media) {
  final seen = <String>{};
  final items = <DetailPosterItem>[];

  for (final item in [...media.related, ...media.moreLikeThis]) {
    if (seen.add(item.id)) {
      items.add(item);
    }
    if (items.length == 20) break;
  }

  return items;
}

String _openableRecommendationId(DetailMedia media, DetailPosterItem item) {
  final rawId = item.id.trim();
  if (rawId.isEmpty) return rawId;

  final fallbackType = _routeTypeForMedia(media.mediaType);
  final itemType = _routeTypeFromSubtitle(item.subtitle) ?? fallbackType;

  if (rawId.contains(':')) {
    final separator = rawId.indexOf(':');
    final type = rawId.substring(0, separator).trim().toLowerCase();
    final id = rawId.substring(separator + 1).trim();
    if (_isSupportedRouteType(type) && id.isNotEmpty) return '$type:$id';
    if (id.isNotEmpty) return '$itemType:$id';
    return rawId;
  }

  return int.tryParse(rawId) == null ? rawId : '$itemType:$rawId';
}

String _routeTypeForMedia(DetailMediaType type) {
  return switch (type) {
    DetailMediaType.movie => 'movie',
    DetailMediaType.tv => 'tv',
    DetailMediaType.anime => 'anime',
    DetailMediaType.live => 'tv',
  };
}

String? _routeTypeFromSubtitle(String subtitle) {
  final normalized = subtitle.toLowerCase();
  if (normalized.contains('anime')) return 'anime';
  if (normalized.contains('tv')) return 'tv';
  if (normalized.contains('movie')) return 'movie';
  return null;
}

bool _isSupportedRouteType(String type) {
  return type == 'movie' || type == 'tv' || type == 'anime';
}

class _EditorialSection extends StatelessWidget {
  const _EditorialSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.sectionTitle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        child,
      ],
    );
  }
}
