import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:nivio/services/streaming_service.dart';
import 'package:nivio/widgets/marquee_text.dart';

class TorrentPickerSheet extends StatefulWidget {
  final SearchResult media;
  final int initialEpisode;
  final int initialSeason;
  final int? initialAbsoluteEpisode;
  final String initialResolution;
  final TorrentStreamService torrentStreamService;
  final void Function(String status)? onStatusUpdate;
  final bool isFullScreen;

  const TorrentPickerSheet({
    super.key,
    required this.media,
    required this.initialEpisode,
    required this.initialSeason,
    this.initialAbsoluteEpisode,
    required this.initialResolution,
    required this.torrentStreamService,
    this.onStatusUpdate,
    this.isFullScreen = false,
  });

  static Future<(TorrentResult, dynamic)?> show(
    BuildContext context, {
    required SearchResult media,
    required int initialEpisode,
    required int initialSeason,
    int? initialAbsoluteEpisode,
    required String initialResolution,
    required TorrentStreamService torrentStreamService,
    void Function(String status)? onStatusUpdate,
  }) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    if (isMobile) {
      return Navigator.of(context).push<(TorrentResult, dynamic)>(
        MaterialPageRoute(
          builder: (context) => Scaffold(
            backgroundColor: const Color(0xFF0F0F0F),
            body: TorrentPickerSheet(
              media: media,
              initialEpisode: initialEpisode,
              initialSeason: initialSeason,
              initialAbsoluteEpisode: initialAbsoluteEpisode,
              initialResolution: initialResolution,
              torrentStreamService: torrentStreamService,
              onStatusUpdate: onStatusUpdate,
              isFullScreen: true,
            ),
          ),
        ),
      );
    }

    return showDialog<(TorrentResult, dynamic)>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.8), // Darker backdrop for cinematic feel
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: TorrentPickerSheet(
          media: media,
          initialEpisode: initialEpisode,
          initialSeason: initialSeason,
          initialAbsoluteEpisode: initialAbsoluteEpisode,
          initialResolution: initialResolution,
          torrentStreamService: torrentStreamService,
          onStatusUpdate: onStatusUpdate,
          isFullScreen: false,
        ),
      ),
    );
  }

  @override
  State<TorrentPickerSheet> createState() => _TorrentPickerSheetState();
}

class _TorrentPickerSheetState extends State<TorrentPickerSheet> {
  List<TorrentResult>? _filteredResults;
  String? _error;
  
  late int _episode;
  late String _resolution;
  
  final _searchController = TextEditingController();
  dynamic _currentQuery;
  
  Timer? _autoPlayTimer;
  int _countdown = 5;
  bool _isCancelled = false;

  bool get _isAnime => StreamingService.isAnimeMedia(widget.media);
  bool get _isMovie => !_isAnime && widget.media.mediaType == 'movie';

  @override
  void initState() {
    super.initState();
    _episode = widget.initialEpisode;
    _resolution = widget.initialResolution;
    
    // We try to load preferred resolution from SharedPreferences, if not, use initial.
    _initResolutionAndLoad();
  }
  
