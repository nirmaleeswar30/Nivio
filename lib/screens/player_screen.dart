import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/media_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/models/stream_result.dart';
import 'package:nivio/widgets/webview_player.dart';
import 'dart:async';

class PlayerScreen extends ConsumerStatefulWidget {
  final int mediaId;
  final int season;
  final int episode;
  final String? mediaType;

  const PlayerScreen({
    super.key,
    required this.mediaId,
    required this.season,
    required this.episode,
    this.mediaType,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  StreamResult? _streamResult;
  bool _isLoading = true;
  String? _error;
  Timer? _progressTimer;
  String _currentProvider = '';
  int _retryCount = 0;
  int _currentProviderIndex = 0; // Track which provider we're using
  static const int _maxRetries = 3;
  static const int _maxProviders = 3; // vidsrc.cc, vidsrc.to, vidlink
  static const List<String> _providerNames = ['vidsrc.cc', 'vidsrc.to', 'vidlink'];
  final FocusNode _focusNode = FocusNode();
  bool _showNextEpisodeButton = false;
  Timer? _nextEpisodeTimer;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
    // Set preferred orientations for better video experience
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
      DeviceOrientation.portraitUp,
    ]);
    // Request focus for keyboard shortcuts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
      case LogicalKeyboardKey.keyK:
        // Play/Pause
        if (_videoController!.value.isPlaying) {
          _videoController!.pause();
        } else {
          _videoController!.play();
        }
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.keyJ:
        // Seek backward 10s
        final currentPos = _videoController!.value.position;
        final newPos = currentPos - const Duration(seconds: 10);
        _videoController!.seekTo(newPos < Duration.zero ? Duration.zero : newPos);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.keyL:
        // Seek forward 10s
        final currentPos = _videoController!.value.position;
        final duration = _videoController!.value.duration;
        final newPos = currentPos + const Duration(seconds: 10);
        _videoController!.seekTo(newPos > duration ? duration : newPos);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.keyF:
        // Toggle fullscreen (handled by Chewie)
        return KeyEventResult.ignored;

      case LogicalKeyboardKey.keyM:
        // Mute/Unmute
        final currentVolume = _videoController!.value.volume;
        _videoController!.setVolume(currentVolume > 0 ? 0 : 1);
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowUp:
        // Volume up
        final currentVolume = _videoController!.value.volume;
        _videoController!.setVolume((currentVolume + 0.1).clamp(0, 1));
        return KeyEventResult.handled;

      case LogicalKeyboardKey.arrowDown:
        // Volume down
        final currentVolume = _videoController!.value.volume;
        _videoController!.setVolume((currentVolume - 0.1).clamp(0, 1));
        return KeyEventResult.handled;

