import 'dart:async';
import 'package:flutter/material.dart';
import 'package:nivio/widgets/playback_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/torrent/torrent_models.dart';
import 'package:nivio/services/torrent/media_torrent_models.dart';
import 'package:nivio/services/torrent/torrent_stream_service.dart';
import 'package:nivio/widgets/skeleton.dart';
import 'package:nivio/services/streaming_service.dart';

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

  static Future<(TorrentResult, dynamic, {bool automatic})?> show(
    BuildContext context, {
    required SearchResult media,
    required int initialEpisode,
    required int initialSeason,
    int? initialAbsoluteEpisode,
    required String initialResolution,
    required TorrentStreamService torrentStreamService,
    void Function(String status)? onStatusUpdate,
  }) {
    return PlaybackPickerFrame.show<(TorrentResult, dynamic, {bool automatic})>(
      context,
      (fullScreen) => TorrentPickerSheet(
        media: media,
        initialEpisode: initialEpisode,
        initialSeason: initialSeason,
        initialAbsoluteEpisode: initialAbsoluteEpisode,
        initialResolution: initialResolution,
        torrentStreamService: torrentStreamService,
        onStatusUpdate: onStatusUpdate,
        isFullScreen: fullScreen,
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
      Navigator.of(context).pop((syntheticResult, dummyQuery, automatic: false));
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
          _playResult(_filteredResults!.first, automatic: true);
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

  void _playResult(TorrentResult result, {bool automatic = false}) {
    if (_currentQuery == null) return;
    _autoPlayTimer?.cancel();
    Navigator.of(context).pop((result, _currentQuery!, automatic: automatic));
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
    final isCompactLandscape =
        isFullScreen && MediaQuery.orientationOf(context) == Orientation.landscape;
    final spacing = isCompactLandscape ? 8.0 : 16.0;
    final horizontalPadding = isFullScreen ? 16.0 : 24.0;

    return MouseRegion(
      onHover: (_) => _cancelAutoPlay(),
      child: Listener(
        onPointerHover: (_) => _cancelAutoPlay(),
        onPointerDown: (_) => _cancelAutoPlay(),
        child: PlaybackPickerFrame(
          media: widget.media,
          fullScreen: isFullScreen,
          label: 'Choose torrent',
          onClose: () {
            _cancelAutoPlay();
            Navigator.of(context).pop();
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const Divider(height: 1, thickness: 1, color: Colors.white12),
              Expanded(child: _buildContent()),
            ],
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
          icon: const Icon(Icons.arrow_forward_rounded, color: playbackPickerAccent, size: 20),
          onPressed: _executeCustomSearch,
          splashRadius: 20,
        ),
        filled: true,
        fillColor: playbackPickerField,
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
        onPressed: () => _playResult(_filteredResults!.first, automatic: true),
        style: ElevatedButton.styleFrom(
          backgroundColor: playbackPickerAccent,
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
        onPressed: () => _playResult(_filteredResults!.first, automatic: true),
        style: ElevatedButton.styleFrom(
          backgroundColor: playbackPickerAccent,
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
        color: playbackPickerField,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          dropdownColor: playbackPickerField,
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
      final isMobile = widget.isFullScreen;
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
        
        return PlaybackPickerRow(
          title: r.title,
          marker: isBest ? 'BEST MATCH' : null,
          highlighted: isBest && !_isCancelled,
          tags: [
            if (isTrusted)
              const PlaybackPickerTag('Verified', color: playbackPickerAccent, icon: Icons.verified_rounded),
            PlaybackPickerTag(r.source.toUpperCase(), color: playbackPickerProviderColor),
            if (r.parsed.resolution != null)
              PlaybackPickerTag('${r.parsed.resolution}p', color: playbackPickerQualityColor),
            PlaybackPickerTag(formatPlaybackPickerSize(r.sizeBytes), color: Colors.white70),
            ...playbackPickerPeerTags(r),
          ],
          onTap: () {
            _cancelAutoPlay();
            _playResult(r);
          },
        );
      },
    );
  }
}