  Future<void> _initResolutionAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final savedRes = prefs.getString('nivio_torrent_resolution');
    if (savedRes != null && mounted) {
      setState(() {
        _resolution = savedRes;
      });
    }
    _loadTorrents();
  }

  Future<void> _loadTorrents() async {
    if (!mounted) return;
    setState(() {
      _filteredResults = null;
      _error = null;
      _isCancelled = false;
    });
    
    _autoPlayTimer?.cancel();
    
    try {
      List<TorrentResult> results;
      if (_isAnime) {
        final animeQuery = await widget.torrentStreamService.queryBuilder.build(
          widget.media,
          _episode,
          season: widget.initialSeason,
          resolution: _resolution,
          absoluteEpisode: widget.initialAbsoluteEpisode,
        );
        _currentQuery = animeQuery;
        
        results = await widget.torrentStreamService.searchTorrents(
          query: animeQuery,
          onStatus: widget.onStatusUpdate,
        );
      } else {
        final isMovie = _isMovie;
        widget.onStatusUpdate?.call('Resolving IMDb ID…');
        String? imdbId;
        if (widget.torrentStreamService.tmdbService != null) {
          imdbId = await widget.torrentStreamService.tmdbService!.getImdbId(
            tmdbId: widget.media.id,
            isMovie: isMovie,
          );
        }
        
        if (imdbId == null || imdbId.isEmpty) {
          if (!mounted) return;
          setState(() {
            _error = 'Could not resolve IMDb ID for torrent search.';
          });
          return;
        }

        final mediaQuery = MediaTorrentQuery(
          imdbId: imdbId,
          tmdbId: widget.media.id,
          title: widget.media.title ?? widget.media.name ?? '',
          isMovie: isMovie,
          season: isMovie ? null : widget.initialSeason,
          episode: isMovie ? null : _episode,
          resolution: _resolution,
        );
        _currentQuery = mediaQuery;

        results = await widget.torrentStreamService.searchMediaTorrents(
          query: mediaQuery,
          onStatus: widget.onStatusUpdate,
        );
      }
      
      if (!mounted) return;
      
      // Preserve the ranking order from the service (TorrentRanking for anime,
      // MediaRanking for movies/shows) — it already accounts for the selected
      // resolution, so re-sorting by seeders here would override that.

      setState(() {
        _filteredResults = results;
      });
      
      if (results.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final autoSelect = prefs.getBool('torrent_auto_select') ?? true;
        if (autoSelect) {
          _countdown = 5;
          _startAutoPlay();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  Future<void> _executeCustomSearch() async {
    final text = _searchController.text.trim();
    if (text.isEmpty) {
      _loadTorrents(); // Reset to normal search
      return;
    }

    _cancelAutoPlay();

    // Support direct magnet links
    if (text.startsWith('magnet:?')) {
      final syntheticResult = TorrentResult(
        title: 'Direct Magnet Link',
        link: text,
        seeders: 0,
        leechers: 0,
        sizeBytes: 0,
        source: 'magnet',
        accuracy: 'high',
      );
      
      final dummyQuery = _isAnime
          ? AnimeQuery(
              titles: [text],
              episode: _episode,
              season: widget.initialSeason,
              anilistId: widget.media.id,
            )
          : MediaTorrentQuery(
              title: text,
              isMovie: _isMovie,
              season: _isMovie ? null : widget.initialSeason,
              episode: _isMovie ? null : _episode,
              rawQuery: text,
            );

      _cancelAutoPlay();
      Navigator.of(context).pop((syntheticResult, dummyQuery));
      return;
    }

    setState(() {
      _filteredResults = null; // show loading
      _error = null;
    });

    try {
      List<TorrentResult> results;
      if (_isAnime) {
        final customQuery = AnimeQuery(
          titles: [text],
          episode: _episode,
          season: widget.initialSeason,
          anilistId: widget.media.id,
          absoluteEpisode: widget.initialAbsoluteEpisode,
          resolution: _resolution,
          isManual: true,
        );
        _currentQuery = customQuery;

        results = await widget.torrentStreamService.searchTorrents(
          query: customQuery,
          onStatus: widget.onStatusUpdate,
        );
      } else {
        // Manual movie/show search is a pure free-text query: send exactly what
        // the user typed, with NO episode/season/resolution/IMDb modifications.
        // PirateBay does the text search (Torrentio needs an IMDb id, so it
        // simply returns nothing here). Results are shown raw (rank: false).
        final customQuery = MediaTorrentQuery(
          title: text,
          isMovie: _isMovie,
          isManual: true,
          rawQuery: text,
        );
        _currentQuery = customQuery;

        results = await widget.torrentStreamService.searchMediaTorrents(
          query: customQuery,
          onStatus: widget.onStatusUpdate,
          rank: false,
        );
      }

      if (!mounted) return;
      
      // Preserve the ranking order from the service (TorrentRanking for anime,
      // MediaRanking for movies/shows) — it already accounts for the selected
      // resolution, so re-sorting by seeders here would override that.

      setState(() {
        _filteredResults = results;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    }
  }

  void _startAutoPlay() {
    _autoPlayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isCancelled || !mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _countdown--;
      });
      if (_countdown <= 0) {
        timer.cancel();
        if (_filteredResults != null && _filteredResults!.isNotEmpty) {
          _playResult(_filteredResults!.first);
        }
      }
    });
  }

  void _cancelAutoPlay() {
    if (!_isCancelled) {
      setState(() {
        _isCancelled = true;
      });
      _autoPlayTimer?.cancel();
    }
  }

  void _playResult(TorrentResult result) {
    if (_currentQuery == null) return;
    _autoPlayTimer?.cancel();
    Navigator.of(context).pop((result, _currentQuery!));
  }
  
  Future<void> _updateResolution(String? newRes) async {
    if (newRes == null || newRes == _resolution) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nivio_torrent_resolution', newRes);
    
    setState(() {
      _resolution = newRes;
    });
    _loadTorrents();
  }
  
  Future<void> _updateEpisode(String? newEpStr) async {
    if (newEpStr == null) return;
    final newEp = int.tryParse(newEpStr);
    if (newEp == null || newEp == _episode) return;
    
    setState(() {
      _episode = newEp;
    });
    _loadTorrents();
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _isTrusted(TorrentResult r) {
    if (r.isBest) return true;
    final lowerTitle = r.title.toLowerCase();
    const trustedGroups = [
      'subsplease', 'erai-raws', 'judas', 'ember', 'seadex', 'flugel', 'ozr', 'kawatare',
      'yts', 'eztv', 'tgx', 'qxr', 'rarbg', 'psa', 'galaxyrg', '1tamilmv', 'tamilblasters'
    ];
    for (final group in trustedGroups) {
      if (lowerTitle.contains('[$group]') || lowerTitle.contains('($group)') || lowerTitle.contains(group)) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final isFullScreen = widget.isFullScreen;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final isCompactLandscape = isFullScreen && isLandscape;
    final spacing = isCompactLandscape ? 8.0 : 16.0;
    final horizontalPadding = isFullScreen ? 16.0 : 24.0;
    
    final title = widget.media.title ?? widget.media.name ?? 'Select Torrent';
    final backdropPath = widget.media.backdropPath ?? widget.media.posterPath;
    final backdropUrl = (backdropPath != null && backdropPath.startsWith('http')) 
        ? backdropPath 
        : (backdropPath != null ? 'https://image.tmdb.org/t/p/w780$backdropPath' : null);
    
    return MouseRegion(
      onHover: (_) => _cancelAutoPlay(),
      child: Listener(
        onPointerHover: (_) => _cancelAutoPlay(),
        onPointerDown: (_) => _cancelAutoPlay(),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: isFullScreen ? BorderRadius.zero : BorderRadius.circular(12),
            border: isFullScreen ? null : Border.all(color: Colors.white.withOpacity(0.05)),
            boxShadow: isFullScreen ? null : [
              BoxShadow(
                color: Colors.black.withOpacity(0.8),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          constraints: isFullScreen
              ? const BoxConstraints.expand()
              : BoxConstraints(
                  maxWidth: 800,
                  maxHeight: MediaQuery.of(context).size.height * 0.85,
                ),
          child: ClipRRect(
            borderRadius: isFullScreen ? BorderRadius.zero : BorderRadius.circular(12),
            child: Stack(
              children: [
                if (backdropUrl != null)
                  Positioned(
                    top: 0, left: 0, right: 0, 
                    height: isCompactLandscape ? 180 : 320,
                    child: ShaderMask(
                      shaderCallback: (rect) {
                        return const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black, Colors.transparent],
                          stops: [0.4, 0.9],
                        ).createShader(rect);
                      },
                      blendMode: BlendMode.dstIn,
                      child: Container(
                        decoration: BoxDecoration(
                          image: DecorationImage(
                            image: NetworkImage(backdropUrl),
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                          ),
                        ),
                        foregroundDecoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF0F0F0F).withOpacity(0.4),
                              const Color(0xFF0F0F0F).withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                
                SafeArea(
                  top: isFullScreen,
                  bottom: isFullScreen,
                  left: isFullScreen,
                  right: isFullScreen,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          isFullScreen ? 8.0 : 24.0, 
                          isFullScreen ? (isCompactLandscape ? 4.0 : 8.0) : 20.0, 
                          16.0, 
                          spacing,
                        ),
                        child: Row(
                          children: [
                            if (isFullScreen) ...[
                              IconButton(
                                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                                onPressed: () {
                                  _cancelAutoPlay();
                                  Navigator.of(context).pop();
                                },
                                splashRadius: 20,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: MarqueeText(
                                text: title,
                                style: TextStyle(
                                  fontSize: isFullScreen ? 19 : 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                blankSpace: 40.0,
                                velocity: 30.0,
                              ),
                            ),
                            if (!isFullScreen)
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white70),
                                onPressed: () {
                                  _cancelAutoPlay();
                                  Navigator.of(context).pop();
                                },
                                hoverColor: Colors.white.withOpacity(0.1),
                                splashRadius: 20,
                              ),
                          ],
                        ),
                      ),
                      
                      // Controls (Search, Episode, Resolution)
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (isCompactLandscape)
                              Row(
                                children: [
                                  Expanded(child: _buildSearchTextField(spacing)),
                                  if (!_isMovie) ...[
                                    const SizedBox(width: 12),
                                    _buildEpisodeSelector(),
                                  ],
                                  const SizedBox(width: 12),
                                  _buildResolutionSelector(),
                                ],
                              )
                            else ...[
                              _buildSearchTextField(spacing),
                              SizedBox(height: spacing),
                              Row(
                                children: [
                                  if (!_isMovie) ...[
                                    _buildEpisodeSelector(),
                                    const SizedBox(width: 24),
                                  ],
                                  _buildResolutionSelector(),
                                ],
                              ),
                            ],
                            SizedBox(height: spacing),
                            _buildAutoSelectButton(spacing),
                          ],
                        ),
                      ),
                      
                      SizedBox(height: spacing),
                      const Divider(height: 1, thickness: 1, color: Color(0xFF2A2A2A)),
                      
                      // Results List
                      Expanded(
                        child: _buildContent(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchTextField(double spacing) {
    return TextField(
      controller: _searchController,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _executeCustomSearch(),
      decoration: InputDecoration(
        hintText: 'Search manually or paste magnet...',
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 14),
        prefixIcon: Icon(Icons.search, color: Colors.white.withOpacity(0.5), size: 20),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward_rounded, color: Color(0xFF38Bdf8), size: 20),
          onPressed: _executeCustomSearch,
          splashRadius: 20,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        contentPadding: EdgeInsets.symmetric(vertical: spacing),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildEpisodeSelector() {
    final epCount = _currentQuery is AnimeQuery
        ? (_currentQuery as AnimeQuery).episodeCount ?? 25
        : 25;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Episode ', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        _buildDropdown(
          value: _episode.toString(),
          items: List.generate(
            epCount, 
            (i) => (i + 1).toString()
          ),
          onChanged: _updateEpisode,
        ),
      ],
    );
  }

  Widget _buildResolutionSelector() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Resolution ', style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(width: 8),
        _buildDropdown(
          value: _resolution,
          items: ['480', '720', '1080', '2160'],
          onChanged: _updateResolution,
          suffix: 'p',
        ),
      ],
    );
  }

  Widget _buildAutoSelectButton(double spacing) {
    if (_filteredResults != null && _filteredResults!.isNotEmpty && !_isCancelled) {
      return ElevatedButton(
        onPressed: () => _playResult(_filteredResults!.first),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF38Bdf8),
          foregroundColor: Colors.black,
          padding: EdgeInsets.symmetric(vertical: spacing),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(
          'Auto Select Torrent (in $_countdown)',
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );
    } else if (_filteredResults != null && _filteredResults!.isNotEmpty) {
      return ElevatedButton(
        onPressed: () => _playResult(_filteredResults!.first),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF38Bdf8),
          foregroundColor: Colors.black,
          padding: EdgeInsets.symmetric(vertical: spacing),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: const Text(
          'Auto Select Torrent',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
        ),
      );
    }
    return const SizedBox.shrink();
  }
  
  Widget _buildDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    String suffix = '',
  }) {
    // Make sure value is in items, otherwise add it
    if (!items.contains(value)) {
      items = [...items, value];
      items.sort((a, b) => (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0));
    }
    
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: const Color(0xFF1A1A1A),
          icon: const Padding(
            padding: EdgeInsets.only(left: 8.0),
            child: Icon(Icons.unfold_more, color: Colors.white54, size: 16),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text('$item$suffix'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
              const SizedBox(height: 20),
              Text(
                'Failed to find torrents',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredResults == null) {
      final isMobile = Platform.isAndroid || Platform.isIOS;
      return Skeletonizer(
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 7,
          itemBuilder: (context, __) => Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 16 : 24,
              vertical: isMobile ? 12 : 16,
            ),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                // Torrent title line
                SkeletonBox(width: double.infinity, height: 15),
                SizedBox(height: 10),
                // Quality / size / seeders tag chips
                Row(
                  children: [
                    SkeletonBox(
                        width: 60,
                        height: 20,
                        borderRadius: BorderRadius.all(Radius.circular(4))),
                    SizedBox(width: 8),
                    SkeletonBox(
                        width: 74,
                        height: 20,
                        borderRadius: BorderRadius.all(Radius.circular(4))),
                    SizedBox(width: 8),
                    SkeletonBox(
                        width: 54,
                        height: 20,
                        borderRadius: BorderRadius.all(Radius.circular(4))),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_filteredResults!.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(48.0),
          child: Text(
            _isMovie
                ? 'No torrents found for this movie.'
                : 'No torrents found for this episode.', 
            style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _filteredResults!.length,
      itemBuilder: (context, index) {
        final r = _filteredResults![index];
        final isBest = index == 0;
        final isTrusted = _isTrusted(r);
        
        return _HoverTorrentCard(
          r: r,
          isBest: isBest,
          isTrusted: isTrusted,
          isCancelled: _isCancelled,
          onTap: () {
            _cancelAutoPlay();
            _playResult(r);
          },
        );
      },
    );
  }
}

class _HoverTorrentCard extends StatefulWidget {
  final TorrentResult r;
  final bool isBest;
  final bool isTrusted;
  final bool isCancelled;
  final VoidCallback onTap;

  const _HoverTorrentCard({
    Key? key,
    required this.r,
    required this.isBest,
    required this.isTrusted,
    required this.isCancelled,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_HoverTorrentCard> createState() => _HoverTorrentCardState();
}

class _HoverTorrentCardState extends State<_HoverTorrentCard> {
  bool _isHovered = false;

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    final kb = bytes / 1024;
    final mb = kb / 1024;
    final gb = mb / 1024;
    if (gb >= 1) return '${gb.toStringAsFixed(2)} GB';
    if (mb >= 1) return '${mb.toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(1)} KB';
  }

  Widget _buildTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildStatTag(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final hideVerifiedText = isMobile && isPortrait;
    final r = widget.r;
    final isBest = widget.isBest;
    final isTrusted = widget.isTrusted;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        style: DpadFocusStyle.subtle,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24, vertical: isMobile ? 12 : 16),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white.withOpacity(0.05)),
            ),
            color: _isHovered 
                ? Colors.white.withOpacity(0.05)
                : (isBest && !widget.isCancelled 
                    ? Colors.white.withOpacity(0.03) 
                    : Colors.transparent),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      r.title,
                      style: TextStyle(
                        fontSize: isMobile ? 13.5 : 14.5,
                        height: 1.4,
                        fontWeight: isBest ? FontWeight.bold : FontWeight.normal,
                        color: isBest ? Colors.white : Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ),
                  if (isBest)
                    Container(
                      margin: const EdgeInsets.only(left: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF38Bdf8).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF38Bdf8).withOpacity(0.3)),
                      ),
                      child: const Text(
                        'BEST MATCH',
                        style: TextStyle(
                          color: Color(0xFF38Bdf8),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (isTrusted) ...[
                            const Icon(Icons.verified_rounded, color: Color(0xFF38Bdf8), size: 16),
                            if (!hideVerifiedText) ...[
                              const SizedBox(width: 4),
                              const Text(
                                'Verified',
                                style: TextStyle(color: Color(0xFF38Bdf8), fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                            const SizedBox(width: 8),
                          ],
                          _buildTag(r.source.toUpperCase(), const Color(0xFFC084FC)),
                          const SizedBox(width: 8),
                          if (r.parsed.resolution != null) ...[
                            _buildTag('${r.parsed.resolution}p', const Color(0xFF60A5FA)),
                            const SizedBox(width: 8),
                          ],
                          _buildTag(_formatSize(r.sizeBytes), Colors.grey),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatTag(Icons.arrow_upward_rounded, r.seeders.toString(), const Color(0xFF4ADE80)),
                  const SizedBox(width: 8),
                  _buildStatTag(Icons.arrow_downward_rounded, r.leechers.toString(), const Color(0xFFF87171)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
