import 'dart:async';

import 'package:flutter/material.dart' hide SearchController;
import 'package:flutter/services.dart';

import '../../features/details/detail_view.dart';
import '../../features/home/home_view.dart';
import '../../features/library/library_view.dart';
import '../../features/live_tv/live_tv_view.dart';
import '../../features/movies/controllers/movies_controller.dart';
import '../../features/movies/models/movie_category.dart';
import '../../features/movies/movies_view.dart';
import '../../features/movies/repositories/tmdb_movies_repository.dart';
import '../../features/party/party_view.dart';
import '../../features/profile/profile_view.dart';
import '../../features/providers/controllers/providers_controller.dart';
import '../../features/providers/models/provider_models.dart';
import '../../features/providers/providers_view.dart';
import '../../features/providers/repositories/tmdb_providers_repository.dart';
import '../../features/player/models/playback_request.dart';
import '../../features/player/resolving_player_screen.dart';
import '../../features/player/services/stream_resolver.dart';
import '../../features/player/playback_engine.dart';

import '../../core/interfaces/search_repository.dart';
import '../../core/interfaces/home_repository.dart';
import '../../core/interfaces/details_repository.dart';
import '../../features/search/controllers/search_controller.dart';
import '../../features/search/models/search_media_item.dart';
import '../../features/home/controllers/home_controller.dart';
import '../../features/details/controllers/detail_controller.dart';
import '../../features/details/models/detail_models.dart';
import '../../features/details/models/detail_route_args.dart';
import '../../features/search/presentation/search_view.dart';
import '../../core/repositories/tmdb_search_repository.dart';
import '../../core/repositories/tmdb_home_repository.dart';
import '../../core/repositories/tmdb_details_repository.dart';
import '../../core/network/tmdb_client.dart';
import '../../core/constants.dart';
import '../../core/services/deep_link_service.dart';
import '../theme/index.dart';
import 'desktop_sidebar.dart';
import 'desktop_topbar.dart';
import '../../core/interfaces/watch_history_repository.dart';
import '../../features/history/desktop_watch_history_repository.dart';
import '../../features/player/services/mini_player_service.dart';
import '../../features/player/widgets/mini_player_overlay.dart';
import '../../features/party/services/watch_party_session_manager.dart';

/// Permanent desktop shell used by future feature screens.
class DesktopScaffold extends StatefulWidget {
  final SearchRepository? searchRepository;
  final HomeRepository? homeRepository;
  final DetailsRepository? detailsRepository;
  final StreamResolver? streamResolver;
  final PlaybackEngineFactory? playbackEngineFactory;
  final WatchHistoryRepository? watchHistoryRepository;

  const DesktopScaffold({
    super.key,
    this.searchRepository,
    this.homeRepository,
    this.detailsRepository,
    this.streamResolver,
    this.playbackEngineFactory,
    this.watchHistoryRepository,
  });

  @override
  State<DesktopScaffold> createState() => _DesktopScaffoldState();
}

class _DesktopScaffoldState extends State<DesktopScaffold> {
  static const int _homeIndex = 0;
  static const int _searchIndex = 1;
  static const int _libraryIndex = 2;
  static const int _liveTvIndex = 3;
  static const int _partyIndex = 4;
  static const int _profileIndex = 5;

  late final WatchHistoryRepository _watchHistoryRepository =
      widget.watchHistoryRepository ?? DesktopWatchHistoryRepository.instance;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchPageFocusNode = FocusNode();
  late final SearchController _searchStateController = SearchController(
    repository:
        widget.searchRepository ??
        TmdbSearchRepository(client: TmdbClient(apiKey: tmdbApiKey)),
  );

  late final HomeController _homeStateController = HomeController(
    repository:
        widget.homeRepository ??
        TmdbHomeRepository(client: TmdbClient(apiKey: tmdbApiKey)),
    watchHistoryRepository: _watchHistoryRepository,
  );

  late final DetailController _detailStateController = DetailController(
    repository:
        widget.detailsRepository ??
        TmdbDetailsRepository(client: TmdbClient(apiKey: tmdbApiKey)),
  );

