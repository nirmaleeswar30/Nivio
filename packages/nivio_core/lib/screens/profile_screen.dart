import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:animations/animations.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/core/tmdb_artwork.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/screens/stream_selection_screen.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/settings_page_header.dart';
import 'package:nivio/widgets/changelog_dialog.dart';
import 'package:nivio/widgets/tab_artwork.dart';
import 'package:nivio/services/discord_gateway_service.dart';
import 'package:nivio/services/discord_rpc_service.dart';
import 'package:nivio/providers/changelog_provider.dart';
import 'package:nivio/providers/home_layout_provider.dart';
import 'package:nivio/services/download_service.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/services/desktop_self_updater.dart';
import 'package:nivio/services/api_status_service.dart';
import 'package:nivio/services/shorebird_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:nivio/widgets/anime_brand_logos.dart';
import 'package:nivio/models/anime_tracking_models.dart';
import 'package:nivio/providers/anime_tracking_provider.dart';
import 'package:nivio/providers/simkl_provider.dart';
import 'package:nivio/services/simkl_auth_service.dart';
import 'package:nivio/services/anime_tracking_coordinator.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.connectionsOnly = false});

  final bool connectionsOnly;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _query = '';
  int _selectedCategoryIndex = 0;
  int? _mobileCategory;
  static const _appearanceCategory = 10;
  double? _tempUiScale;
  bool _isSyncingAnime = false;
  // Shown under Settings → Downloads.
  Future<String>? _downloadLocation;

  static const List<String> _categories = [
    'Profile & Activity',
    'Playback',
    'Subtitle Appearance',
    'Downloads',
    'Network',
    'Content & Discovery',
    'Episode Alerts',
    'Tracking',
    'App & Updates',
    'Data & Account',
  ];

  /// Desktop sidebar order: indexes into [_categories], plus Appearance.
  static const List<int> _desktopCategoryOrder = [
    0,
    _appearanceCategory,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
  ];

  static String _categoryLabel(int index) =>
      index == _appearanceCategory ? 'Appearance' : _categories[index];

  void _handleBackNavigation() {
    if (_mobileCategory != null) {
      setState(() => _mobileCategory = null);
      return;
    }
    if (_isSearching) {
      FocusManager.instance.primaryFocus?.unfocus();
      _clearSearch();
      return;
    }
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  bool get _isSearching =>
      _searchController.text.isNotEmpty || _searchFocusNode.hasFocus;

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Whether every word of the search query appears in [title] or
  /// [subtitle], in any order and as part of a word ("sub font" finds
  /// "subtitle font").
  bool _matches(String title, [String subtitle = '']) {
    if (_query.isEmpty) return true;
    final source = '$title $subtitle'.toLowerCase();
    return _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .every(source.contains);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.connectionsOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
            _buildDiscordDesktopTile(),
          if (Platform.isAndroid || Platform.isIOS) _buildDiscordMobileTile(),
          const SizedBox(height: 8),
          _buildTrackingAccounts(),
        ],
      );
    }
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      loading: () => Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        body: Center(
          child: CircularProgressIndicator(
            color: NivioTheme.accentColorOf(context),
          ),
        ),
      ),
      error: (error, stackTrace) => _buildLoggedOutView(context),
      data: (user) {
        if (user == null) return _buildLoggedOutView(context);
        return _buildProfileWithSettings(context, user);
      },
    );
  }

  Widget _buildLoggedOutView(BuildContext context) {
    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Please sign in to use profile and settings.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 20),
              TextButton(onPressed: () => showStreamPickerSettings(context), child: const Text('Stream selection settings')),
              ElevatedButton(
                onPressed: () => context.go('/auth'),
                child: const Text('Sign In'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  
  Widget _buildProfileWithSettings(BuildContext context, User user) {
    final isDesktop = AppPlatform.isTv ||
        (AppPlatform.isDesktopOS && MediaQuery.sizeOf(context).width > 800);
    return ListenableBuilder(
      listenable: _searchFocusNode,
      builder: (context, child) {
        final hasLocalBackAction = _mobileCategory != null || _isSearching;
        return PopScope(
          canPop: !hasLocalBackAction,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && (_mobileCategory != null || _isSearching)) {
              _handleBackNavigation();
            }
          },
          child: child!,
        );
      },
      child: isDesktop
          ? _buildDesktopLayout(context, user)
          : _buildMobileLayout(context, user),
    );
  }

  Widget _buildMobileLayout(BuildContext context, User user) {
    final category = _mobileCategory;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: SettingsPageHeader(
        category == null
            ? 'Settings'
            : _categoryLabel(category),
        onBack: _handleBackNavigation,
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: category != null,
              child: TickerMode(
                enabled: category == null,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: [
                    _buildProfileHeader(user),
                    _buildSearchField(),
                    const SizedBox(height: 14),
                    if (_query.isNotEmpty)
                      _buildSearchResultsCard(
                        user: user,
                        languagePrefs: ref.watch(languagePreferencesProvider),
                        videoQuality: ref.watch(videoQualityProvider),
                        preferredAudio: ref.watch(preferredAudioLanguageProvider),
                        preferredSubtitle: ref.watch(
                          preferredSubtitleLanguageProvider,
                        ),
                        episodeCheckEnabled: ref.watch(episodeCheckEnabledProvider),
                        videoDebanding: ref.watch(videoDebandingProvider),
                        appThemeKey: ref.watch(appThemeProvider),
                        uiScale: ref.watch(uiScaleProvider),
                      )
                    else ...[
                      _mobileSettingsGroup(theme, 'You', const [
                        (Icons.person_outline_rounded, 'Profile & activity', 0),
                        (Icons.manage_accounts_outlined, 'Data & account', 9),
                      ]),
                      _mobileSettingsGroup(theme, 'Look', const [
                        (Icons.palette_outlined, 'Appearance', _appearanceCategory),
                      ]),
                      _mobileSettingsGroup(theme, 'Watch', const [
                        (Icons.dashboard_outlined, 'Content & Discovery', 5),
                        (Icons.play_circle_outline, 'Playback', 1),
                        (Icons.subtitles_outlined, 'Subtitle appearance', 2),
                        (Icons.download_outlined, 'Downloads', 3),
                      ]),
                      _mobileSettingsGroup(theme, 'Services', const [
                        (Icons.hub_outlined, 'Tracking', 7),
                        (Icons.language_rounded, 'Network', 4),
                      ]),
                      _mobileSettingsGroup(theme, 'System', const [
                        (Icons.notifications_none, 'Episode alerts', 6),
                        (Icons.info_outline, 'App & updates', 8),
                      ]),
                    ],
                  ],
                ),
              ),
            ),
            if (category != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _buildCategoryContent(user, category, mobile: true),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mobileSettingsGroup(
    ThemeData theme,
    String title,
    List<(IconData, String, int)> rows,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 7),
            child: Text(title, style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            )),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (index, row) in rows.indexed) ...[
                  if (index > 0) Divider(
                    height: 1,
                    thickness: 1,
                    indent: 52,
                    color: theme.dividerColor,
                  ),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    minLeadingWidth: 24,
                    leading: Icon(row.$1, size: 22, color: theme.colorScheme.onSurfaceVariant),
                    title: Text(row.$2, style: theme.textTheme.titleMedium),
                    trailing: Icon(Icons.chevron_right_rounded, size: 19,
                      color: theme.colorScheme.onSurfaceVariant),
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      setState(() => _mobileCategory = row.$3);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dynamicColorsTile() => _buildSwitchTile(
    icon: Icons.color_lens_outlined,
    title: 'Dynamic colors',
    subtitle: 'Use colors from artwork. Turn off for AMOLED Black.',
    value: ref.watch(dynamicArtworkColorsProvider),
    onChanged: ref.read(dynamicArtworkColorsProvider.notifier).setEnabled,
  );

  Widget _watchPartyFollowHostTile() => _buildSwitchTile(
    icon: Icons.groups_rounded,
    title: "Watch Party: play host's source",
    subtitle: 'When you join a party, play the stream the host picked. '
        'Turn off to choose your own.',
    value: ref.watch(watchPartyFollowHostSourceProvider),
    onChanged: ref.read(watchPartyFollowHostSourceProvider.notifier).setEnabled,
  );

  Widget _buildProfileHeader(User user) {
    final avatarUrl = user.photoURL;
    final avatar = avatarUrl != null && avatarUrl.isNotEmpty
        ? avatarArtworkImage(context, avatarUrl, 92)
        : null;
    final name = user.displayName?.trim().isNotEmpty == true
        ? user.displayName!.trim()
        : 'Nivio User';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: NivioTheme.netflixDarkGrey,
            backgroundImage: avatar,
            child: avatar == null
                ? const PhosphorIcon(
                    PhosphorIconsRegular.userCircle,
                    color: NivioTheme.netflixWhite,
                    size: 40,
                  )
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(
              color: NivioTheme.netflixWhite,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Consumer(
            builder: (context, ref, _) {
              final apiStatus = ref.watch(apiStatusProvider);
              
              final isApiDown = apiStatus.anilistStatus == ApiServiceStatus.offline || apiStatus.newTvStatus == ApiServiceStatus.offline;
              
              Color dotColor = Colors.greenAccent;
              String statusText = 'Services Online';
              
              if (isApiDown) {
                dotColor = Colors.redAccent;
                if (apiStatus.anilistStatus == ApiServiceStatus.offline && apiStatus.newTvStatus == ApiServiceStatus.offline) {
                  statusText = 'AniList & NetMirror Offline';
                } else if (apiStatus.anilistStatus == ApiServiceStatus.offline) {
                  statusText = 'AniList Offline';
                } else {
                  statusText = 'NetMirror Offline';
                }
              }

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _BlinkingDot(color: dotColor),
                  const SizedBox(width: 8),
                  Text(
                    statusText,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TvTextFieldGate(
      builder: (context, focusNode) => TextField(
        focusNode: focusNode ?? _searchFocusNode,
        controller: _searchController,
        onChanged: (value) => setState(() => _query = value.trim()),
        style: const TextStyle(color: NivioTheme.netflixWhite, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search profile settings...',
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.75),
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  onPressed: _clearSearch,
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.75),
                  ),
                ),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.05),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsPlaceholder() {
    return Row(
      children: [
        Expanded(child: _statCard('Watchlist', '--')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Watched', '--')),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Completed', '--')),
      ],
    );
  }

  Widget _buildStatsRow({
    required int watchlistCount,
    required int historyCount,
    required int completedCount,
  }) {
    return Row(
      children: [
        Expanded(child: _statCard('Watchlist', watchlistCount.toString())),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Watched', historyCount.toString())),
        const SizedBox(width: 10),
        Expanded(child: _statCard('Completed', completedCount.toString())),
      ],
    );
  }

  Widget _statCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 11),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: NivioTheme.netflixWhite,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
        ],
      ),
    );
  }

  void _showAnimeAudioDialog() {
    final prefs = ref.read(languagePreferencesProvider);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context, fallback: const Color(0xFF1F1F1F)),
          title: const Text(
            'Preferred Anime Audio',
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile<String>(
                title: const Text('Subbed (Japanese Audio)', style: TextStyle(color: Colors.white)),
                value: 'sub',
                groupValue: prefs.animePreferredAudio,
                activeColor: NivioTheme.accentColorOf(context),
                onChanged: (val) {
                  ref.read(languagePreferencesProvider.notifier).setAnimePreferredAudio(val!);
                  Navigator.pop(context);
                },
              ),
              RadioListTile<String>(
                title: const Text('Dubbed (English Audio)', style: TextStyle(color: Colors.white)),
                value: 'dub',
                groupValue: prefs.animePreferredAudio,
                activeColor: NivioTheme.accentColorOf(context),
                onChanged: (val) {
                  ref.read(languagePreferencesProvider.notifier).setAnimePreferredAudio(val!);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({required String title, required Widget child, bool initiallyExpanded = false}) {
    // We ignore initiallyExpanded now since we removed the collapsible feature
    if (_query.isNotEmpty && !initiallyExpanded) {
      // If we're searching and this section isn't matching the query (initiallyExpanded would be true if it matched)
      // Actually the parent already filters this out using _matches(), so we're good.
    }
    
    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ),
          Material(
            color: Colors.white.withValues(alpha: 0.04),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: child,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsCard({
    required User user,
    required LanguagePreferences languagePrefs,
    required String videoQuality,
    required String preferredAudio,
    required String preferredSubtitle,
    required bool episodeCheckEnabled,
    required bool videoDebanding,
    required String appThemeKey,
    required double uiScale,
  }) {
    final results = <Widget>[];

    if (_matches('auto play next episode automatically')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.skip_next_rounded,
          title: 'Auto Play Next Episode',
          subtitle: 'Automatically start the next episode when current finishes',
          value: ref.watch(autoPlayNextEpisodeProvider),
          onChanged: (value) {
            ref.read(autoPlayNextEpisodeProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('content warnings parental guide playback')) {
      results.add(_contentWarningsTile());
    }
    if (_matches('picture in picture pip lost visibility background on')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'PiP on Lost Visibility',
          subtitle: 'Switch to Picture-in-Picture when leaving the app',
          value: ref.watch(pipOnLostVisibilityProvider),
          onChanged: (value) {
            ref.read(pipOnLostVisibilityProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('pause on lost visibility background focus')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.pause_circle_outline_rounded,
          title: 'Pause on Lost Visibility',
          subtitle: 'Pause playback when app loses focus or goes to background',
          value: ref.watch(pauseOnLostVisibilityProvider),
          onChanged: (value) {
            ref.read(pauseOnLostVisibilityProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_showAmbientSetting && _matches(_ambientSearchTerms)) {
      results.addAll(_buildAmbientModeTiles());
    }
    if (_showHdrSettings && _matches(_hdrSearchTerms)) {
      results.addAll(_buildHdrSettingTiles());
    }
    if (AppPlatform.supportsDolbyPassthrough &&
        _matches(_dolbyPassthroughSearchTerms)) {
      results.add(_buildDolbyPassthroughTile());
    }
    if (_matches('seek duration skip jump forward rewind step')) {
      results.add(
        _buildActionTile(
          icon: Icons.fast_forward_rounded,
          title: 'Seek Duration',
          subtitle: '${ref.watch(seekDurationProvider)}s',
          onTap: _showSeekDurationDialog,
        ),
      );
    }
    if (_matches('auto skip intro outro opening ending theme')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.fast_forward_rounded,
          title: 'Auto Skip Intro & Outro',
          subtitle: 'Automatically skip opening and ending themes',
          value: ref.watch(autoSkipIntroOutroProvider),
          onChanged: (value) {
            ref.read(autoSkipIntroOutroProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('auto skip filler anime episode')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.auto_stories_rounded,
          title: 'Auto Skip Filler',
          subtitle: 'Automatically skip filler episodes during auto-play',
          value: ref.watch(autoSkipFillerProvider),
          onChanged: (value) {
            ref.read(autoSkipFillerProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('video quality resolution preferred')) {
      results.add(
        _buildActionTile(
          icon: Icons.high_quality_rounded,
          title: 'Preferred Video Quality',
          subtitle: _qualityLabel(videoQuality),
          onTap: _showVideoQualityDialog,
        ),
      );
    }
    if (_matches('preferred default audio language')) {
      results.add(
        _buildActionTile(
          icon: Icons.audiotrack_rounded,
          title: 'Preferred Audio Language',
          subtitle: preferredAudio,
          onTap: _showAudioLanguageDialog,
        ),
      );
    }
    if (_matches('preferred default subtitle language')) {
      results.add(
        _buildActionTile(
          icon: Icons.subtitles_rounded,
          title: 'Preferred Subtitle Language',
          subtitle: preferredSubtitle,
          onTap: _showSubtitleLanguageDialog,
        ),
      );
    }
    if (_matches('video deband filter quality debanding')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.blur_linear_rounded,
          title: 'Video Debanding',
          subtitle: 'Reduces color banding (uses more battery)',
          value: videoDebanding,
          onChanged: (value) {
            ref.read(videoDebandingProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('customize home layout order arrange shelves')) {
      results.add(
        _buildActionTile(
          icon: Icons.dashboard_customize_rounded,
          title: 'Customize Home Layout',
          subtitle: 'Rearrange the order of shelves on the home screen',
          onTap: () => _showHomeLayoutDialog(context),
        ),
      );
    }
    if (_matches('torrent torrents sources p2p enable streaming playback autoplay auto play indexers nyaa torrentio piratebay pirate bay persist files cache')) {
      results.add(const TorrentSourceSettingsLink());
    }
    if (_matches('anime language audio sub dub subbed dubbed preferred')) {
      results.add(
        _buildActionTile(
          icon: Icons.record_voice_over_rounded,
          title: 'Preferred Anime Audio',
          subtitle: languagePrefs.animePreferredAudio == 'sub' ? 'Subbed' : 'Dubbed',
          onTap: _showAnimeAudioDialog,
        ),
      );
      results.add(
        _buildSwitchTile(
          icon: Icons.animation_rounded,
          title: 'Anime',
          subtitle: 'Show anime rows on home',
          value: languagePrefs.showAnime,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleAnime(value);
          },
        ),
      );
    }
    if (_matches('watch party host source stream follow participant')) {
      results.add(_watchPartyFollowHostTile());
    }
    if (_matches('download concurrency parallel connections')) {
      results.add(
        _buildActionTile(
          icon: Icons.speed_rounded,
          title: 'Parallel Download Connections',
          subtitle: '${ref.watch(downloadConcurrencyProvider)}',
          onTap: _showDownloadConcurrencyDialog,
        ),
      );
    }
    if (_matches('use dns over https doh isp blocks domains bypass network')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.vpn_lock_rounded,
          title: 'Use DNS over HTTPS',
          subtitle:
              'This enables DNS over HTTPS, useful if your ISP blocks certain domains.',
          value: ref.watch(useDnsOverHttpsProvider),
          onChanged: (value) {
            ref.read(useDnsOverHttpsProvider.notifier).setEnabled(value);
          },
        ),
      );
    }
    if (_matches('dns over https doh url server query provider cloudflare network')) {
      results.add(
        _buildActionTile(
          icon: Icons.dns_rounded,
          title: 'DNS over HTTPS URL',
          subtitle: ref.watch(dnsOverHttpsUrlProvider),
          onTap: _showDnsUrlDialog,
        ),
      );
    }
    if (_matches('tamil language')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.movie_filter_rounded,
          title: 'Tamil',
          subtitle: 'Show Tamil rows on home',
          value: languagePrefs.showTamil,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleTamil(value);
          },
        ),
      );
    }
    if (_matches('telugu language')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.movie_creation_outlined,
          title: 'Telugu',
          subtitle: 'Show Telugu rows on home',
          value: languagePrefs.showTelugu,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleTelugu(value);
          },
        ),
      );
    }
    if (_matches('hindi language')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.theaters_rounded,
          title: 'Hindi',
          subtitle: 'Show Hindi rows on home',
          value: languagePrefs.showHindi,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleHindi(value);
          },
        ),
      );
    }
    if (_matches('korean language kdrama')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.live_tv_rounded,
          title: 'Korean',
          subtitle: 'Show Korean rows on home',
          value: languagePrefs.showKorean,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleKorean(value);
          },
        ),
      );
    }
    if (_matches('malayalam language')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.movie_outlined,
          title: 'Malayalam',
          subtitle: 'Show Malayalam rows on home',
          value: languagePrefs.showMalayalam,
          onChanged: (value) {
            ref.read(languagePreferencesProvider.notifier).toggleMalayalam(value);
          },
        ),
      );
    }
    if (_matches('alerts notifications new episode')) {
      results.add(
        _buildSwitchTile(
          icon: Icons.notifications_active_outlined,
          title: 'New Episode Alerts',
          subtitle: episodeCheckEnabled ? 'Enabled' : 'Disabled',
          value: episodeCheckEnabled,
          onChanged: (value) {
            ref.read(episodeCheckEnabledProvider.notifier).setEnabled(value);
          },
        ),
      );
    }

    if (_matches('check now refresh')) {
      results.add(
        _buildActionTile(
          icon: Icons.sync_rounded,
          title: 'Check Now',
          subtitle: 'Manually check for newly aired episodes',
          onTap: _checkNow,
        ),
      );
    }
    if (_matches('new episodes inbox open')) {
      results.add(
        _buildActionTile(
          icon: Icons.notifications_none_rounded,
          title: 'Open New Episodes',
          subtitle: 'View recently detected episodes',
          onTap: () => context.go('/library'),
        ),
      );
    }
    if (_matches('app theme color scheme dark blackout monokai catppuccin dracula amber lavender system')) {
      results.add(
        _buildActionTile(
          icon: Icons.palette_outlined,
          title: 'App Theme',
          subtitle: NivioTheme.getTheme(appThemeKey).label,
          onTap: _showThemeDialog,
        ),
      );
    }
    if (_matches('ui scale zoom display interface size')) {
      results.add(_buildUiScaleTile(uiScale));
    }
    if (_showLiquidGlassSetting && _matches(_liquidGlassSearchTerms)) {
      results.add(_buildLiquidGlassNavTile());
    }
    if ((Platform.isWindows || Platform.isLinux || Platform.isMacOS) &&
        _matches('discord rich presence rpc activity status')) {
      results.add(_buildDiscordDesktopTile());
    }
    if ((Platform.isAndroid || Platform.isIOS) &&
        _matches('discord rich presence rpc activity status')) {
      results.add(_buildDiscordMobileTile());
    }
    if (_matches('anime tracking anilist mal myanimelist simkl movies tv shows sync watchlist')) {
      results.add(_buildAnimeTrackingContent());
    }
    if (_matches('dynamic colors artwork amoled black')) results.add(_dynamicColorsTile());

    if (_matches('update app version release github')) {
      results.add(
        FutureBuilder<String>(
          future: _getAppVersionLabel(),
          builder: (context, snapshot) {
            return _buildActionTile(
              icon: Icons.info_outline_rounded,
              title: 'App Version',
              subtitle: snapshot.data ?? 'Loading...',
              onTap: _showAppVersionDialog,
            );
          },
        ),
      );
    }
    if (_matches('update github release app install apk')) {
      results.add(
        FutureBuilder<GitHubReleaseUpdateResult>(
          future: GitHubReleaseUpdateService.checkForUpdate(),
          builder: (context, snapshot) {
            final result = snapshot.data;
            final subtitle = result == null
                ? 'Checking GitHub releases...'
                : result.hasUpdate
                ? 'Latest ${result.latestVersion} available'
                : result.message;
            return _buildActionTile(
              icon: Icons.download_for_offline_outlined,
              title: 'Check GitHub Release',
              subtitle: subtitle,
              onTap: _checkForGitHubRelease,
            );
          },
        ),
      );
    }
    if (_matches('clear history data watch')) {
      results.add(
        _buildActionTile(
          icon: Icons.delete_sweep_outlined,
          title: 'Clear Watch History',
          subtitle: 'Remove all watch progress and activity',
          onTap: _showClearHistoryDialog,
        ),
      );
    }
    if (_matches('clear cache data storage')) {
      results.add(
        _buildActionTile(
          icon: Icons.cleaning_services_outlined,
          title: 'Clear Cache',
          subtitle: 'Clear cached API and image metadata',
          onTap: _showClearCacheDialog,
        ),
      );
    }
    if (_matches('sign out logout')) {
      results.add(
        _buildActionTile(
          icon: Icons.logout_rounded,
          title: user.isAnonymous ? 'Exit Guest Mode' : 'Sign Out',
          subtitle: user.email ?? 'Current session',
          titleColor: NivioTheme.accentColorOf(context),
          onTap: _showSignOutDialog,
        ),
      );
    }

    if (_matches('subtitle subtitles font family typeface custom appearance')) {
      final family = ref.watch(subtitleFontFamilyProvider);
      final customName = ref.watch(customSubtitleFontNameProvider);
      results.add(
        _buildActionTile(
          icon: Icons.font_download_rounded,
          title: 'Subtitle Font',
          subtitle: family == 'Custom' && customName != null ? 'Custom ($customName)' : family,
          onTap: _showSubtitleFontDialog,
        ),
      );
    }
    if (_matches('subtitle subtitles font size text bigger smaller appearance')) {
      results.add(
        _buildActionTile(
          icon: Icons.format_size_rounded,
          title: 'Subtitle Font Size',
          subtitle: subtitleFontSizeLabel(ref.watch(subtitleFontSizeProvider)),
          onTap: _showSubtitleFontSizeDialog,
        ),
      );
    }
    if (_matches('subtitle subtitles background box shadow opacity appearance')) {
      results.add(
        _buildActionTile(
          icon: Icons.picture_in_picture_alt_rounded,
          title: 'Subtitle Background',
          subtitle: ref.watch(subtitleBackgroundProvider),
          onTap: _showSubtitleBackgroundDialog,
        ),
      );
    }
    if (_matches('subtitle subtitles text style outline border drop shadow appearance')) {
      results.add(
        _buildActionTile(
          icon: Icons.text_fields_rounded,
          title: 'Subtitle Text Style',
          subtitle: ref.watch(subtitleOutlineProvider),
          onTap: _showSubtitleOutlineDialog,
        ),
      );
    }
    for (final entry in _streamSelectionSearchEntries) {
      if (_matches(entry.keywords, entry.title)) {
        results.add(
          _buildActionTile(
            icon: entry.icon,
            title: entry.title,
            subtitle: entry.subtitle,
            onTap: () => showStreamPickerSettings(context),
          ),
        );
      }
    }
    if (_matches("what's new whats new changelog changes release notes version")) {
      results.add(
        _buildActionTile(
          icon: Icons.new_releases_outlined,
          title: "What's New",
          subtitle: 'See the changes in this version',
          onTap: () => _showChangelog(context, ref),
        ),
      );
    }
    if (_matches('sponsor nivio support donate github')) {
      results.add(
        _buildActionTile(
          icon: Icons.favorite_rounded,
          title: 'Sponsor Nivio',
          subtitle: 'Support the development on GitHub',
          titleColor: Colors.pinkAccent,
          onTap: () {
            final sponsorUrl = dotenv.env['GITHUB_SPONSOR_URL'] ??
                'https://github.com/sponsors/nirmaleeswar30';
            launchUrl(Uri.parse(sponsorUrl), mode: LaunchMode.externalApplication);
          },
        ),
      );
    }

    if (results.isEmpty) {
      results.add(
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 10, 4, 12),
          child: Text(
            'No matching settings found.',
            style: TextStyle(color: NivioTheme.netflixGrey),
          ),
        ),
      );
    }

    return _buildSectionCard(
      title: 'Search Results',
      child: Column(children: results),
    );
  }

  Widget _contentWarningsTile() => _buildSwitchTile(
    icon: Icons.info_outline_rounded,
    title: 'Content Warnings',
    subtitle: 'Show parental guidance when playback starts',
    value: ref.watch(parentalGuideEnabledProvider),
    onChanged: ref.read(parentalGuideEnabledProvider.notifier).setEnabled,
  );

  /// Settings that live in the Stream Selection screen, listed so settings
  /// search finds them; each result opens that screen.
  static const _streamSelectionSearchEntries = <({
    String title,
    String subtitle,
    String keywords,
    IconData icon,
  })>[
    (
      title: 'Stream Selection',
      subtitle: 'Autoplay, quality presets, and source priority',
      keywords: 'stream selection picker autoplay auto play fastest first manual mode choose stream sources',
      icon: Icons.filter_list,
    ),
    (
      title: 'Quality Preset',
      subtitle: 'Stream Selection · Data Saver, Balanced and more',
      keywords: 'quality preset data saver balanced best 4k 1080p 720p hevc mobile data',
      icon: Icons.high_quality_rounded,
    ),
    (
      title: 'Resolution Priority',
      subtitle: 'Stream Selection · Customise',
      keywords: 'resolution priority order quality 2160p 4k 1080p 720p 480p',
      icon: Icons.sort_rounded,
    ),
    (
      title: 'Block Releases',
      subtitle: 'Stream Selection · Customise',
      keywords: 'block releases exclude hide filter cam ts telesync hdcam screener',
      icon: Icons.block_rounded,
    ),
    (
      title: 'Prefer These Formats',
      subtitle: 'Stream Selection · Customise',
      keywords: 'prefer these formats hevc x265 h265 av1 hdr dolby vision remux bluray web dl atmos',
      icon: Icons.star_outline_rounded,
    ),
    (
      title: 'Maximum File Size',
      subtitle: 'Stream Selection · Customise',
      keywords: 'maximum max file size limit gb big large data',
      icon: Icons.data_usage_rounded,
    ),
    (
      title: 'Match Saved Audio Preference',
      subtitle: 'Stream Selection · Autoplay',
      keywords: 'match saved audio preference language dub sub autoplay',
      icon: Icons.record_voice_over_rounded,
    ),
    (
      title: 'Reuse Binge Group',
      subtitle: 'Stream Selection · Autoplay',
      keywords: 'reuse binge group same release next episode autoplay',
      icon: Icons.playlist_play_rounded,
    ),
    (
      title: 'Stream Selection Timeout',
      subtitle: 'Stream Selection · how long Autoplay waits for sources',
      keywords: 'stream selection timeout wait seconds autoplay search time',
      icon: Icons.timer_outlined,
    ),
    (
      title: 'Group Results by Source',
      subtitle: 'Stream Selection · provider sections in All',
      keywords: 'group results by source provider sections list',
      icon: Icons.view_agenda_outlined,
    ),
    (
      title: 'Custom Regex Override',
      subtitle: 'Stream Selection · Advanced',
      keywords: 'custom regex override advanced pattern filter',
      icon: Icons.code_rounded,
    ),
    (
      title: 'Source Priority',
      subtitle: 'Stream Selection · reorder movie and TV sources',
      keywords: 'source priority order reorder providers movie tv servers',
      icon: Icons.reorder_rounded,
    ),
    (
      title: 'Anime Source Priority',
      subtitle: 'Stream Selection · reorder anime sources',
      keywords: 'anime source priority order reorder providers servers',
      icon: Icons.reorder_rounded,
    ),
  ];

  Widget _streamSelectionTile() => _buildActionTile(
    icon: Icons.filter_list,
    title: 'Stream Selection',
    subtitle: 'Autoplay, quality presets, and source priority',
    onTap: () => showStreamPickerSettings(context),
  );

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return _SettingActionTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      titleColor: titleColor,
    );
  }

  // The floating bottom nav only exists on phones (MainShellScreen).
  bool get _showLiquidGlassSetting => (Platform.isAndroid || Platform.isIOS) && !AppPlatform.isTv;

  static const _liquidGlassSearchTerms = 'liquid glass navigation bar bottom nav tab bar blur';

  Widget _buildLiquidGlassNavTile() {
    return _buildSwitchTile(
      icon: Icons.water_drop_outlined,
      title: 'Liquid Glass Navigation',
      subtitle: 'Glass bottom bar with a lens that follows your tab',
      value: ref.watch(liquidGlassNavProvider),
      onChanged: (value) {
        ref.read(liquidGlassNavProvider.notifier).setEnabled(value);
      },
    );
  }

  // Ambient mode only exists on Android phones (see VideoAmbientBackground).
  bool get _showAmbientSetting => Platform.isAndroid && !AppPlatform.isTv;

  static const _ambientSearchTerms =
      'ambient mode glow black bars letterbox background blur fade edge style';

  /// Ambient mode switch, then its style and blur (the player's Ambient page
  /// has the same).
  List<Widget> _buildAmbientModeTiles() {
    final style = ref.watch(ambientStyleProvider);
    final blur = ref.watch(ambientBlurProvider);
    return [
      _buildSwitchTile(
        icon: Icons.blur_on_rounded,
        title: 'Ambient Mode',
        subtitle: 'Fill the black bars around the video with a soft glow',
        value: ref.watch(ambientModeProvider),
        onChanged: (value) {
          ref.read(ambientModeProvider.notifier).setEnabled(value);
        },
      ),
      _buildActionTile(
        icon: Icons.gradient_rounded,
        title: 'Ambient Style',
        subtitle: ambientStyleLabels[style] ?? style,
        onTap: () => _showOptionSheet(
          title: 'Ambient Style',
          options: ambientStyles,
          labels: ambientStyleLabels,
          descriptions: const {
            'fade': "The video's edges fade softly into the glow",
            'glow': 'Glow in the bars only, with sharp video edges',
          },
          current: style,
          onSelected: (value) => ref.read(ambientStyleProvider.notifier).setStyle(value),
        ),
      ),
      _buildAmbientBlurTile(blur),
    ];
  }

  /// Blur strength slider: 0 keeps the picture's shapes in the glow, 10 (the
  /// default, the original look) is the softest.
  Widget _buildAmbientBlurTile(int blur) {
    final accentColor = NivioTheme.accentColorOf(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.blur_linear_rounded, color: NivioTheme.netflixWhite, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Ambient Blur',
                        style: TextStyle(
                          color: NivioTheme.netflixWhite,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      blur == ambientBlurMax ? '$blur · default' : '$blur',
                      style: TextStyle(color: accentColor, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  "0 keeps the picture's shapes in the glow, 10 is the softest (the default)",
                  style: TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                    activeTrackColor: accentColor,
                    inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
                    thumbColor: accentColor,
                    overlayColor: accentColor.withValues(alpha: 0.15),
                  ),
                  child: Slider(
                    value: blur.toDouble(),
                    min: ambientBlurMin.toDouble(),
                    max: ambientBlurMax.toDouble(),
                    divisions: ambientBlurMax - ambientBlurMin,
                    onChanged: (value) {
                      final level = value.round();
                      if (level != blur) ref.read(ambientBlurProvider.notifier).setLevel(level);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _dolbyPassthroughSearchTerms =
      'dolby atmos audio passthrough bitstream digital plus eac3 truehd hdmi receiver';

  Widget _buildDolbyPassthroughTile() {
    final route = ref.watch(dolbyAudioRouteProvider);
    final supported = route.asData?.value != null;
    final codecs = switch (route.asData?.value?.codecs) {
      'eac3,truehd' => 'Dolby Digital Plus or TrueHD',
      'truehd' => 'Dolby TrueHD',
      _ => 'Dolby Digital Plus',
    };
    final value = ref.watch(dolbyPassthroughProvider);
    final subtitle = Platform.isIOS
        ? 'Use Apple’s audio renderer for Dolby Digital Plus Atmos on '
            'compatible audio routes at 1× speed. Applies when playback starts.'
        : Platform.isAndroid && !AppPlatform.isTv
        ? 'Use Android’s audio renderer for Dolby Digital Plus Atmos on '
            'compatible audio routes at 1× speed. Applies when playback starts.'
        : 'Send $codecs to a compatible HDMI receiver for Atmos at 1× speed. '
            'Use the receiver for volume. Applies when playback starts.';
    return _buildSwitchTile(
      icon: Icons.surround_sound_outlined,
      title: 'Dolby audio passthrough',
      subtitle: supported
          ? subtitle
          : route.isLoading
          ? 'Checking the current audio output…'
          : 'Dolby passthrough is unavailable on this audio output. Audio plays as PCM.',
      value: supported && value,
      enabled: supported,
      onChanged: (enabled) async {
        if (enabled && await AppPlatform.dolbyAudioRoute() == null) {
          if (mounted) ref.invalidate(dolbyAudioRouteProvider);
          return;
        }
        if (!mounted) return;
        await ref.read(dolbyPassthroughProvider.notifier).setEnabled(enabled);
      },
    );
  }

  // iOS shows the HDR Output switch because the system handles HDR presentation
  // and tone mapping. The other HDR settings below apply to Android.
  bool get _showHdrSettings => Platform.isAndroid || Platform.isIOS;

  static const _hdrSearchTerms =
      'hdr dolby vision dv tone mapping sdr hdr10 hlg bt2020 toys surface output mediacodec vulkan';

  static const _toneMappingLabels = {'standard': 'Standard', 'hdrToys': 'HDR Toys'};
  static const _toneMappingDescriptions = {
    'standard': "mpv's tone mapping with per-scene brightness detection",
    'hdrToys': 'hdr-toys shaders: PQ, HLG and BT.2020 profiles picked from the video. Ambient mode is off while they run',
  };
  static const _hdrBackendLabels = {
    'vulkan': 'Vulkan (gpu-next)',
    'mediacodecEmbed': 'MediaCodec Direct',
  };
  static const _hdrBackendDescriptions = {
    'vulkan': 'HDR10 through mpv\'s Vulkan renderer. Dolby Vision videos play their HDR10 base layer',
    'mediacodecEmbed': 'Straight from the hardware decoder to the screen. Needed for Dolby Vision, easiest on battery',
  };

  List<Widget> _buildHdrSettingTiles() {
    final toneMode = ref.watch(toneMappingProvider);
    final backend = ref.watch(hdrSurfaceBackendProvider);
    return [
      FutureBuilder<HdrDisplayInfo>(
        future: AppPlatform.hdrDisplay(),
        builder: (context, snapshot) {
          final hdrScreen = snapshot.data?.isHdr ?? false;
          return _buildSwitchTile(
            icon: Icons.hdr_on_rounded,
            title: 'HDR Output',
            subtitle: !snapshot.hasData || hdrScreen
                ? 'Show HDR and Dolby Vision videos in HDR on this screen'
                : "This screen doesn't support HDR, so HDR videos are tone mapped",
            value: ref.watch(hdrOutputProvider),
            enabled: hdrScreen,
            onChanged: (value) {
              ref.read(hdrOutputProvider.notifier).setEnabled(value);
            },
          );
        },
      ),
      if (Platform.isAndroid) ...[
      _buildActionTile(
        icon: Icons.tonality_rounded,
        title: 'Tone Mapping',
        subtitle: '${_toneMappingLabels[toneMode]} · used when HDR output is off or the screen has no HDR',
        onTap: () => _showOptionSheet(
          title: 'Tone Mapping (HDR on SDR)',
          options: toneMappingModes,
          labels: _toneMappingLabels,
          descriptions: _toneMappingDescriptions,
          current: toneMode,
          onSelected: (mode) => ref.read(toneMappingProvider.notifier).setMode(mode),
        ),
      ),
      _buildActionTile(
        icon: Icons.developer_board_rounded,
        title: 'HDR Surface Output',
        subtitle: '${_hdrBackendLabels[backend]} · how HDR video reaches the screen',
        onTap: () => _showOptionSheet(
          title: 'HDR Surface Output (Experimental)',
          options: hdrSurfaceBackends,
          labels: _hdrBackendLabels,
          descriptions: _hdrBackendDescriptions,
          current: backend,
          onSelected: (mode) => ref.read(hdrSurfaceBackendProvider.notifier).setBackend(mode),
        ),
      ),
      ],
    ];
  }

  Future<void> _showOptionSheet({
    required String title,
    required List<String> options,
    required Map<String, String> labels,
    required Map<String, String> descriptions,
    required String current,
    required ValueChanged<String> onSelected,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                title: Text(
                  title,
                  style: const TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...options.map((option) {
                final isSelected = option == current;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? NivioTheme.accentColorOf(context)
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    labels[option] ?? option,
                    style: const TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  subtitle: Text(
                    descriptions[option] ?? '',
                    style: const TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
                  ),
                  onTap: () {
                    onSelected(option);
                    Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return _SettingSwitchTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      value: value,
      onChanged: onChanged,
      enabled: enabled,
    );
  }

  /// Desktop Discord Rich Presence tile. Desktop has no sign-in: presence goes
  /// through the Discord app the user is already logged into, so the subtitle
  /// reports whether that app was found.
  Widget _buildDiscordDesktopTile() {
    return ValueListenableBuilder<bool>(
      valueListenable: DiscordRpcService.instance.connectedNotifier,
      builder: (context, connected, _) {
        final enabled = ref.watch(discordRpcEnabledProvider);
        return _buildSwitchTile(
          icon: PhosphorIconsRegular.discordLogo,
          title: 'Discord Rich Presence',
          subtitle: !enabled
              ? 'Shows what you watch on your Discord profile (uses the Discord app)'
              : connected
                  ? 'Showing your activity through the Discord app'
                  : 'Discord app not running — open Discord to show activity',
          value: enabled,
          onChanged: (value) =>
              ref.read(discordRpcEnabledProvider.notifier).setEnabled(value),
        );
      },
    );
  }

  /// Mobile Discord Rich Presence tile: connects through Discord OAuth2 (system
  /// browser sign-in) and reflects live connection status.
  Widget _buildDiscordMobileTile() {
    return ValueListenableBuilder<DiscordGatewayState>(
      valueListenable: DiscordGatewayService.instance.stateNotifier,
      builder: (context, dstate, _) {
        final enabled = ref.watch(discordRpcEnabledProvider);
        final authorized = DiscordGatewayService.instance.isAuthorized;
        String subtitle;
        if (!enabled) {
          // A failed sign-in leaves the toggle off; say why instead of looking unresponsive.
          subtitle = dstate.errorMessage ??
              (dstate.status == DiscordGatewayStatus.connecting
                  ? 'Signing in…'
                  : authorized
                      ? 'Disabled'
                      : 'Tap to sign in with Discord');
        } else if (dstate.status == DiscordGatewayStatus.connected) {
          subtitle = 'Connected as ${dstate.displayName}';
        } else if (dstate.status == DiscordGatewayStatus.connecting) {
          subtitle = 'Connecting…';
        } else {
          subtitle = dstate.errorMessage ?? 'Not connected';
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SettingSwitchTile(
              icon: PhosphorIconsRegular.discordLogo,
              title: 'Discord Rich Presence',
              subtitle: subtitle,
              value: enabled,
              onChanged: (val) async {
                if (val) {
                  if (DiscordGatewayService.instance.isAuthorized) {
                    ref.read(discordRpcEnabledProvider.notifier).setEnabled(true);
                  } else {
                    final ok = await DiscordGatewayService.instance.authorize();
                    if (ok) {
                      ref.read(discordRpcEnabledProvider.notifier).setEnabled(true);
                    }
                  }
                } else {
                  ref.read(discordRpcEnabledProvider.notifier).setEnabled(false);
                }
              },
            ),
            if (authorized)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 16, bottom: 6),
                  child: TextButton.icon(
                    onPressed: () async {
                      await DiscordGatewayService.instance.logout();
                      ref.read(discordRpcEnabledProvider.notifier).setEnabled(false);
                    },
                    icon: const Icon(Icons.logout_rounded,
                        size: 16, color: Colors.redAccent),
                    label: const Text('Sign out of Discord',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildDownloadLocationNote() {
    return FutureBuilder<String>(
      future: _downloadLocation ??= DownloadService.downloadDirectoryPath(),
      builder: (context, snapshot) {
        final path = snapshot.data;
        if (path == null) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 18,
                color: Colors.white.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 10),
              Expanded(
                // Selectable so the path can be copied.
                child: SelectableText(
                  'Downloads, including torrents, are saved to:\n$path',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWatchlistPreview(List<dynamic> watchlist) {
    if (watchlist.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(4, 10, 4, 12),
        child: Text(
          'No items in watchlist yet.',
          style: TextStyle(color: NivioTheme.netflixGrey),
        ),
      );
    }

    final preview = watchlist.take(8).toList();
    final posterPixels = (78 * MediaQuery.devicePixelRatioOf(context))
        .ceil()
        .clamp(1, 240);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 122,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
              clipBehavior: AppPlatform.isTv ? Clip.none : Clip.hardEdge,
            itemCount: preview.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = preview[index];
              final posterUrl = tmdbArtworkUrl(item.posterPath, 'w185');
              return FocusableTap(
                onTap: () =>
                    context.push('/media/${item.id}?type=${item.mediaType}'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: posterUrl == null
                      ? Container(
                          width: 78,
                          color: NivioTheme.netflixDarkGrey,
                          child: Icon(
                            Icons.movie_outlined,
                            color: NivioTheme.netflixGrey,
                          ),
                        )
                      : ArtworkImage(
                          imageUrl: posterUrl,
                          width: 78,
                          maxDecodeWidth: posterPixels,
                          fit: BoxFit.cover,
                        ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => context.go('/library?tab=watchlist'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: Icon(Icons.bookmark_rounded, size: 18),
          label: const Text('Open full watchlist'),
        ),
      ],
    );
  }

  Widget _buildRecentActivity(AsyncValue<List<dynamic>> historyAsync) {
    return historyAsync.when(
      loading: () => Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: CircularProgressIndicator(
            color: NivioTheme.accentColorOf(context),
            strokeWidth: 2,
          ),
        ),
      ),
      error: (error, stackTrace) => const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Unable to load activity.',
          style: TextStyle(color: NivioTheme.netflixGrey),
        ),
      ),
      data: (history) {
        if (history.isEmpty) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(4, 10, 4, 12),
            child: Text(
              'No activity yet.',
              style: TextStyle(color: NivioTheme.netflixGrey),
            ),
          );
        }

        final posterPixels = (42 * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 128);
        final sorted = [...history]
          ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
        final preview = sorted.take(4).toList();

        return Column(
          children: preview.map((entry) {
            final posterUrl = tmdbArtworkUrl(entry.posterPath, 'w92');
            final subtitle = [
              if (entry.mediaType == 'tv')
                'S${entry.currentSeason} E${entry.currentEpisode}',
              DateFormat.yMMMd().add_jm().format(entry.lastWatchedAt),
            ].join(' | ');

            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 42,
                  height: 58,
                  child: posterUrl != null
                      ? ArtworkImage(
                          imageUrl: posterUrl,
                          maxDecodeWidth: posterPixels,
                          fit: BoxFit.cover,
                        )
                      : Container(color: NivioTheme.netflixDarkGrey),
                ),
              ),
              title: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
              ),
              onTap: () => context.push(
                '/media/${entry.tmdbId}?type=${entry.mediaType}',
              ),
            );
          }).toList(),
        );
      },
    );
  }

  String _qualityLabel(String quality) {
    switch (quality) {
      case '2160p':
        return '4K (2160p)';
      case '1080p':
        return 'Full HD (1080p)';
      case '720p':
        return 'HD (720p)';
      case '480p':
        return 'SD (480p)';
      default:
        return 'Auto (Best Available)';
    }
  }

  void _showHomeLayoutDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NivioTheme.sheetColorOf(context),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, scrollController) => _HomeLayoutBottomSheet(scrollController: scrollController),
        );
      },
    );
  }

  Future<void> _showSeekDurationDialog() async {
    final currentDuration = ref.read(seekDurationProvider);
    final controller = TextEditingController(text: currentDuration.toString());

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Seek Duration',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter seek step in seconds (e.g. 5, 10, 15, 30)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  suffixText: 'sec',
                  suffixStyle: const TextStyle(color: Colors.white70),
                  hintText: '10',
                  hintStyle: const TextStyle(color: Colors.white38),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                final val = int.tryParse(text);
                if (val != null && val > 0 && val <= 300) {
                  ref.read(seekDurationProvider.notifier).setDuration(val);
                }
                Navigator.pop(dialogContext);
              },
              child: Text(
                'Save',
                style: TextStyle(
                  color: NivioTheme.accentColorOf(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDnsUrlDialog() async {
    final currentUrl = ref.read(dnsOverHttpsUrlProvider);
    final controller = TextEditingController(text: currentUrl);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'DNS over HTTPS URL',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This is what URL to use for querying DNS over HTTPS',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.url,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: DnsOverHttpsUrlNotifier.defaultDohUrl,
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                    enabledBorder: const UnderlineInputBorder(
                      borderSide: BorderSide(color: Colors.white24),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Presets',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _buildDohPresetChip(
                      label: 'Cloudflare',
                      url: 'https://cloudflare-dns.com/dns-query',
                      controller: controller,
                    ),
                    _buildDohPresetChip(
                      label: 'Google',
                      url: 'https://dns.google/dns-query',
                      controller: controller,
                    ),
                    _buildDohPresetChip(
                      label: 'AdGuard',
                      url: 'https://dns.adguard-dns.com/dns-query',
                      controller: controller,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                ref.read(dnsOverHttpsUrlProvider.notifier).resetToDefault();
                controller.text = DnsOverHttpsUrlNotifier.defaultDohUrl;
              },
              child: const Text('Reset', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) {
                  ref.read(dnsOverHttpsUrlProvider.notifier).setUrl(text);
                }
                Navigator.pop(dialogContext);
              },
              child: Text(
                'Save',
                style: TextStyle(
                  color: NivioTheme.accentColorOf(context),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDohPresetChip({
    required String label,
    required String url,
    required TextEditingController controller,
  }) {
    return ActionChip(
      label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)),
      backgroundColor: Colors.white.withOpacity(0.08),
      side: BorderSide(color: Colors.white.withOpacity(0.15)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      onPressed: () {
        controller.text = url;
      },
    );
  }

  Future<void> _showVideoQualityDialog() async {
    const options = ['auto', '2160p', '1080p', '720p', '480p'];
    final current = ref.read(videoQualityProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Video Quality',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...options.map((option) {
                final isSelected = option == current;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? NivioTheme.accentColorOf(context)
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    _qualityLabel(option),
                    style: TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  onTap: () {
                    ref.read(videoQualityProvider.notifier).setQuality(option);
                    Navigator.pop(sheetContext);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }



  Future<void> _showThemeDialog() async {
    final isDesktop = AppPlatform.useDesktopLayout;

    if (isDesktop) {
      await _showThemeDesktopDialog();
    } else {
      await _showThemeMobileSheet();
    }
  }

  Future<void> _showThemeDesktopDialog() async {
    final current = ref.read(appThemeProvider);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final screenSize = MediaQuery.sizeOf(dialogContext);
        final double dialogWidth = min(740.0, screenSize.width - 48);
        final double dialogHeight = min(580.0, screenSize.height - 48);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            decoration: BoxDecoration(
              color: NivioTheme.surfaceColorOf(dialogContext),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: Colors.white.withOpacity(0.09),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.55),
                  blurRadius: 36,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 16, 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: NivioTheme.accentColorOf(dialogContext).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.palette_rounded,
                          color: NivioTheme.accentColorOf(dialogContext),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'App Theme',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const Text(
                              'Select a complete color scheme for the interface',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        splashRadius: 20,
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: Colors.white10),
                Expanded(
                  child: AppSingleChildScrollView(
                    padding: const EdgeInsets.all(22),
                    child: _buildDesktopThemesLayout(dialogContext, current),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDesktopThemesLayout(BuildContext dialogContext, String currentThemeKey) {
    final themes = NivioTheme.availableThemes;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final int columns;
        if (availableWidth >= 600) {
          columns = 4;
        } else if (availableWidth >= 440) {
          columns = 3;
        } else {
          columns = 2;
        }

        const double spacing = 14.0;
        final double cardWidth = (availableWidth - ((columns - 1) * spacing)) / columns;
        final double cardHeight = cardWidth;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          alignment: WrapAlignment.center,
          children: themes.map((theme) {
            final isSelected = theme.key == currentThemeKey;
            return SizedBox(
              width: cardWidth,
              height: cardHeight,
              child: _DesktopThemeCard(
                theme: theme,
                isSelected: isSelected,
                onTap: () async {
                  await ref.read(appThemeProvider.notifier).setTheme(theme.key);
                  if (dialogContext.mounted) Navigator.pop(dialogContext);
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _showThemeMobileSheet() async {
    final current = ref.read(appThemeProvider);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          initialChildSize: 0.82,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          snap: true,
          snapSizes: const [0.82],
          shouldCloseOnMinExtent: true,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: NivioTheme.surfaceColorOf(context),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withOpacity(0.12),
                    width: 1,
                  ),
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: CustomScrollView(
                controller: scrollController,
                physics: const ClampingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Drag Handle
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            margin: const EdgeInsets.only(top: 12, bottom: 10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                        // Title & Close Button
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'App Theme',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                splashRadius: 20,
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white70,
                                  size: 22,
                                ),
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.fromLTRB(20, 2, 20, 14),
                          child: Text(
                            'Select a complete color scheme for the interface',
                            style: TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                        ),
                        const Divider(height: 1, color: Colors.white10),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.0,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          final theme = NivioTheme.availableThemes[index];
                          final isSelected = theme.key == current;
                          return _DesktopThemeCard(
                            theme: theme,
                            isSelected: isSelected,
                            onTap: () async {
                              await ref
                                  .read(appThemeProvider.notifier)
                                  .setTheme(theme.key);
                              if (sheetContext.mounted) {
                                Navigator.pop(sheetContext);
                              }
                            },
                          );
                        },
                        childCount: NivioTheme.availableThemes.length,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildScaleBadge({
    required bool isDefault,
    required int percent,
    required Color accentColor,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 46),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: isDefault
            ? Colors.white.withOpacity(0.06)
            : accentColor.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDefault
              ? Colors.white.withOpacity(0.12)
              : accentColor.withOpacity(0.5),
          width: 1,
        ),
      ),
      child: Center(
        child: Text(
          '$percent%',
          style: TextStyle(
            color: isDefault ? Colors.white70 : accentColor,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildScaleResetButton({
    required bool isDefault,
    required Color accentColor,
    bool compact = false,
  }) {
    if (isDefault) return const SizedBox.shrink();

    return Tooltip(
      message: 'Reset to default (100%)',
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() {
            _tempUiScale = null;
          });
          ref
              .read(uiScaleConfirmationProvider.notifier)
              .requestScaleChange(1.0);
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 7 : 9,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: accentColor.withOpacity(0.14),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accentColor.withOpacity(0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.restart_alt_rounded,
                size: 14,
                color: accentColor,
              ),
              const SizedBox(width: 4),
              Text(
                'Reset',
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScaleMinusButton(double effectiveScale) {
    return IconButton(
      tooltip: 'Zoom out (-5%)',
      splashRadius: 14,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.remove_rounded, size: 16, color: Colors.white70),
      onPressed: effectiveScale <= UiScaleNotifier.minScale + 0.01
          ? null
          : () {
              final next = ((effectiveScale - 0.05) * 100).round() / 100;
              ref
                  .read(uiScaleConfirmationProvider.notifier)
                  .requestScaleChange(next.clamp(
                      UiScaleNotifier.minScale, UiScaleNotifier.maxScale));
            },
    );
  }

  Widget _buildScalePlusButton(double effectiveScale) {
    return IconButton(
      tooltip: 'Zoom in (+5%)',
      splashRadius: 14,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.add_rounded, size: 16, color: Colors.white70),
      onPressed: effectiveScale >= UiScaleNotifier.maxScale - 0.01
          ? null
          : () {
              final next = ((effectiveScale + 0.05) * 100).round() / 100;
              ref
                  .read(uiScaleConfirmationProvider.notifier)
                  .requestScaleChange(next.clamp(
                      UiScaleNotifier.minScale, UiScaleNotifier.maxScale));
            },
    );
  }

  Widget _buildScaleSliderWidget(double effectiveScale, Color accentColor) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4.0,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: 6.5,
          elevation: 2,
          pressedElevation: 4,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: 12.0,
        ),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        showValueIndicator: ShowValueIndicator.never,
        activeTrackColor: accentColor,
        inactiveTrackColor: Colors.white.withOpacity(0.12),
        thumbColor: accentColor,
        overlayColor: accentColor.withOpacity(0.15),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: effectiveScale.clamp(
          UiScaleNotifier.minScale,
          UiScaleNotifier.maxScale,
        ),
        min: UiScaleNotifier.minScale,
        max: UiScaleNotifier.maxScale,
        divisions: 12,
        onChanged: (val) {
          final rounded = (val * 100).round() / 100;
          setState(() {
            _tempUiScale = rounded;
          });
        },
        onChangeEnd: (val) {
          final rounded = (val * 100).round() / 100;
          setState(() {
            _tempUiScale = null;
          });
          ref
              .read(uiScaleConfirmationProvider.notifier)
              .requestScaleChange(rounded);
        },
      ),
    );
  }

  Widget _buildUiScaleTile(double currentUiScale, {bool mobile = false}) {
    final effectiveScale = _tempUiScale ?? currentUiScale;
    final percent = (effectiveScale * 100).round();
    final accentColor = NivioTheme.accentColorOf(context);
    final isDefault = (percent == 100);
    final isDesktop = !mobile && AppPlatform.useDesktopLayout &&
        MediaQuery.sizeOf(context).width > 800;

    // Mobile layout: slider capsule placed directly below the description for maximum width & ease of touch
    if (!isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                Icons.aspect_ratio_rounded,
                color: NivioTheme.netflixWhite,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'UI Scale',
                          style: TextStyle(
                            color: NivioTheme.netflixWhite,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      _buildScaleBadge(
                        isDefault: isDefault,
                        percent: percent,
                        accentColor: accentColor,
                      ),
                      if (!isDefault) ...[
                        const SizedBox(width: 8),
                        _buildScaleResetButton(
                          isDefault: isDefault,
                          accentColor: accentColor,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Adjust interface zoom level',
                    style: TextStyle(
                      color: NivioTheme.netflixGrey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Sleek framed capsule controller below description
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        _buildScaleMinusButton(effectiveScale),
                        Expanded(
                          child: _buildScaleSliderWidget(
                              effectiveScale, accentColor),
                        ),
                        _buildScalePlusButton(effectiveScale),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Desktop layout: sleek inline row on the right
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Icon(
            Icons.aspect_ratio_rounded,
            color: NivioTheme.netflixWhite,
            size: 22,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'UI Scale',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Adjust interface zoom level',
                  style: TextStyle(
                    color: NivioTheme.netflixGrey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Sleek framed capsule controller on the right
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildScaleMinusButton(effectiveScale),
                SizedBox(
                  width: 145,
                  child: _buildScaleSliderWidget(effectiveScale, accentColor),
                ),
                _buildScalePlusButton(effectiveScale),
                const SizedBox(width: 2),
                _buildScaleBadge(
                  isDefault: isDefault,
                  percent: percent,
                  accentColor: accentColor,
                ),
                if (!isDefault) ...[
                  const SizedBox(width: 4),
                  _buildScaleResetButton(
                    isDefault: isDefault,
                    accentColor: accentColor,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkNow() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: NivioTheme.accentColorOf(context),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Checking for new episodes...',
                  style: TextStyle(color: NivioTheme.netflixWhite),
                ),
              ),
            ],
          ),
        );
      },
    );

    final count = await EpisodeCheckService.checkNow();
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count > 0
              ? 'Found $count new episode${count > 1 ? 's' : ''}'
              : 'No new episodes found',
        ),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }


  Future<void> _showClearHistoryDialog() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          title: const Text(
            'Clear Watch History?',
            style: TextStyle(color: NivioTheme.netflixWhite),
          ),
          content: const Text(
            'This removes all watch progress and activity for this account.',
            style: TextStyle(color: NivioTheme.netflixLightGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Clear',
                style: TextStyle(color: NivioTheme.accentColorOf(context)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldClear != true) return;

    final historyService = ref.read(watchHistoryServiceProvider);
    await historyService.clearAllHistory();
    ref.invalidate(continueWatchingProvider);
    ref.invalidate(watchHistoryProvider);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Watch history cleared',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }

  Future<void> _showClearCacheDialog() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          title: const Text(
            'Clear Cache?',
            style: TextStyle(color: NivioTheme.netflixWhite),
          ),
          content: const Text(
            'This clears temporary cached data. The app may load slower briefly.',
            style: TextStyle(color: NivioTheme.netflixLightGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Clear',
                style: TextStyle(color: NivioTheme.accentColorOf(context)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldClear != true) return;

    final cacheService = ref.read(cacheServiceProvider);
    await cacheService.clearAll();
    
    // Clear image cache
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    await DefaultCacheManager().emptyCache();
    

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Cache cleared',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
        ),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }

  Future<void> _showSignOutDialog() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          title: const Text(
            'Sign Out?',
            style: TextStyle(color: NivioTheme.netflixWhite),
          ),
          content: const Text(
            'Your local preferences stay saved.',
            style: TextStyle(color: NivioTheme.netflixLightGrey),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(
                'Sign Out',
                style: TextStyle(color: NivioTheme.accentColorOf(context)),
              ),
            ),
          ],
        );
      },
    );

    if (shouldSignOut != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    context.go('/auth');
  }

  Future<String> _getAppVersionLabel() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final baseVersion = info.buildNumber.isEmpty
          ? info.version
          : '${info.version} (${info.buildNumber})';
      if (!ShorebirdUpdateService.isAvailable) {
        return baseVersion;
      }
      final patch = await ShorebirdUpdateService.currentPatchNumber();
      if (patch == null) {
        return '$baseVersion • patch: base';
      }
      return '$baseVersion • patch: $patch';
    } catch (_) {
      return 'Unknown';
    }
  }

  Future<void> _showAppVersionDialog() async {
    final packageInfo = await PackageInfo.fromPlatform();
    final String version = packageInfo.version;
    final String buildNumber = packageInfo.buildNumber;
    
    int? currentPatch;
    ShorebirdUpdateResult? updateCheck;
    bool isChecking = ShorebirdUpdateService.isAvailable;

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            if (isChecking) {
              isChecking = false;
              ShorebirdUpdateService.currentPatchNumber().then((patch) {
                currentPatch = patch;
                return ShorebirdUpdateService.checkAndUpdate();
              }).then((result) {
                if (mounted && context.mounted) {
                  setState(() {
                    updateCheck = result;
                  });
                }
              }).catchError((_) {
                if (mounted && context.mounted) {
                  setState(() {
                    updateCheck = const ShorebirdUpdateResult(
                      action: ShorebirdUpdateAction.failed,
                      message: 'Could not check for patch updates.',
                    );
                  });
                }
              });
            }

            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: NivioTheme.netflixDarkGrey,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // App Logo
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: NivioTheme.accentColorOf(context).withOpacity(0.3),
                            blurRadius: 18,
                            offset: const Offset(0, 6),
                          )
                        ],
                        image: const DecorationImage(
                          image: AssetImage('assets/images/app-icon.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'Nivio',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Version $version ($buildNumber)',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Divider(color: Colors.white12),
                    const SizedBox(height: 16),
                    
                    if (updateCheck == null && ShorebirdUpdateService.isAvailable)
                      Column(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: NivioTheme.accentColorOf(context),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Checking for patch updates...',
                            style: TextStyle(color: Colors.white60, fontSize: 13),
                          ),
                        ],
                      )
                    else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            currentPatch != null ? Icons.verified_rounded : Icons.info_outline_rounded,
                            color: currentPatch != null ? Colors.greenAccent : Colors.white54,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            currentPatch != null 
                              ? 'Active Patch: #$currentPatch' 
                              : 'Active Patch: Base Release',
                            style: TextStyle(
                              color: currentPatch != null ? Colors.white : Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (updateCheck != null)
                        Text(
                          updateCheck!.message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: updateCheck!.action == ShorebirdUpdateAction.downloaded || 
                                   updateCheck!.action == ShorebirdUpdateAction.restartRequired
                                ? NivioTheme.accentColorOf(context)
                                : Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                    ],
                    
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white10,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Future<void> _showChangelog(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(changelogProvider.notifier);
    final currentVersion = ref.read(changelogProvider).currentVersion;
    final notes = await notifier.forceFetchNotes();
    if (!context.mounted) return;
    
    if (notes == null || notes.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No release notes found for this version.')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ChangelogDialog(
        version: currentVersion,
        releaseNotes: notes,
        onDismiss: () {},
      ),
    );
  }

  Future<void> _checkForGitHubRelease() async {
    if (!mounted) return;
    BuildContext? dialogContext;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return AlertDialog(
          backgroundColor: NivioTheme.sheetColorOf(context),
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: NivioTheme.accentColorOf(context),
                ),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  'Checking latest GitHub release...',
                  style: TextStyle(color: NivioTheme.netflixWhite),
                ),
              ),
            ],
          ),
        );
      },
    );

    final result = await GitHubReleaseUpdateService.checkForUpdate(
      forceRefresh: true,
    );

    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }
    if (!mounted) return;

    if (result.hasUpdate) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          return ChangelogDialog(
            version: result.latestVersion,
            releaseNotes: result.releaseNotes ?? 'A new update is available. Please update to enjoy the latest features and bug fixes!',
            isUpdatePrompt: true,
            onDismiss: () {},
            onInstall: () async {
              await DesktopSelfUpdater.installOrOpen(context, result.releaseUrl);
            },
          );
        },
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.status == GitHubReleaseUpdateStatus.failed
            ? const Color(0xFFB00020)
            : NivioTheme.accentColorOf(context),
      ),
    );
  }

  Future<void> _showAudioLanguageDialog() async {
    final current = ref.read(preferredAudioLanguageProvider);
    final options = ['Original', 'English', 'Japanese', 'Hindi', 'Tamil', 'Telugu', 'Spanish', 'French', 'Korean', 'German', 'Italian'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Preferred Audio Language',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      option,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(preferredAudioLanguageProvider.notifier).setLanguage(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleLanguageDialog() async {
    final current = ref.read(preferredSubtitleLanguageProvider);
    final options = ['Auto', 'Off', 'English', 'Japanese', 'Hindi', 'Tamil', 'Telugu', 'Spanish', 'French', 'Korean', 'German', 'Italian'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Preferred Subtitle Language',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      option,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(preferredSubtitleLanguageProvider.notifier).setLanguage(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleFontDialog() async {
    final current = ref.read(subtitleFontFamilyProvider);
    final customName = ref.read(customSubtitleFontNameProvider);
    final customPath = ref.read(customSubtitleFontPathProvider);
    final options = subtitleFontFamilyOptions;

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Subtitle Font',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final font = options[index];
                  final isSelected = current == font;

                  if (font == 'Custom') {
                    final hasCustom = customPath != null && customPath.isNotEmpty;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: Icon(
                        Icons.font_download_outlined,
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite.withOpacity(0.7),
                      ),
                      title: Text(
                        customName != null ? 'Custom ($customName)' : 'Custom Font (.ttf / .otf)',
                        style: TextStyle(
                          color: isSelected
                              ? NivioTheme.accentColorOf(context)
                              : NivioTheme.netflixWhite,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        hasCustom ? 'Tap to apply or browse a new file' : 'Import your own font file (.ttf / .otf)',
                        style: TextStyle(
                          color: NivioTheme.netflixWhite.withOpacity(0.5),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isSelected)
                            Icon(Icons.check_circle_rounded,
                                color: NivioTheme.accentColorOf(context)),
                          IconButton(
                            icon: const Icon(Icons.folder_open_rounded, color: Colors.white70),
                            tooltip: 'Browse font file',
                            onPressed: () async {
                              final ok = await pickAndImportCustomFont(context, ref);
                              if (ok && context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        if (hasCustom) {
                          await ref.read(subtitleFontFamilyProvider.notifier).setFamily('Custom');
                          if (context.mounted) Navigator.pop(context);
                        } else {
                          final ok = await pickAndImportCustomFont(context, ref);
                          if (ok && context.mounted) Navigator.pop(context);
                        }
                      },
                    );
                  }

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      font,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    subtitle: Text(
                      'The quick brown fox jumps over the lazy dog',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: getSubtitleTextStyle(
                        fontFamily: font,
                        fontSize: 13,
                        color: isSelected
                            ? NivioTheme.accentColorOf(context).withOpacity(0.85)
                            : NivioTheme.netflixWhite.withOpacity(0.6),
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(subtitleFontFamilyProvider.notifier).setFamily(font);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleFontSizeDialog() async {
    final current = ref.read(subtitleFontSizeProvider);
    final options = subtitleFontSizeOptions.entries.toList();

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Subtitle Font Size',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option.value;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      option.key,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(subtitleFontSizeProvider.notifier).setSize(option.value);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleBackgroundDialog() async {
    final current = ref.read(subtitleBackgroundProvider);
    final options = ['Transparent', 'Semi-Transparent', 'Solid'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Subtitle Background',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      option,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(subtitleBackgroundProvider.notifier).setBackground(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSubtitleOutlineDialog() async {
    final current = ref.read(subtitleOutlineProvider);
    final options = ['None', 'Subtle Shadow', 'Outline'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Subtitle Text Style',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      option,
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(subtitleOutlineProvider.notifier).setOutline(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDownloadConcurrencyDialog() async {
    final current = ref.read(downloadConcurrencyProvider);
    final options = [2, 4, 6, 8, 12, 16];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.sheetColorOf(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Parallel Download Connections',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'Higher values mean faster speeds but use more battery and CPU.',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = current == option;

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    title: Text(
                      '$option connections',
                      style: TextStyle(
                        color: isSelected
                            ? NivioTheme.accentColorOf(context)
                            : NivioTheme.netflixWhite,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle_rounded,
                            color: NivioTheme.accentColorOf(context))
                        : null,
                    onTap: () {
                      ref.read(downloadConcurrencyProvider.notifier).setPreference(option);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, User user) {
    return Scaffold(
      backgroundColor: NivioTheme.backgroundColorOf(context),
      body: Container(
        decoration: BoxDecoration(
          gradient: NivioTheme.backgroundGradientOf(context),
        ),
        child: SafeArea(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDesktopSidebar(user),
              Expanded(
                child: _buildDesktopContentArea(user),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopSidebar(User user) {
    return Container(
      width: 280,
      color: Colors.black.withOpacity(0.3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                tooltip: 'Back',
                onPressed: _handleBackNavigation,
                icon: const PhosphorIcon(
                  PhosphorIconsRegular.caretLeft,
                  color: NivioTheme.netflixWhite,
                  size: 22,
                ),
              ),
            ),
          ),
          _buildProfileHeader(user),
          const Divider(color: Colors.white12, height: 1),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: _buildSearchField(),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: AppListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 12),
              itemCount: _desktopCategoryOrder.length,
              itemBuilder: (context, position) {
                final index = _desktopCategoryOrder[position];
                final isSelected = _selectedCategoryIndex == index;
                return _SidebarCategoryTile(
                  label: _categoryLabel(index),
                  isSelected: isSelected,
                  onTap: () => setState(() => _selectedCategoryIndex = index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopContentArea(User user) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_query.isNotEmpty) ...[
            const Text(
              'Search Results',
              style: TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: AppSingleChildScrollView(
                child: _buildSearchResultsCard(
                  user: user,
                  languagePrefs: ref.watch(languagePreferencesProvider),
                  videoQuality: ref.watch(videoQualityProvider),
                  preferredAudio: ref.watch(preferredAudioLanguageProvider),
                  preferredSubtitle: ref.watch(preferredSubtitleLanguageProvider),
                  episodeCheckEnabled: ref.watch(episodeCheckEnabledProvider),
                  videoDebanding: ref.watch(videoDebandingProvider),
                  appThemeKey: ref.watch(appThemeProvider),
                  uiScale: ref.watch(uiScaleProvider),
                ),
              ),
            ),
          ] else ...[
            Text(
              _categoryLabel(_selectedCategoryIndex),
              style: const TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: PageTransitionSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation, secondaryAnimation) {
                  return FadeThroughTransition(
                    animation: animation,
                    secondaryAnimation: secondaryAnimation,
                    fillColor: Colors.transparent,
                    child: child,
                  );
                },
                child: _buildCategoryContent(user, _selectedCategoryIndex),
              ),
            ),
          ]
        ],
      ),
    );
  }

  Widget _buildCategoryContent(User user, int index, {bool mobile = false}) {
    // We duplicate the variables here because we didn't extract them.
    final watchlist = ref.watch(watchlistProvider);
    final historyAsync = ref.watch(watchHistoryProvider);
    final languagePrefs = ref.watch(languagePreferencesProvider);
    final autoPlayNextEpisode = ref.watch(autoPlayNextEpisodeProvider);
    final pipOnLostVisibility = ref.watch(pipOnLostVisibilityProvider);
    final pauseOnLostVisibility = ref.watch(pauseOnLostVisibilityProvider);
    final seekDuration = ref.watch(seekDurationProvider);
    final autoSkipIntroOutro = ref.watch(autoSkipIntroOutroProvider);
    final autoSkipFiller = ref.watch(autoSkipFillerProvider);
    final videoQuality = ref.watch(videoQualityProvider);
    final preferredAudio = ref.watch(preferredAudioLanguageProvider);
    final preferredSubtitle = ref.watch(preferredSubtitleLanguageProvider);
    final episodeCheckEnabled = ref.watch(episodeCheckEnabledProvider);
    final videoDebanding = ref.watch(videoDebandingProvider);
    final subtitleFontSize = ref.watch(subtitleFontSizeProvider);
    final subtitleBackground = ref.watch(subtitleBackgroundProvider);
    final subtitleOutline = ref.watch(subtitleOutlineProvider);
    final subtitleFontFamily = ref.watch(subtitleFontFamilyProvider);
    final customFontName = ref.watch(customSubtitleFontNameProvider);
    final appThemeKey = ref.watch(appThemeProvider);
    final uiScale = ref.watch(uiScaleProvider);

    final content = _buildCategorySettingsList(
          index,
          user: user,
          watchlist: watchlist,
          historyAsync: historyAsync,
          languagePrefs: languagePrefs,
          autoPlayNextEpisode: autoPlayNextEpisode,
          pipOnLostVisibility: pipOnLostVisibility,
          pauseOnLostVisibility: pauseOnLostVisibility,
          seekDuration: seekDuration,
          autoSkipIntroOutro: autoSkipIntroOutro,
          autoSkipFiller: autoSkipFiller,
          videoQuality: videoQuality,
          preferredAudio: preferredAudio,
          preferredSubtitle: preferredSubtitle,
          episodeCheckEnabled: episodeCheckEnabled,
          videoDebanding: videoDebanding,
          subtitleFontSize: subtitleFontSize,
          subtitleBackground: subtitleBackground,
          subtitleOutline: subtitleOutline,
          subtitleFontFamily: subtitleFontFamily,
          customFontName: customFontName,
          appThemeKey: appThemeKey,
          uiScale: uiScale,
      mobile: mobile,
    );
    return AppSingleChildScrollView(
      key: ValueKey(index),
      padding: EdgeInsets.only(bottom: mobile ? 20 : 0),
      child: Material(
        color: Colors.white.withValues(alpha: mobile ? 0.05 : 0.03),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.all(mobile ? 4 : 24),
          child: content,
        ),
      ),
    );
  }

  Widget _buildCategorySettingsList(
    int index, {
    required User user,
    required List<dynamic> watchlist,
    required AsyncValue<List<dynamic>> historyAsync,
    required dynamic languagePrefs,
    required bool autoPlayNextEpisode,
    required bool pipOnLostVisibility,
    required bool pauseOnLostVisibility,
    required int seekDuration,
    required bool autoSkipIntroOutro,
    required bool autoSkipFiller,
    required String videoQuality,
    required String preferredAudio,
    required String preferredSubtitle,
    required bool episodeCheckEnabled,
    required bool videoDebanding,
    required double subtitleFontSize,
    required String subtitleBackground,
    required String subtitleOutline,
    required String subtitleFontFamily,
    required String? customFontName,
    required String appThemeKey,
    required double uiScale,
    required bool mobile,
  }) {
    switch (index) {
      case 0: // Profile & Activity
        return Column(
          children: [
            historyAsync.when(
              loading: () => _buildStatsPlaceholder(),
              error: (error, stackTrace) => _buildStatsPlaceholder(),
              data: (history) => _buildStatsRow(
                watchlistCount: watchlist.length,
                historyCount: history.length,
                completedCount: history.where((entry) => entry.isCompleted).length,
              ),
            ),
            const SizedBox(height: 24),
            _buildSectionCard(
              title: 'Recent Activity',
              initiallyExpanded: true,
              child: _buildRecentActivity(historyAsync),
            ),
            if (watchlist.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionCard(
                title: 'Watchlist',
                child: _buildWatchlistPreview(watchlist),
              ),
            ],
          ],
        );
      case 1: // Playback
        return Column(
          children: [
            _streamSelectionTile(),
            _contentWarningsTile(),
            _buildActionTile(
              icon: Icons.record_voice_over_rounded,
              title: 'Preferred Anime Audio',
              subtitle: languagePrefs.animePreferredAudio == 'sub' ? 'Subbed' : 'Dubbed',
              onTap: _showAnimeAudioDialog,
            ),
            _buildSwitchTile(
              icon: Icons.skip_next_rounded,
              title: 'Auto Play Next Episode',
              subtitle: 'Automatically start the next episode when current finishes',
              value: autoPlayNextEpisode,
              onChanged: (val) {
                ref.read(autoPlayNextEpisodeProvider.notifier).setEnabled(val);
              },
            ),
            _watchPartyFollowHostTile(),
            _buildSwitchTile(
              icon: Icons.picture_in_picture_alt_rounded,
              title: 'PiP on Lost Visibility',
              subtitle: 'Switch to Picture-in-Picture when leaving the app',
              value: pipOnLostVisibility,
              onChanged: (val) {
                ref.read(pipOnLostVisibilityProvider.notifier).setEnabled(val);
              },
            ),
            _buildSwitchTile(
              icon: Icons.pause_circle_outline_rounded,
              title: 'Pause on Lost Visibility',
              subtitle: 'Pause playback when app loses focus or goes to background',
              value: pauseOnLostVisibility,
              onChanged: (val) {
                ref.read(pauseOnLostVisibilityProvider.notifier).setEnabled(val);
              },
            ),
            if (_showAmbientSetting) ..._buildAmbientModeTiles(),
            _buildActionTile(
              icon: Icons.fast_forward_rounded,
              title: 'Seek Duration',
              subtitle: '${seekDuration}s',
              onTap: _showSeekDurationDialog,
            ),
            _buildSwitchTile(
              icon: Icons.fast_forward_rounded,
              title: 'Auto Skip Intro & Outro',
              subtitle: 'Automatically skip opening and ending themes',
              value: autoSkipIntroOutro,
              onChanged: (val) {
                ref.read(autoSkipIntroOutroProvider.notifier).setEnabled(val);
              },
            ),
            _buildSwitchTile(
              icon: Icons.auto_stories_rounded,
              title: 'Auto Skip Filler',
              subtitle: 'Automatically skip filler episodes during auto-play',
              value: autoSkipFiller,
              onChanged: (val) {
                ref.read(autoSkipFillerProvider.notifier).setEnabled(val);
              },
            ),
            _buildActionTile(
              icon: Icons.high_quality_rounded,
              title: 'Preferred Video Quality',
              subtitle: _qualityLabel(videoQuality),
              onTap: _showVideoQualityDialog,
            ),
            _buildActionTile(
              icon: Icons.audiotrack_rounded,
              title: 'Preferred Audio Language',
              subtitle: preferredAudio,
              onTap: _showAudioLanguageDialog,
            ),
            _buildActionTile(
              icon: Icons.subtitles_rounded,
              title: 'Preferred Subtitle Language',
              subtitle: preferredSubtitle,
              onTap: _showSubtitleLanguageDialog,
            ),
            _buildSwitchTile(
              icon: Icons.blur_linear_rounded,
              title: 'Video Debanding',
              subtitle: 'Reduces color banding (uses more battery)',
              value: videoDebanding,
              onChanged: (value) {
                ref.read(videoDebandingProvider.notifier).setEnabled(value);
              },
            ),
            // Android TV uses this layout.
            if (_showHdrSettings) ..._buildHdrSettingTiles(),
            if (AppPlatform.supportsDolbyPassthrough)
              _buildDolbyPassthroughTile(),
          ],
        );
      case 2: // Subtitle Appearance
        return Column(
          children: [
            _buildActionTile(
              icon: Icons.font_download_rounded,
              title: 'Subtitle Font',
              subtitle: subtitleFontFamily == 'Custom' && customFontName != null
                  ? 'Custom ($customFontName)'
                  : subtitleFontFamily,
              onTap: _showSubtitleFontDialog,
            ),
            _buildActionTile(
              icon: Icons.format_size_rounded,
              title: 'Subtitle Font Size',
              subtitle: subtitleFontSizeLabel(subtitleFontSize),
              onTap: _showSubtitleFontSizeDialog,
            ),
            _buildActionTile(
              icon: Icons.picture_in_picture_alt_rounded,
              title: 'Subtitle Background',
              subtitle: subtitleBackground,
              onTap: _showSubtitleBackgroundDialog,
            ),
            _buildActionTile(
              icon: Icons.text_fields_rounded,
              title: 'Subtitle Text Style',
              subtitle: subtitleOutline,
              onTap: _showSubtitleOutlineDialog,
            ),
          ],
        );
      case 3: // Downloads
        return Column(
          children: [
            _buildActionTile(
              icon: Icons.speed_rounded,
              title: 'Parallel Download Connections',
              subtitle: '${ref.watch(downloadConcurrencyProvider)}',
              onTap: _showDownloadConcurrencyDialog,
            ),
            _buildDownloadLocationNote(),
          ],
        );
      case 4: // Network
        return Column(
          children: [
            _buildSwitchTile(
              icon: Icons.vpn_lock_rounded,
              title: 'Use DNS over HTTPS',
              subtitle:
                  'This enables DNS over HTTPS, useful if your ISP blocks certain domains.',
              value: ref.watch(useDnsOverHttpsProvider),
              onChanged: (value) {
                ref.read(useDnsOverHttpsProvider.notifier).setEnabled(value);
              },
            ),
            _buildActionTile(
              icon: Icons.dns_rounded,
              title: 'DNS over HTTPS URL',
              subtitle: ref.watch(dnsOverHttpsUrlProvider),
              onTap: _showDnsUrlDialog,
            ),
          ],
        );
      case 5: // Content & Discovery
        return Column(
          children: [
            const StreamSourceSettings(inPanel: false),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.dashboard_customize_rounded,
              title: 'Customize Home Layout',
              subtitle: 'Rearrange the order of shelves on the home screen',
              onTap: () => _showHomeLayoutDialog(context),
            ),
            _buildSwitchTile(
              icon: Icons.animation_rounded,
              title: 'Anime',
              subtitle: 'Show anime rows on home',
              value: languagePrefs.showAnime,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleAnime(value),
            ),
            _buildSwitchTile(
              icon: Icons.movie_filter_rounded,
              title: 'Tamil',
              subtitle: 'Show Tamil rows on home',
              value: languagePrefs.showTamil,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleTamil(value),
            ),
            _buildSwitchTile(
              icon: Icons.movie_creation_outlined,
              title: 'Telugu',
              subtitle: 'Show Telugu rows on home',
              value: languagePrefs.showTelugu,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleTelugu(value),
            ),
            _buildSwitchTile(
              icon: Icons.theaters_rounded,
              title: 'Hindi',
              subtitle: 'Show Hindi rows on home',
              value: languagePrefs.showHindi,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleHindi(value),
            ),
            _buildSwitchTile(
              icon: Icons.live_tv_rounded,
              title: 'Korean',
              subtitle: 'Show Korean rows on home',
              value: languagePrefs.showKorean,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleKorean(value),
            ),
            _buildSwitchTile(
              icon: Icons.movie_outlined,
              title: 'Malayalam',
              subtitle: 'Show Malayalam rows on home',
              value: languagePrefs.showMalayalam,
              onChanged: (value) => ref.read(languagePreferencesProvider.notifier).toggleMalayalam(value),
            ),
          ],
        );
      case 6: // Episode Alerts
        return Column(
          children: [
            _buildSwitchTile(
              icon: Icons.notifications_active_outlined,
              title: 'New Episode Alerts',
              subtitle: episodeCheckEnabled ? 'Enabled' : 'Disabled',
              value: episodeCheckEnabled,
              onChanged: (value) => ref.read(episodeCheckEnabledProvider.notifier).setEnabled(value),
            ),
            _buildActionTile(
              icon: Icons.notifications_none_rounded,
              title: 'Open New Episodes',
              subtitle: 'View recently detected episodes',
              onTap: () => context.go('/library'),
            ),
            _buildActionTile(
              icon: Icons.sync_rounded,
              title: 'Check Now',
              subtitle: 'Manually check for newly aired episodes',
              onTap: _checkNow,
            ),
          ],
        );
      case 7: // Anime Tracking
        return _buildAnimeTrackingContent();
      case _appearanceCategory:
        return Column(
          children: [
            _dynamicColorsTile(),
            _buildActionTile(
              icon: Icons.palette_outlined,
              title: 'App Theme',
              subtitle: NivioTheme.getTheme(appThemeKey).label,
              onTap: _showThemeDialog,
            ),
            _buildUiScaleTile(uiScale, mobile: mobile),
            if (_showLiquidGlassSetting) _buildLiquidGlassNavTile(),
          ],
        );
      case 8: // App & Updates
        return Column(
          children: [
            FutureBuilder<String>(
              future: _getAppVersionLabel(),
              builder: (context, snapshot) {
                return _buildActionTile(
                  icon: Icons.info_outline_rounded,
                  title: 'App Version',
                  subtitle: snapshot.data ?? 'Loading...',
                  onTap: _showAppVersionDialog,
                );
              },
            ),
            FutureBuilder<GitHubReleaseUpdateResult>(
              future: GitHubReleaseUpdateService.checkForUpdate(),
              builder: (context, snapshot) {
                final result = snapshot.data;
                final subtitle = result == null
                    ? 'Checking GitHub releases...'
                    : result.hasUpdate
                        ? 'Latest ${result.latestVersion} available'
                        : result.message;
                return _buildActionTile(
                  icon: Icons.download_for_offline_outlined,
                  title: 'Check GitHub Release',
                  subtitle: subtitle,
                  onTap: _checkForGitHubRelease,
                );
              },
            ),
            FutureBuilder<String>(
              future: _getAppVersionLabel(),
              builder: (context, snapshot) {
                return _buildActionTile(
                  icon: Icons.new_releases_outlined,
                  title: "What's New",
                  subtitle: 'See changes in ${snapshot.data ?? 'this version'}',
                  onTap: () => _showChangelog(context, ref),
                );
              },
            ),
            _buildActionTile(
              icon: Icons.favorite_rounded,
              title: 'Sponsor Nivio',
              subtitle: 'Support the development on GitHub',
              titleColor: Colors.pinkAccent,
              onTap: () {
                final sponsorUrl = dotenv.env['GITHUB_SPONSOR_URL'] ?? 'https://github.com/sponsors/nirmaleeswar30';
                launchUrl(Uri.parse(sponsorUrl), mode: LaunchMode.externalApplication);
              },
            ),
          ],
        );
      case 9: // Data & Account
        return Column(
          children: [
            _buildActionTile(
              icon: Icons.delete_sweep_outlined,
              title: 'Clear Watch History',
              subtitle: 'Remove all watch progress and activity',
              onTap: _showClearHistoryDialog,
            ),
            _buildActionTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Clear Cache',
              subtitle: 'Clear cached API and image metadata',
              onTap: _showClearCacheDialog,
            ),
            _buildActionTile(
              icon: Icons.logout_rounded,
              title: user.isAnonymous ? 'Exit Guest Mode' : 'Sign Out',
              subtitle: user.email ?? 'Current session',
              titleColor: NivioTheme.accentColorOf(context),
              onTap: _showSignOutDialog,
            ),
          ],
        );
      default:
        return const SizedBox();
    }
  }

  Widget _buildTrackingAccounts() {
    final aniListUser = ref.watch(aniListAuthProvider);
    final malUser = ref.watch(malAuthProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAnimeTrackingAccountTile(
          title: 'AniList',
          subtitle: 'Sync watch progress & Planning list',
          provider: TrackingProvider.anilist,
          user: aniListUser,
          brandColor: const Color(0xFF02A9FF),
          onConnect: () async {
            final launched =
                await ref.read(aniListAuthProvider.notifier).launchAuth();
            if (!launched && mounted) {
              _showAniListManualTokenDialog();
            }
          },
          onManualEntry: _showAniListManualTokenDialog,
          onDisconnect: () => ref.read(aniListAuthProvider.notifier).logout(),
          manualButtonLabel: 'Enter AniList Code / Token Manually',
        ),
        const SizedBox(height: 8),
        _buildAnimeTrackingAccountTile(
          title: 'MyAnimeList',
          subtitle: 'Sync watch progress & Plan to Watch',
          provider: TrackingProvider.mal,
          user: malUser,
          brandColor: const Color(0xFF2E51A2),
          onConnect: () async {
            final launched =
                await ref.read(malAuthProvider.notifier).launchAuth();
            if (!launched && mounted) {
              _showMalManualCodeDialog();
            }
          },
          onManualEntry: _showMalManualCodeDialog,
          onDisconnect: () => ref.read(malAuthProvider.notifier).logout(),
          manualButtonLabel: 'Enter MAL Code Manually',
        ),
        const SizedBox(height: 8),
        _buildSimklAccountTile(),
      ],
    );
  }

  Widget _buildAnimeTrackingContent() {
    final autoSyncProgress = ref.watch(animeAutoSyncProgressProvider);
    final autoSyncWatchlist = ref.watch(animeAutoSyncWatchlistProvider);
    final untrackedBehavior = ref.watch(untrackedAnimeBehaviorProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
          _buildDiscordDesktopTile(),
        if (Platform.isAndroid || Platform.isIOS) _buildDiscordMobileTile(),
        _buildTrackingAccounts(),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 8),
        _buildSwitchTile(
          icon: Icons.sync_alt_rounded,
          title: 'Auto-Sync Watch Progress',
          subtitle:
              'Automatically sync episode progress to AniList & MAL when watching anime (>80%)',
          value: autoSyncProgress,
          onChanged: (val) {
            ref.read(animeAutoSyncProgressProvider.notifier).setEnabled(val);
          },
        ),
        _buildActionTile(
          icon: untrackedBehavior == UntrackedAnimeBehavior.prompt
              ? Icons.notifications_active_rounded
              : Icons.sync_rounded,
          title: 'Untracked Anime Behavior',
          subtitle: untrackedBehavior == UntrackedAnimeBehavior.prompt
              ? 'Prompt to Track (Anime Slayer style)'
              : 'Auto-Sync silently (>80% progress)',
          onTap: () => _showUntrackedBehaviorDialog(untrackedBehavior),
        ),
        _buildSwitchTile(
          icon: Icons.playlist_add_check_rounded,
          title: 'Auto-Sync Watchlist',
          subtitle:
              'Automatically add or remove anime from your AniList & MAL planning lists',
          value: autoSyncWatchlist,
          onChanged: (val) {
            ref.read(animeAutoSyncWatchlistProvider.notifier).setEnabled(val);
          },
        ),
        _buildActionTile(
          icon: _isSyncingAnime ? Icons.sync_rounded : Icons.cloud_sync_rounded,
          title: 'Sync Library Now',
          subtitle: 'Last synced: ${_formatLastAnimeSyncTime()}',
          onTap: _syncAnimeWatchlistNow,
        ),
      ],
    );
  }

  void _showUntrackedBehaviorDialog(UntrackedAnimeBehavior current) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.sheetColorOf(context),
        title: const Text(
          'Untracked Anime Behavior',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RadioListTile<UntrackedAnimeBehavior>(
              value: UntrackedAnimeBehavior.autoSync,
              groupValue: current,
              title: const Text('Auto-Sync Silently',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Automatically add to Watching when an episode is >80% watched.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              activeColor: NivioTheme.accentColorOf(ctx),
              onChanged: (val) {
                if (val != null) {
                  ref
                      .read(untrackedAnimeBehaviorProvider.notifier)
                      .setBehavior(val);
                  Navigator.of(ctx).pop();
                }
              },
            ),
            RadioListTile<UntrackedAnimeBehavior>(
              value: UntrackedAnimeBehavior.prompt,
              groupValue: current,
              title: const Text('Prompt to Track (Anime Slayer style)',
                  style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Show a discrete banner asking if you want to add the anime to Watching.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              activeColor: NivioTheme.accentColorOf(ctx),
              onChanged: (val) {
                if (val != null) {
                  ref
                      .read(untrackedAnimeBehaviorProvider.notifier)
                      .setBehavior(val);
                  Navigator.of(ctx).pop();
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimeTrackingAccountTile({
    required String title,
    required String subtitle,
    required TrackingProvider provider,
    required TrackingUser? user,
    required VoidCallback onConnect,
    required VoidCallback onManualEntry,
    required VoidCallback onDisconnect,
    required String manualButtonLabel,
    Color brandColor = Colors.blueAccent,
  }) {
    final logo = provider == TrackingProvider.anilist
        ? const AniListLogo(size: 38)
        : const MalLogo(size: 38);
    return _TrackingAccountCard(
      key: ValueKey(provider),
      title: title,
      description: subtitle,
      username: user?.username,
      avatarUrl: user?.avatarUrl,
      connected: user != null,
      brand: brandColor,
      logo: logo,
      manualLabel: manualButtonLabel,
      onConnect: onConnect,
      onManualEntry: onManualEntry,
      onDisconnect: onDisconnect,
    );
  }

  Widget _buildSimklAccountTile() {
    final user = ref.watch(simklAuthProvider);
    return _TrackingAccountCard(
      key: const ValueKey('simkl'),
      title: 'Simkl',
      description: 'Sync movies, TV and anime with Simkl',
      username: user?.username,
      avatarUrl: user?.avatarUrl,
      connected: user != null,
      brand: const Color(0xFF0AA1DD),
      logo: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset('assets/images/simkl_logo.png', width: 38, height: 38),
      ),
      manualLabel: 'Enter Simkl code or URL',
      onConnect: () async {
        final launched = await ref.read(simklAuthProvider.notifier).launchAuth();
        if (!launched && mounted) _showSimklManualCodeDialog();
      },
      onManualEntry: _showSimklManualCodeDialog,
      onDisconnect: () => ref.read(simklAuthProvider.notifier).logout(),
    );
  }

  void _showSimklManualCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.sheetColorOf(context, fallback: const Color(0xFF1F1F1F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter Simkl Code or URL',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If the browser did not redirect back into Nivio, authorize on Simkl and paste the authorization code (or full redirect URL) here:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'code=... or nivio://auth/simkl?code=...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = controller.text.trim();
              Navigator.pop(ctx);
              if (input.isEmpty) return;
              final ok =
                  await ref.read(simklAuthProvider.notifier).loginWithInput(input);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok
                        ? 'Connected to Simkl'
                        : 'Simkl authorization failed'),
                  ),
                );
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showAniListManualTokenDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.sheetColorOf(context, fallback: const Color(0xFF1F1F1F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter AniList Code or URL',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If the browser did not redirect automatically into Nivio, authorize on AniList and copy the authorization code (or full redirect URL) from your browser address bar and paste it below:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Paste code, redirect URL, or token...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(aniListAuthProvider.notifier).launchAuth();
            },
            child: const Text('Open Browser',
                style: TextStyle(color: Color(0xFF02A9FF))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final input = controller.text.trim();
              if (input.isNotEmpty) {
                Navigator.pop(ctx);
                final success = await ref
                    .read(aniListAuthProvider.notifier)
                    .loginWithInput(input);
                if (success) {
                  unawaited(
                    ref
                        .read(watchlistServiceProvider)
                        .importFromAnimeTracking(pushOfflineChanges: true)
                        .then((_) {
                      if (mounted) {
                        ref.read(watchlistRefreshProvider.notifier).refresh();
                      }
                    }),
                  );
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'AniList connected! Importing your anime library...'
                          : 'Failed to connect AniList. Check the code or token.'),
                      backgroundColor:
                          success ? Colors.green : Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  void _showMalManualCodeDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.sheetColorOf(context, fallback: const Color(0xFF1F1F1F)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Enter MyAnimeList Code',
            style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If the browser did not redirect automatically into Nivio, authorize on MAL and copy the authorization code (or full redirect URL) from your browser address bar (after ?code=...) and paste it below:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Paste code or redirect URL here...',
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.white10,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(malAuthProvider.notifier).launchAuth();
            },
            child: const Text('Open Browser',
                style: TextStyle(color: Color(0xFF2E51A2))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () async {
              final code = controller.text.trim();
              if (code.isNotEmpty) {
                Navigator.pop(ctx);
                final success = await ref
                    .read(malAuthProvider.notifier)
                    .loginWithCode(code);
                if (success) {
                  unawaited(
                    ref
                        .read(watchlistServiceProvider)
                        .importFromAnimeTracking(pushOfflineChanges: true)
                        .then((_) {
                      if (mounted) {
                        ref.read(watchlistRefreshProvider.notifier).refresh();
                      }
                    }),
                  );
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success
                          ? 'MyAnimeList connected! Importing your anime library...'
                          : 'Failed to connect MyAnimeList. Check the code.'),
                      backgroundColor:
                          success ? Colors.green : Colors.redAccent,
                    ),
                  );
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _syncAnimeWatchlistNow() async {
    final animeConnected =
        AnimeTrackingCoordinator.instance.hasAnyAccountConnected;
    final simklConnected = SimklAuthService.instance.isAuthenticated;

    if (!animeConnected && !simklConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please connect AniList, MyAnimeList, or Simkl first.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
      return;
    }

    if (_isSyncingAnime) return;
    setState(() => _isSyncingAnime = true);

    try {
      final watchlistService = ref.read(watchlistServiceProvider);

      // AniList/MAL: two-way anime sync (import + push offline changes).
      int animeCount = 0;
      if (animeConnected) {
        animeCount = await watchlistService.importFromAnimeTracking(
            pushOfflineChanges: true);
        ref.read(watchlistRefreshProvider.notifier).refresh();
      }

      // Simkl: two-way library sync (movies, TV & anime).
      int simklCount = 0;
      if (simklConnected) {
        simklCount =
            await watchlistService.importFromSimkl(pushOfflineChanges: true);
        ref.read(watchlistRefreshProvider.notifier).refresh();
      }

      if (mounted) {
        final parts = <String>[];
        if (animeConnected) parts.add('$animeCount anime entries');
        if (simklConnected) parts.add('$simklCount Simkl items');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Synced ${parts.join(' and ')}.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error syncing: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncingAnime = false);
      }
    }
  }

  String _formatLastAnimeSyncTime() {
    final lastSync = AnimeTrackingCoordinator.instance.lastSyncedAt;
    if (lastSync == null) return 'Never';
    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(lastSync);
  }
}


class _TrackingAccountCard extends StatefulWidget {
  const _TrackingAccountCard({
    super.key,
    required this.title,
    required this.description,
    required this.username,
    required this.avatarUrl,
    required this.connected,
    required this.brand,
    required this.logo,
    required this.manualLabel,
    required this.onConnect,
    required this.onManualEntry,
    required this.onDisconnect,
  });

  final String title;
  final String description;
  final String? username;
  final String? avatarUrl;
  final bool connected;
  final Color brand;
  final Widget logo;
  final String manualLabel;
  final VoidCallback onConnect;
  final VoidCallback onManualEntry;
  final VoidCallback onDisconnect;

  @override
  State<_TrackingAccountCard> createState() => _TrackingAccountCardState();
}

class _TrackingAccountCardState extends State<_TrackingAccountCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero : const Duration(milliseconds: 280);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.alphaBlend(widget.brand.withValues(alpha: .24), colors.surface), colors.surface],
        )),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              expanded: _expanded,
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                leading: widget.avatarUrl?.isNotEmpty == true
                    ? CircleAvatar(backgroundImage: avatarArtworkImage(context, widget.avatarUrl!, 40))
                    : widget.logo,
                title: Text(widget.title, style: theme.textTheme.titleMedium),
                subtitle: Text(widget.connected ? '@${widget.username ?? widget.title}' : 'Not connected',
                  style: TextStyle(color: colors.onSurfaceVariant)),
                trailing: AnimatedRotation(
                  turns: _expanded ? .5 : 0, duration: duration, curve: Curves.easeInOutCubic,
                  child: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                onTap: () => setState(() => _expanded = !_expanded),
              ),
            ),
            AnimatedSize(
              alignment: Alignment.topCenter,
              duration: duration,
              curve: Curves.easeInOutCubic,
              child: _expanded ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 13),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Divider(height: 14),
                    Text(widget.description, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 8),
                    if (widget.connected)
                      OutlinedButton(onPressed: widget.onDisconnect, child: const Text('Disconnect'))
                    else ...[
                      FilledButton(onPressed: widget.onConnect, child: const Text('Connect')),
                      TextButton(onPressed: widget.onManualEntry, child: Text(widget.manualLabel)),
                    ],
                  ],
                ),
              ) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlinkingDot extends StatefulWidget {
  final Color color;
  const _BlinkingDot({required this.color});

  @override
  State<_BlinkingDot> createState() => _BlinkingDotState();
}

class _BlinkingDotState extends State<_BlinkingDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_controller),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _HomeLayoutBottomSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  const _HomeLayoutBottomSheet({required this.scrollController});

  @override
  ConsumerState<_HomeLayoutBottomSheet> createState() => _HomeLayoutBottomSheetState();
}

class _HomeLayoutBottomSheetState extends ConsumerState<_HomeLayoutBottomSheet> {
  late List<String> _currentOrder;
  
  final Map<String, String> _sectionNames = {
    'latest_movies_ott': 'Latest OTT Movies',
    'popular_movies': 'All Time Popular',
    'trending_movies': 'Trending Now',
    'top_rated_movies': 'Top Rated Movies',
    'latest_tv_ott': 'Latest TV Releases',
    'popular_tv': 'Popular TV Shows',
    'trending_tv': 'Trending TV Shows',
    'latest_anime': 'Latest Anime Releases',
    'popular_anime': 'Popular Anime',
    'trending_anime': 'Trending Anime',
    'tamil': 'Tamil Picks',
    'telugu': 'Telugu Picks',
    'hindi': 'Hindi Picks',
    'korean': 'Korean Dramas',
    'malayalam': 'Malayalam Picks',
  };

  @override
  void initState() {
    super.initState();
    // Read the current order from provider immediately
    _currentOrder = List.from(ref.read(homeLayoutProvider));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Customize Layout',
                style: TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              TextButton(
                onPressed: () {
                  ref.read(homeLayoutProvider.notifier).updateOrder(_currentOrder);
                  Navigator.pop(context);
                },
                child: const Text('Done', style: TextStyle(color: NivioTheme.netflixRed)),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Text(
            'Drag and drop to reorder the content shelves on your home screen.',
            style: TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            scrollController: widget.scrollController,
            buildDefaultDragHandles: false, // We provide our own larger drag handle
            itemCount: _currentOrder.length,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex -= 1;
                final item = _currentOrder.removeAt(oldIndex);
                _currentOrder.insert(newIndex, item);
              });
            },
            itemBuilder: (context, index) {
              final sectionKey = _currentOrder[index];
              return ListTile(
                key: ValueKey(sectionKey),
                title: Text(
                  _sectionNames[sectionKey] ?? sectionKey,
                  style: const TextStyle(color: NivioTheme.netflixWhite),
                ),
                trailing: ReorderableDragStartListener(
                  index: index,
                  child: Container(
                    padding: const EdgeInsets.all(0.0),
                    color: Colors.transparent, // expand hit area
                    child: const Icon(Icons.drag_handle_rounded, color: Colors.white54, size: 28),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

}

class _SidebarCategoryTile extends StatefulWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SidebarCategoryTile({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SidebarCategoryTile> createState() => _SidebarCategoryTileState();
}

class _SidebarCategoryTileState extends State<_SidebarCategoryTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accentColor = NivioTheme.accentColorOf(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: FocusableTap(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(
              (widget.isSelected || !_isHovered) ? 0.0 : 4.0,
              0.0,
              0.0,
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            decoration: BoxDecoration(
              color: widget.isSelected
                  ? accentColor.withOpacity(0.18)
                  : (_isHovered
                      ? Colors.white.withOpacity(0.06)
                      : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: widget.isSelected
                    ? accentColor.withOpacity(0.55)
                    : (_isHovered
                        ? Colors.white.withOpacity(0.12)
                        : Colors.transparent),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  width: widget.isSelected ? 3.5 : (_isHovered ? 3.0 : 0.0),
                  height: widget.isSelected ? 18.0 : (_isHovered ? 12.0 : 0.0),
                  margin: EdgeInsets.only(
                    right: (widget.isSelected || _isHovered) ? 10.0 : 0.0,
                  ),
                  decoration: BoxDecoration(
                    color: widget.isSelected
                        ? accentColor
                        : accentColor.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: (widget.isSelected || _isHovered)
                        ? [
                            BoxShadow(
                              color: accentColor.withOpacity(0.4),
                              blurRadius: 6,
                            ),
                          ]
                        : null,
                  ),
                ),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    style: TextStyle(
                      color: widget.isSelected
                          ? NivioTheme.netflixWhite
                          : (_isHovered ? Colors.white : Colors.white60),
                      fontWeight: widget.isSelected
                          ? FontWeight.bold
                          : (_isHovered ? FontWeight.w600 : FontWeight.normal),
                      fontSize: 14.5,
                    ),
                    child: Text(widget.label),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingActionTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Color? titleColor;

  const _SettingActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.titleColor,
  });

  @override
  State<_SettingActionTile> createState() => _SettingActionTileState();
}

class _SettingActionTileState extends State<_SettingActionTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.useDesktopLayout) {
      final theme = Theme.of(context);
      return ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: Icon(widget.icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
        title: Text(widget.title, style: _mobileSettingTitle(theme, widget.titleColor)),
        subtitle: Text(widget.subtitle, style: _mobileSettingCaption(theme)),
        trailing: Icon(Icons.chevron_right_rounded, size: 19, color: theme.colorScheme.onSurfaceVariant),
        onTap: widget.onTap,
      );
    }
    final accentColor = NivioTheme.accentColorOf(context);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white.withOpacity(0.045)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isHovered
                ? Colors.white.withOpacity(0.08)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: ListTile(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            leading: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: _isHovered
                    ? accentColor.withOpacity(0.15)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                widget.icon,
                color: widget.titleColor ??
                    (_isHovered ? accentColor : NivioTheme.netflixWhite),
                size: 20,
              ),
            ),
            title: Text(
              widget.title,
              style: TextStyle(
                color: widget.titleColor ?? NivioTheme.netflixWhite,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              widget.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isHovered ? Colors.white70 : NivioTheme.netflixGrey,
                fontSize: 12,
              ),
            ),
            trailing: AnimatedSlide(
              offset: Offset(_isHovered ? 0.25 : 0.0, 0),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Icon(
                Icons.chevron_right_rounded,
                color: _isHovered ? accentColor : NivioTheme.netflixGrey,
                size: 22,
              ),
            ),
            onTap: widget.onTap,
          ),
        ),
      ),
    );
  }
}

class _SettingSwitchTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  const _SettingSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  State<_SettingSwitchTile> createState() => _SettingSwitchTileState();
}

class _SettingSwitchTileState extends State<_SettingSwitchTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    if (!AppPlatform.useDesktopLayout) {
      final theme = Theme.of(context);
      return SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        secondary: Icon(widget.icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
        title: Text(widget.title, style: _mobileSettingTitle(theme)),
        subtitle: Text(widget.subtitle, style: _mobileSettingCaption(theme)),
        value: widget.value,
        onChanged: widget.enabled ? widget.onChanged : null,
      );
    }
    final accentColor = Theme.of(context).colorScheme.primary;
    final enabled = widget.enabled;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: MouseRegion(
      onEnter: (_) => enabled ? setState(() => _isHovered = true) : null,
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white.withOpacity(0.045)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isHovered
                ? Colors.white.withOpacity(0.08)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: SwitchListTile(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          secondary: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _isHovered
                  ? accentColor.withOpacity(0.15)
                  : Colors.white.withOpacity(0.04),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              widget.icon,
              color: _isHovered ? accentColor : NivioTheme.netflixWhite,
              size: 20,
            ),
          ),
          title: Text(
            widget.title,
            style: const TextStyle(
              color: NivioTheme.netflixWhite,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            widget.subtitle,
            style: TextStyle(
              color: _isHovered ? Colors.white70 : NivioTheme.netflixGrey,
              fontSize: 12,
            ),
          ),
          value: widget.value,
          activeThumbColor: accentColor,
          onChanged: enabled ? widget.onChanged : null,
        ),
      ),
      ),
    );
  }
}