      default:
        return KeyEventResult.ignored;
    }
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check if media is already selected, if not fetch it from TMDB
      var media = ref.read(selectedMediaProvider);
      if (media == null) {
        print('📥 Fetching media details from TMDB (ID: ${widget.mediaId}, Type: ${widget.mediaType})...');
        setState(() {
          _currentProvider = 'Loading media details...';
        });
        
        // Fetch media details from TMDB
        final tmdbService = ref.read(tmdbServiceProvider);
        
        // Use mediaType if provided, otherwise try TV first then movie
        if (widget.mediaType == 'tv') {
          media = await tmdbService.getTVShowDetails(widget.mediaId);
          ref.read(selectedMediaProvider.notifier).state = media;
          print('✅ Loaded TV show: ${media.name}');
        } else if (widget.mediaType == 'movie') {
          media = await tmdbService.getMovieDetails(widget.mediaId);
          ref.read(selectedMediaProvider.notifier).state = media;
          print('✅ Loaded movie: ${media.title}');
        } else {
          // No type specified, try TV show first, then movie
          try {
            media = await tmdbService.getTVShowDetails(widget.mediaId);
            ref.read(selectedMediaProvider.notifier).state = media;
            print('✅ Loaded TV show: ${media.name}');
          } catch (e) {
            // If TV show fails, try movie
            media = await tmdbService.getMovieDetails(widget.mediaId);
            ref.read(selectedMediaProvider.notifier).state = media;
            print('✅ Loaded movie: ${media.title}');
          }
        }
      }

      // Show which provider we're trying
      setState(() {
        _currentProvider = 'Fetching stream...';
      });

      // Fetch stream URL from streaming service
      final streamingService = ref.read(streamingServiceProvider);
      
      // Use quality from settings (user's preference)
      final settingsQuality = ref.read(videoQualityProvider);
      
      // If user manually selected a quality in player, use that. Otherwise use settings.
      final manualQuality = ref.read(selectedQualityProvider);
      final preferredQuality = manualQuality ?? (settingsQuality == 'auto' ? null : settingsQuality);
      
      // Get anime sub/dub preference
      final subDubPref = ref.read(animeSubDubProvider);

      final result = await streamingService.fetchStreamUrl(
        media: media,
        season: widget.season,
        episode: widget.episode,
        preferredQuality: preferredQuality,
        providerIndex: _currentProviderIndex, // Use current provider index
        subDubPreference: subDubPref, // Pass anime preference
      );

      if (result == null) {
        // Try next provider if available
        if (_currentProviderIndex < _maxProviders - 1) {
          print('⏭️ Trying next provider...');
          _currentProviderIndex++;
          setState(() {
            _error = 'Provider unavailable, trying next...';
          });
          await Future.delayed(const Duration(milliseconds: 500));
          _initializePlayer(); // Retry with next provider
          return;
        }
        throw Exception('Failed to get stream URL from all providers');
      }

      _streamResult = result;
      _currentProvider = result.provider;

      // Check if this is an iframe embed provider (vidsrc.cc, vidsrc.to, vidlink)
      if (result.provider == 'vidsrc.cc' || 
          result.provider == 'vidsrc.to' || 
          result.provider == 'vidlink') {
        print('✅ Using WebView for ${result.provider} embed');
        print('📺 VidSrc will send real-time player events via postMessage');
        
        setState(() {
          _isLoading = false;
          _retryCount = 0;
        });
        return; // WebView will be rendered in build method with event handler
      }

      // For direct video URLs, use video_player + chewie
      print('✅ Using video_player for direct stream URL');
      
      // Initialize video player with error handling
      _videoController = VideoPlayerController.networkUrl(
        Uri.parse(result.url),
        httpHeaders: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        },
      );

      // Add listener for player state changes
      _videoController!.addListener(_onVideoPlayerStateChanged);

      await _videoController!.initialize();

      // Get playback speed from settings and apply it
      final playbackSpeed = ref.read(playbackSpeedProvider);
      await _videoController!.setPlaybackSpeed(playbackSpeed);

      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        playbackSpeeds: const [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0],
        materialProgressColors: ChewieProgressColors(
          playedColor: NivioTheme.netflixRed,
          handleColor: NivioTheme.netflixRed,
          backgroundColor: NivioTheme.netflixGrey,
          bufferedColor: NivioTheme.netflixLightGrey,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(
              color: NivioTheme.netflixRed,
            ),
          ),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: NivioTheme.netflixRed,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Playback Error',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  errorMessage,
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    if (_retryCount < _maxRetries) {
                      _retryCount++;
                      _initializePlayer();
                    }
                  },
                  icon: const Icon(Icons.refresh),
                  label: Text('Retry ($_retryCount/$_maxRetries)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NivioTheme.netflixRed,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
        },
        autoInitialize: true,
      );

      // Start progress tracking
      _startProgressTracking();

      // Check for existing watch history to resume
      final historyService = ref.read(watchHistoryServiceProvider);
      await historyService.init();
      final history = await historyService.getHistory(widget.mediaId);
      
      if (history != null &&
          history.currentSeason == widget.season &&
          history.currentEpisode == widget.episode &&
          history.lastPositionSeconds > 0 &&
          history.lastPositionSeconds < history.totalDurationSeconds - 30) {
        // Resume from last position (if not within 30s of end)
        await _videoController!.seekTo(
          Duration(seconds: history.lastPositionSeconds),
        );
        
        // Show resume notification
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Resumed from ${_formatDuration(Duration(seconds: history.lastPositionSeconds))}'),
              duration: const Duration(seconds: 2),
              backgroundColor: NivioTheme.netflixRed,
            ),
          );
        }
      }

      setState(() {
        _isLoading = false;
        _retryCount = 0; // Reset retry count on success
        _currentProviderIndex = 0; // Reset provider index on success
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      
      // Try next provider first before retrying same provider
      if (_currentProviderIndex < _maxProviders - 1) {
        print('❌ Error with provider, trying next: $e');
        _currentProviderIndex++;
        setState(() {
          _error = 'Switching to next provider...';
        });
        await Future.delayed(const Duration(milliseconds: 500));
        _initializePlayer();
        return;
      }
      
      // All providers failed, try auto-retry on certain errors
      if (_retryCount < _maxRetries && 
          (e.toString().contains('network') || e.toString().contains('timeout'))) {
        await Future.delayed(const Duration(seconds: 2));
        _retryCount++;
        _currentProviderIndex = 0; // Reset to first provider
        _initializePlayer();
      }
    }
  }

  void _onVideoPlayerStateChanged() {
    if (_videoController == null || !_videoController!.value.isInitialized) return;
    
    // Handle buffering state
    if (_videoController!.value.isBuffering) {
      // Could show buffering indicator here
    }
    
    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;
    
    // Show next episode button at 95% completion (Netflix style)
    if (duration.inSeconds > 0) {
      final progress = position.inSeconds / duration.inSeconds;
      if (progress >= 0.95 && !_showNextEpisodeButton && _hasNextEpisode()) {
        setState(() {
          _showNextEpisodeButton = true;
        });
      }
    }
    
    // Auto-save progress when video completes
    if (position >= duration - const Duration(seconds: 30)) {
      _markAsCompleted();
      // Auto-play next episode immediately on completion
      if (_hasNextEpisode() && !_showNextEpisodeButton) {
        print('⏭️ Auto-playing next episode...');
        setState(() {
          _showNextEpisodeButton = true; // Prevent multiple triggers
        });
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _playNextEpisode();
        });
      }
    }
  }

  Future<void> _markAsCompleted() async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;

    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: widget.episode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: _videoController!.value.duration,
      totalDuration: _videoController!.value.duration,
    );
  }

  /// Handle VidSrc player events (play, pause, time, complete)
  void _handlePlayerEvent(String event, double currentTime, double duration) {
    print('📺 VidSrc Event: $event | ${currentTime.toInt()}s / ${duration.toInt()}s');
    
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;
    
    switch (event) {
      case 'play':
        print('▶️ Video started playing');
        break;
        
      case 'pause':
        print('⏸️ Video paused');
        break;
        
      case 'time':
        // Update progress every ~5 seconds (VidSrc sends this automatically)
        _saveWebViewProgress(currentTime, duration);
        
        // Show next episode button at 95% completion (Netflix style)
        final progress = currentTime / duration;
        if (progress >= 0.95 && !_showNextEpisodeButton && _hasNextEpisode()) {
          setState(() {
            _showNextEpisodeButton = true;
          });
        }
        break;
        
      case 'complete':
        print('✅ Video completed');
        _markWebViewAsCompleted(duration);
        // Auto-play next episode immediately on completion
        if (_hasNextEpisode()) {
          print('⏭️ Auto-playing next episode...');
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) _playNextEpisode();
          });
        }
        break;
    }
  }
  
  /// Check if there's a next episode available
  bool _hasNextEpisode() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return false;
    
    // For now, always return true for TV shows
    // TODO: Check actual episode count from TMDB data
    return true;
  }
  
  /// Navigate to next episode
  void _playNextEpisode() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return;
    
    // Navigate to next episode
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => PlayerScreen(
          mediaId: widget.mediaId,
          season: widget.season,
          episode: widget.episode + 1, // Next episode
          mediaType: media.mediaType,
        ),
      ),
    );
  }
  
  /// Show episodes bottom sheet
  void _showEpisodesBottomSheet() {
    final media = ref.read(selectedMediaProvider);
    if (media == null || media.mediaType != 'tv') return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          final seasonDataAsync = ref.watch(
            seasonDataProvider((showId: widget.mediaId, seasonNumber: widget.season)),
          );
          
          return seasonDataAsync.when(
            data: (seasonData) => Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey[600],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Title
                  Text(
                    'Season ${widget.season}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${seasonData.episodes.length} Episodes',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Episodes list
                  Expanded(
                    child: ListView.builder(
                      controller: scrollController,
                      itemCount: seasonData.episodes.length,
                      itemBuilder: (context, index) {
                        final episode = seasonData.episodes[index];
                        final isCurrentEpisode = episode.episodeNumber == widget.episode;
                        
                        return InkWell(
                          onTap: () {
                            Navigator.pop(context); // Close bottom sheet
                            if (!isCurrentEpisode) {
                              // Navigate to selected episode
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (context) => PlayerScreen(
                                    mediaId: widget.mediaId,
                                    season: widget.season,
                                    episode: episode.episodeNumber,
                                    mediaType: media.mediaType,
                                  ),
                                ),
                              );
                            }
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isCurrentEpisode
                                  ? NivioTheme.netflixRed.withOpacity(0.2)
                                  : const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                              border: isCurrentEpisode
                                  ? Border.all(color: NivioTheme.netflixRed, width: 2)
                                  : null,
                            ),
                            child: Row(
                              children: [
                                // Episode number
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: isCurrentEpisode
                                        ? NivioTheme.netflixRed
                                        : Colors.grey[800],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${episode.episodeNumber}',
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Episode info
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        episode.episodeName ?? 'Episode ${episode.episodeNumber}',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: isCurrentEpisode ? NivioTheme.netflixRed : Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (episode.runtime != null) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          '${episode.runtime} min',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[400],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // Play icon
                                Icon(
                                  isCurrentEpisode ? Icons.play_circle_filled : Icons.play_arrow,
                                  color: isCurrentEpisode ? NivioTheme.netflixRed : Colors.white,
                                  size: 32,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            loading: () => const Center(
              child: CircularProgressIndicator(color: NivioTheme.netflixRed),
            ),
            error: (error, stack) => Center(
              child: Text(
                'Error loading episodes',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        },
      ),
    );
  }
  
  /// Save progress from WebView player events
  Future<void> _saveWebViewProgress(double currentTime, double duration) async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;

    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: widget.episode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: Duration(seconds: currentTime.toInt()),
      totalDuration: Duration(seconds: duration.toInt()),
    );
  }
  
  /// Mark WebView video as completed
  Future<void> _markWebViewAsCompleted(double duration) async {
    final media = ref.read(selectedMediaProvider);
    if (media == null) return;

    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: widget.episode,
      totalSeasons: 1,
      totalEpisodes: null,
      lastPosition: Duration(seconds: duration.toInt()),
      totalDuration: Duration(seconds: duration.toInt()),
    );
    
    print('✅ Marked as completed: ${media.title ?? media.name}');
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  void _startProgressTracking() {
    _progressTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (_videoController != null &&
          _videoController!.value.isInitialized &&
          _videoController!.value.isPlaying) {
        _saveProgress();
      }
    });
  }

  Future<void> _saveProgress() async {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return;
    }

    final media = ref.read(selectedMediaProvider);
    if (media == null) return;

    final position = _videoController!.value.position;
    final duration = _videoController!.value.duration;

    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.updateProgress(
      tmdbId: widget.mediaId,
      mediaType: media.mediaType,
      title: media.title ?? media.name ?? 'Unknown',
      posterPath: media.posterPath,
      currentSeason: widget.season,
      currentEpisode: widget.episode,
      totalSeasons: 1, // TODO: Get from series info
      totalEpisodes: null,
      lastPosition: position,
      totalDuration: duration,
    );
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    
    // Save progress for video_player
    if (_videoController != null && _videoController!.value.isInitialized) {
      _saveProgress();
    }
    
    _videoController?.removeListener(_onVideoPlayerStateChanged);
    _videoController?.dispose();
    _chewieController?.dispose();
    _focusNode.dispose();
    
    // Reset orientations
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(selectedMediaProvider);
    
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: _streamResult != null
            ? AppBar(
                backgroundColor: Colors.black.withOpacity(0.7),
                elevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                  tooltip: 'Back',
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      media?.title ?? media?.name ?? 'Playing',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        if (media?.mediaType == 'tv')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NivioTheme.netflixRed,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              'S${widget.season} E${widget.episode}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            _streamResult!.provider.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: Colors.white70,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                actions: [
                  // Episodes button (only for TV shows)
                  if (media?.mediaType == 'tv')
                    IconButton(
                      icon: const Icon(Icons.list, color: Colors.white),
                      tooltip: 'Episodes',
                      onPressed: () => _showEpisodesBottomSheet(),
                    ),
                  // Switch Server button
                  PopupMenuButton<int>(
                    icon: const Icon(Icons.swap_horiz, color: Colors.white),
                    tooltip: 'Switch Server',
                    color: const Color(0xFF1F1F1F),
                    onSelected: (providerIndex) async {
                      if (providerIndex == _currentProviderIndex) return; // Same provider
                      
                      final currentPosition = _videoController?.value.position;
                      
                      // Show snackbar before rebuilding
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Switching to ${_providerNames[providerIndex]}...'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: NivioTheme.netflixRed,
                          ),
                        );
                      }
                      
                      // Dispose controllers first
                      _videoController?.dispose();
                      _chewieController?.dispose();
                      _videoController = null;
                      _chewieController = null;
                      
                      // Then update state and reinitialize
                      setState(() {
                        _currentProviderIndex = providerIndex;
                        _isLoading = true;
                        _error = null;
                        _retryCount = 0;
                        _streamResult = null; // Clear old stream result to force rebuild
                      });
                      
                      await _initializePlayer();
                      
                      if (currentPosition != null && _videoController != null) {
                        await _videoController!.seekTo(currentPosition);
                      }
                    },
                    itemBuilder: (context) {
                      return List.generate(_maxProviders, (index) {
                        final isSelected = index == _currentProviderIndex;
                        return PopupMenuItem(
                          value: index,
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                color: isSelected ? NivioTheme.netflixRed : Colors.white70,
                                size: 18,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _providerNames[index],
                                style: TextStyle(
                                  color: isSelected ? NivioTheme.netflixRed : Colors.white,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                            ],
                          ),
                        );
                      });
                    },
                  ),
                  // Quality selector
                  if (_streamResult!.availableQualities.length > 1)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.hd, color: Colors.white),
                      tooltip: 'Quality',
                      color: const Color(0xFF1F1F1F),
                      onSelected: (quality) async {
                        final currentPosition = _videoController?.value.position;
                        ref.read(selectedQualityProvider.notifier).state = quality;
                        
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Switching to $quality...'),
                            duration: const Duration(seconds: 2),
                            backgroundColor: NivioTheme.netflixRed,
                          ),
                        );
                        
                        _videoController?.dispose();
                        _chewieController?.dispose();
                        await _initializePlayer();
                        
                        if (currentPosition != null && _videoController != null) {
                          await _videoController!.seekTo(currentPosition);
                        }
                      },
                      itemBuilder: (context) {
                        return _streamResult!.availableQualities.map((quality) {
                          final isSelected = quality == _streamResult!.quality;
                          return PopupMenuItem(
                            value: quality,
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                                  color: isSelected ? NivioTheme.netflixRed : Colors.white70,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  quality,
                                  style: TextStyle(
                                    color: isSelected ? NivioTheme.netflixRed : Colors.white,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList();
                      },
                    ),
                ],
              )
            : null,
        body: Stack(
          children: [
            Center(
              child: _isLoading
                  ? _buildLoadingState()
                  : _error != null
                      ? _buildErrorState()
                      : _streamResult != null &&
                              (_streamResult!.provider == 'vidsrc.cc' ||
                               _streamResult!.provider == 'vidsrc.to' ||
                               _streamResult!.provider == 'vidlink')
                          ? _buildWebViewPlayer()
                          : _chewieController != null &&
                                  _chewieController!.videoPlayerController.value.isInitialized
                              ? _buildVideoPlayer()
                              : _buildLoadingState(),
            ),
            
            // Netflix-style Next Episode button overlay (always on top, even in fullscreen)
            if (_showNextEpisodeButton && _hasNextEpisode())
              Positioned(
                right: 30,
                bottom: 100,
                child: SafeArea(
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8,
                    child: InkWell(
                      onTap: () {
                        _nextEpisodeTimer?.cancel();
                        _playNextEpisode();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.7),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Next Episode',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Icon(
                              Icons.skip_next_rounded,
                              color: Colors.black,
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: Colors.black,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 60,
            height: 60,
            child: CircularProgressIndicator(
              color: NivioTheme.netflixRed,
              strokeWidth: 4,
            ),
          ),
          const SizedBox(height: 32),
          Text(
            _currentProvider.isNotEmpty ? _currentProvider : _providerNames[_currentProviderIndex],
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Trying provider ${_currentProviderIndex + 1}/$_maxProviders...',
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white54,
            ),
          ),
          if (_retryCount > 0) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.orange, width: 1),
              ),
              child: Text(
                'Retry $_retryCount/$_maxRetries',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: NivioTheme.netflixRed.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.error_outline,
              color: NivioTheme.netflixRed,
              size: 64,
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Failed to Load Stream',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.white70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Switch Server button (if more providers available)
              if (_currentProviderIndex < _maxProviders - 1) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _isLoading = true;
                      _currentProviderIndex++;
                      _retryCount = 0;
                      _streamResult = null; // Clear old stream result
                    });
                    _initializePlayer();
                  },
                  icon: const Icon(Icons.swap_horiz, size: 20),
                  label: const Text('SWITCH SERVER'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                const SizedBox(width: 16),
              ],
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _retryCount = 0;
                    _currentProviderIndex = 0; // Reset to first provider
                    _streamResult = null; // Clear old stream result
                  });
                  _initializePlayer();
                },
                icon: const Icon(Icons.refresh, size: 20),
                label: const Text('RETRY'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NivioTheme.netflixRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('GO BACK'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white54, width: 1.5),
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildWebViewPlayer() {
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9, // Force 16:9 aspect ratio
        child: WebViewPlayer(
          key: ValueKey(_streamResult!.url), // Force rebuild when URL changes
          streamUrl: _streamResult!.url,
          title: ref.read(selectedMediaProvider)?.title ??
              ref.read(selectedMediaProvider)?.name ??
              'Video',
          onPlayerEvent: _handlePlayerEvent, // Handle VidSrc player events
        ),
      ),
    );
  }

  Widget _buildVideoPlayer() {
    return Center(
      child: AspectRatio(
        aspectRatio: 16 / 9, // Force 16:9 aspect ratio
        child: Chewie(controller: _chewieController!),
      ),
    );
  }
}