  late final ProvidersController _providersController = ProvidersController(
    repository: TmdbProvidersRepository(client: TmdbClient(apiKey: tmdbApiKey)),
  );

  late final MoviesController _moviesController = MoviesController(
    repository: TmdbMoviesRepository(client: TmdbClient(apiKey: tmdbApiKey)),
  );

  int _selectedIndex = _homeIndex;
  int _lastSidebarIndex = _homeIndex;
  bool _isSidebarHovered = false;
  Timer? _sidebarCollapseTimer;
  DetailRouteArgs? _detailRouteArgs;
  PlaybackRequest? _playbackRequest;
  PartyPreselection? _partyPreselection;
  bool _isProviderBrowserOpen = false;
  bool _isMoviesBrowserOpen = false;
  bool _showHomeDetailOverlay = false;
  bool _homeDetailOverlayMounted = false;

  @override
  void initState() {
    super.initState();
    _homeStateController.loadAll();
    DeepLinkService.instance.latest.addListener(_handleDeepLink);
  }

  @override
  void dispose() {
    _sidebarCollapseTimer?.cancel();
    _searchController.dispose();
    _searchPageFocusNode.dispose();
    _searchStateController.dispose();
    _homeStateController.dispose();
    _providersController.dispose();
    _moviesController.dispose();
    DeepLinkService.instance.latest.removeListener(_handleDeepLink);
    super.dispose();
  }

  void _handleDeepLink() {
    final link = DeepLinkService.instance.latest.value;
    if (link == null || !mounted) return;
    switch (link) {
      case OpenMediaDeepLink(:final mediaType, :final mediaId):
        _openDetail('$mediaType:$mediaId');
      case PlayMediaDeepLink(:final request):
        _openPlayback(request);
    }
  }