TextStyle _mobileSettingTitle(ThemeData theme, [Color? color]) => TextStyle(
  color: color ?? theme.colorScheme.onSurface,
  fontSize: 15,
  fontWeight: FontWeight.w600,
);

TextStyle _mobileSettingCaption(ThemeData theme) => TextStyle(
  color: theme.colorScheme.onSurfaceVariant,
  fontSize: 12,
  height: 1.4,
);

class _DesktopThemeCard extends StatefulWidget {
  final NivioAppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _DesktopThemeCard({
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_DesktopThemeCard> createState() => _DesktopThemeCardState();
}

class _DesktopThemeCardState extends State<_DesktopThemeCard> {
  bool _isHovered = false;

  Widget _buildSwatchDot(
    Color color, {
    required double size,
    bool hasGlow = false,
    Color? borderColor,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.25),
          width: 1,
        ),
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: color.withOpacity(0.55),
                  blurRadius: 5,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
    );
  }

  Widget _buildColorThemePreview(NivioAppTheme theme) {
    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topRight,
                radius: 1.2,
                colors: [
                  theme.primary.withOpacity(0.22),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: theme.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 20,
                    height: 3.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.primary.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Text(
                      theme.key.toUpperCase(),
                      style: TextStyle(
                        color: theme.primary,
                        fontSize: 7.5,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 4.5,
                ),
                decoration: BoxDecoration(
                  color: theme.surface.withOpacity(0.92),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.1),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSwatchDot(theme.primary, size: 11, hasGlow: true),
                    _buildSwatchDot(theme.secondary, size: 9),
                    _buildSwatchDot(
                      theme.surfaceContainer,
                      size: 8,
                      borderColor: Colors.white30,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPreview(NivioAppTheme theme, bool isSelected) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        gradient: theme.gradientColors.length >= 2
            ? LinearGradient(
                colors: theme.gradientColors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected
              ? theme.primary.withOpacity(0.55)
              : Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildColorThemePreview(theme),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final isSelected = widget.isSelected;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          transform: Matrix4.translationValues(0, _isHovered ? -3.0 : 0.0, 0),
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.primary.withOpacity(0.14)
                : (_isHovered
                    ? Colors.white.withOpacity(0.06)
                    : Colors.white.withOpacity(0.03)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? theme.primary
                  : (_isHovered
                      ? theme.primary.withOpacity(0.55)
                      : Colors.white.withOpacity(0.08)),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: (isSelected || _isHovered)
                ? [
                    BoxShadow(
                      color:
                          theme.primary.withOpacity(isSelected ? 0.22 : 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _buildPreview(theme, isSelected),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      theme.label,
                      style: TextStyle(
                        color: isSelected ? theme.primary : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w600,
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.check_circle_rounded,
                      color: theme.primary,
                      size: 15,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                theme.description,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9.5,
                  height: 1.15,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