  void _selectDestination(int index, {bool keepPartyPreselection = false}) {
    setState(() {
      _selectedIndex = index;
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
      _isProviderBrowserOpen = false;
      _isMoviesBrowserOpen = false;
      if (index == _partyIndex && !keepPartyPreselection) {
        _partyPreselection = null;
      }
      _lastSidebarIndex = index;
    });

    if (index == _searchIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          FocusScope.of(context).requestFocus(_searchPageFocusNode);
        }
      });
    }
  }

  void _returnHome() {
    _selectDestination(_homeIndex);
  }

  void _openWatchTogether(DetailMedia media, int season) {
    final mediaId = _numericDetailMediaId(media);
    if (mediaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Watch Together unavailable.')),
      );
      return;
    }
    setState(() {
      _partyPreselection = PartyPreselection(
        mediaId: mediaId,
        mediaType: _routeTypeForDetailMedia(media.mediaType),
        season: media.isSeries ? season : 1,
        title: media.title,
      );
    });
    _selectDestination(_partyIndex, keepPartyPreselection: true);
  }

  int? _numericDetailMediaId(DetailMedia media) {
    final raw = media.id.contains(':') ? media.id.split(':').last : media.id;
    return int.tryParse(raw);
  }

  String _routeTypeForDetailMedia(DetailMediaType type) {
    return switch (type) {
      DetailMediaType.movie => 'movie',
      DetailMediaType.tv => 'tv',
      DetailMediaType.anime => 'anime',
      DetailMediaType.live => 'tv',
    };
  }

  void _focusGlobalSearch() {
    _selectDestination(_searchIndex);
  }

  void _clearFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _setSidebarHovered(bool hovered) {
    _sidebarCollapseTimer?.cancel();
    if (hovered) {
      if (!_isSidebarHovered) {
        setState(() => _isSidebarHovered = true);
      }
      return;
    }

    _sidebarCollapseTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted && _isSidebarHovered) {
        setState(() => _isSidebarHovered = false);
      }
    });
  }

  void _openDetail(String mediaId) {
    final args = _detailArgsFromRoute(mediaId);
    if (args == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Details unavailable for "$mediaId".')),
      );
      return;
    }

    _detailStateController.loadDetail(args);
    final shouldUseHomeOverlay =
        _selectedIndex == _homeIndex &&
        !_isProviderBrowserOpen &&
        !_isMoviesBrowserOpen;
    final overlayWasMounted = _homeDetailOverlayMounted;
    setState(() {
      _detailRouteArgs = args;
      _homeDetailOverlayMounted =
          _homeDetailOverlayMounted || shouldUseHomeOverlay;
      _showHomeDetailOverlay = _showHomeDetailOverlay && shouldUseHomeOverlay;
    });
    if (shouldUseHomeOverlay && !overlayWasMounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _detailRouteArgs != args) return;
        setState(() => _showHomeDetailOverlay = true);
      });
    }
  }

  DetailRouteArgs? _detailArgsFromRoute(String route) {
    final trimmed = route.trim();
    final parts = trimmed.split(':');
    if (parts.length >= 2) {
      final mediaType = parts[0].trim().toLowerCase();
      final id = int.tryParse(parts[1].trim());
      if (_isDetailMediaType(mediaType) && id != null && id > 0) {
        return DetailRouteArgs(mediaType: mediaType, mediaId: id);
      }
      return null;
    }

    final id = int.tryParse(trimmed);
    if (id != null && id > 0) {
      return DetailRouteArgs(mediaType: 'movie', mediaId: id);
    }
    return null;
  }

  bool _isDetailMediaType(String value) {
    return value == 'movie' || value == 'tv' || value == 'anime';
  }

  void _closeDetail() {
    if (_homeDetailOverlayMounted) {
      setState(() => _showHomeDetailOverlay = false);
      Future<void>.delayed(const Duration(milliseconds: 260), () {
        if (!mounted || _showHomeDetailOverlay) return;
        setState(() {
          _detailRouteArgs = null;
          _homeDetailOverlayMounted = false;
        });
      });
      return;
    }
    setState(() {
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
    });
  }

  void _openPlayback(PlaybackRequest request) {
    final playbackRequest = _requestWithActiveWatchParty(request);
    if (!MiniPlayerService.instance.matches(playbackRequest)) {
      unawaited(MiniPlayerService.instance.deactivate());
    }
    setState(() => _playbackRequest = playbackRequest);
  }

  PlaybackRequest _requestWithActiveWatchParty(PlaybackRequest request) {
    final service = WatchPartySessionManager.instance.currentService;
    final sessionCode = (service?.sessionCode ?? '').trim();
    if (service?.isInSession != true || sessionCode.isEmpty) return request;

    return request.copyWith(
      watchPartyCode: (request.watchPartyCode ?? '').trim().isNotEmpty
          ? request.watchPartyCode
          : sessionCode.toUpperCase(),
      watchPartyRole: (request.watchPartyRole ?? '').trim().isNotEmpty
          ? request.watchPartyRole
          : service!.isHost
          ? 'host'
          : 'participant',
    );
  }

  void _openAllProviders() {
    _providersController.showAllProviders();
    setState(() {
      _selectedIndex = _homeIndex;
      _lastSidebarIndex = _homeIndex;
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
      _isProviderBrowserOpen = true;
      _isMoviesBrowserOpen = false;
    });
  }

  void _openProvider(StreamingProviderItem provider) {
    setState(() {
      _selectedIndex = _homeIndex;
      _lastSidebarIndex = _homeIndex;
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
      _isProviderBrowserOpen = true;
      _isMoviesBrowserOpen = false;
    });
    unawaited(_providersController.selectProvider(provider));
  }

  void _openHomeSection(String sectionId) {
    final movieCategory = switch (sectionId) {
      'popular_movies' => MovieCategory.popular,
      'trending_movies' => MovieCategory.trending,
      'top_rated_movies' => MovieCategory.topRated,
      _ => null,
    };
    if (movieCategory != null) {
      _openMovies(movieCategory);
      return;
    }

    _openSearchForHomeSection(sectionId);
  }

  void _openMovies(MovieCategory category) {
    unawaited(_moviesController.selectCategory(category));
    setState(() {
      _selectedIndex = _homeIndex;
      _lastSidebarIndex = _homeIndex;
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
      _isProviderBrowserOpen = false;
      _isMoviesBrowserOpen = true;
    });
  }

  void _openSearchForHomeSection(String sectionId) {
    final target = _searchTargetForHomeSection(sectionId);
    _searchController.text = target.query;
    _searchStateController.setQuery(target.query);
    _searchStateController.setLanguage(target.language);
    unawaited(_searchStateController.submitQuery());
    _selectDestination(_searchIndex);
  }

  ({String query, SearchLanguageFilter language}) _searchTargetForHomeSection(
    String sectionId,
  ) {
    return switch (sectionId) {
      'popular_tv' => (
        query: 'popular tv shows',
        language: SearchLanguageFilter.all,
      ),
      'trending_tv' => (
        query: 'trending tv shows',
        language: SearchLanguageFilter.all,
      ),
      'popular_anime' || 'trending_anime' => (
        query: 'anime',
        language: SearchLanguageFilter.japanese,
      ),
      'tamil' => (query: 'Tamil movies', language: SearchLanguageFilter.tamil),
      'telugu' => (
        query: 'Telugu movies',
        language: SearchLanguageFilter.telugu,
      ),
      'hindi' => (query: 'Hindi movies', language: SearchLanguageFilter.hindi),
      'malayalam' => (
        query: 'Malayalam movies',
        language: SearchLanguageFilter.all,
      ),
      'korean' => (
        query: 'Korean dramas',
        language: SearchLanguageFilter.korean,
      ),
      _ => (query: 'movies shows', language: SearchLanguageFilter.all),
    };
  }

  void _closeProviderBrowser() {
    setState(() {
      _isProviderBrowserOpen = false;
      _isMoviesBrowserOpen = false;
      _detailRouteArgs = null;
      _showHomeDetailOverlay = false;
      _homeDetailOverlayMounted = false;
      _selectedIndex = _homeIndex;
      _lastSidebarIndex = _homeIndex;
    });
  }

  void _closePlayback() {
    setState(() => _playbackRequest = null);
  }

  @override
  Widget build(BuildContext context) {
    final playbackRequest = _playbackRequest;
    if (playbackRequest != null) {
      return ResolvingPlayerScreen(
        request: playbackRequest,
        resolver: widget.streamResolver,
        engineFactory: widget.playbackEngineFactory,
        watchHistoryRepository: _watchHistoryRepository,
        onClose: _closePlayback,
        onMinimize: _closePlayback,
        onNextEpisode: _openPlayback,
      );
    }

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyK, control: true):
            ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.slash): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _focusGlobalSearch();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              if (_detailRouteArgs != null) {
                _closeDetail();
                return null;
              }
              _clearFocus();
              return null;
            },
          ),
        },
        child: Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.background,
              body: SafeArea(child: _buildShell()),
            ),
            MiniPlayerOverlay(onExpand: _openPlayback),
          ],
        ),
      ),
    );
  }

  Widget _buildShell() {
    final showImmersiveDetail =
        _detailRouteArgs != null && !_homeDetailOverlayMounted;
    if (showImmersiveDetail) {
      return ColoredBox(color: AppColors.background, child: _buildContent());
    }

    if (_selectedIndex == _homeIndex) {
      return Stack(
        children: [
          Positioned.fill(child: _buildContentStack()),
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: AppBreakpoints.topbarHeight,
            child: DesktopTopbar(isOverlay: true),
          ),
          if (_homeDetailOverlayMounted && _detailRouteArgs != null)
            Positioned.fill(child: _buildHomeDetailOverlay()),
        ],
      );
    }

    return _buildContentStack();
  }

  Widget _buildContentStack() {
    final hideSidebar = _selectedIndex == _profileIndex;
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: AppColors.background,
            child: Padding(
              padding: EdgeInsets.only(
                left: hideSidebar ? 0 : DesktopSidebar.preferredWidth,
              ),
              child: _buildContent(includeDetail: !_homeDetailOverlayMounted),
            ),
          ),
        ),
        if (!hideSidebar)
          AnimatedPositioned(
            duration: AppAnimation.sidebar,
            curve: AppAnimation.emphasized,
            left: 0,
            top: 0,
            bottom: 0,
            width: _isSidebarHovered
                ? DesktopSidebar.expandedWidth
                : DesktopSidebar.preferredWidth,
            child: DesktopSidebar(
              isExpanded: _isSidebarHovered,
              selectedIndex: _lastSidebarIndex,
              onItemHoverChanged: _setSidebarHovered,
              onDestinationSelected: _selectDestination,
            ),
          ),
      ],
    );
  }

  Widget _buildHomeDetailOverlay() {
    final detailRouteArgs = _detailRouteArgs;
    if (detailRouteArgs == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _showHomeDetailOverlay ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            curve: AppAnimation.standard,
            child: GestureDetector(
              onTap: _closeDetail,
              child: ColoredBox(color: Colors.black.withValues(alpha: 0.72)),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_showHomeDetailOverlay,
            child: AnimatedOpacity(
              opacity: _showHomeDetailOverlay ? 1 : 0,
              duration: const Duration(milliseconds: 240),
              curve: AppAnimation.standard,
              child: AnimatedSlide(
                offset: _showHomeDetailOverlay
                    ? Offset.zero
                    : const Offset(0, 0.08),
                duration: const Duration(milliseconds: 260),
                curve: AppAnimation.emphasized,
                child: AnimatedScale(
                  scale: _showHomeDetailOverlay ? 1 : 0.985,
                  duration: const Duration(milliseconds: 260),
                  curve: AppAnimation.emphasized,
                  child: DetailView(
                    args: detailRouteArgs,
                    controller: _detailStateController,
                    onBack: _closeDetail,
                    onOpenDetail: _openDetail,
                    onPlay: _openPlayback,
                    onWatchTogether: _openWatchTogether,
                    watchHistoryRepository: _watchHistoryRepository,
                    homeOverlay: true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent({bool includeDetail = true}) {
    final detailRouteArgs = _detailRouteArgs;
    if (includeDetail && detailRouteArgs != null) {
      return DetailView(
        args: detailRouteArgs,
        controller: _detailStateController,
        onBack: _closeDetail,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
        onWatchTogether: _openWatchTogether,
        watchHistoryRepository: _watchHistoryRepository,
      );
    }

    if (_selectedIndex == _homeIndex && _isProviderBrowserOpen) {
      return ProvidersView(
        controller: _providersController,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
        onBack: _closeProviderBrowser,
      );
    }

    if (_selectedIndex == _homeIndex && _isMoviesBrowserOpen) {
      return MoviesView(
        controller: _moviesController,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
      );
    }

    return switch (_selectedIndex) {
      _homeIndex => HomeView(
        controller: _homeStateController,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
        onOpenAllProviders: _openAllProviders,
        onOpenProvider: _openProvider,
        onOpenSection: _openHomeSection,
      ),
      _libraryIndex => LibraryView(
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
        watchHistoryRepository: _watchHistoryRepository,
      ),
      _liveTvIndex => LiveTvView(onPlay: _openPlayback),
      _partyIndex => PartyView(
        onPlay: _openPlayback,
        preselection: _partyPreselection,
      ),
      _profileIndex => ProfileView(
        onOpenDetail: _openDetail,
        onBack: _returnHome,
        onHomeLayoutChanged: () {
          unawaited(_homeStateController.reloadHomeLayoutOrder());
        },
      ),
      _searchIndex => SearchView(
        controller: _searchStateController,
        queryController: _searchController,
        searchFocusNode: _searchPageFocusNode,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
      ),
      _ => HomeView(
        controller: _homeStateController,
        onOpenDetail: _openDetail,
        onPlay: _openPlayback,
        onOpenAllProviders: _openAllProviders,
        onOpenProvider: _openProvider,
        onOpenSection: _openHomeSection,
      ),
    };
  }
}
