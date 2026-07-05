import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/auth_provider.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/watchlist_provider.dart';
import 'package:nivio/widgets/changelog_dialog.dart';
import 'package:nivio/providers/changelog_provider.dart';
import 'package:nivio/providers/home_layout_provider.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/services/github_release_update_service.dart';
import 'package:nivio/services/scrapers/animepahe/cloudflare_bypass_service.dart';
import 'package:nivio/services/scrapers/newtv/newtv_bypass_service.dart';
import 'package:nivio/services/api_status_service.dart';
import 'package:nivio/services/shorebird_update_service.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  void _handleBackNavigation() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/home');
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matches(String title, [String subtitle = '']) {
    if (_query.isEmpty) return true;
    final source = '$title $subtitle'.toLowerCase();
    return source.contains(_query.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
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
    final watchlist = ref.watch(watchlistProvider);
    final historyAsync = ref.watch(watchHistoryProvider);
    final languagePrefs = ref.watch(languagePreferencesProvider);
    final playbackSpeed = ref.watch(playbackSpeedProvider);
    final videoQuality = ref.watch(videoQualityProvider);
    final preferredAudio = ref.watch(preferredAudioLanguageProvider);
    final preferredSubtitle = ref.watch(preferredSubtitleLanguageProvider);
    final episodeCheckEnabled = ref.watch(episodeCheckEnabledProvider);

    final appAccentKey = ref.watch(appAccentColorProvider);

    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151922), NivioTheme.netflixBlack],
          ),
        ),
        child: SafeArea(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    children: [
                      Align(
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

                      _buildProfileHeader(user),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSearchField(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: historyAsync.when(
                    loading: () => _buildStatsPlaceholder(),
                    error: (error, stackTrace) => _buildStatsPlaceholder(),
                    data: (history) => _buildStatsRow(
                      watchlistCount: watchlist.length,
                      historyCount: history.length,
                      completedCount: history
                          .where((entry) => entry.isCompleted)
                          .length,
                    ),
                  ),
                ),
              ),
              if (_query.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _buildSearchResultsCard(
                      user: user,
                      languagePrefs: languagePrefs,
                      playbackSpeed: playbackSpeed,
                      videoQuality: videoQuality,
                      preferredAudio: preferredAudio,
                      preferredSubtitle: preferredSubtitle,
                      episodeCheckEnabled: episodeCheckEnabled,

                      appAccentKey: appAccentKey,
                    ),
                  ),
                ),
              if (_matches('activity history continue'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: _buildSectionCard(
                      title: 'Recent Activity',
                      initiallyExpanded: true,
                      child: _buildRecentActivity(historyAsync),
                    ),
                  ),
                ),
              if (_matches('watchlist my list saved') && watchlist.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _buildSectionCard(
                      title: 'Watchlist',
                      child: _buildWatchlistPreview(watchlist),
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'Playback',
                    child: Column(
                      children: [
                        if (_matches('playback speed'))
                          _buildActionTile(
                            icon: Icons.speed_rounded,
                            title: 'Default Playback Speed',
                            subtitle: '${playbackSpeed}x',
                            onTap: _showPlaybackSpeedDialog,
                          ),
                        if (_matches('video quality resolution'))
                          _buildActionTile(
                            icon: Icons.high_quality_rounded,
                            title: 'Preferred Video Quality',
                            subtitle: _qualityLabel(videoQuality),
                            onTap: _showVideoQualityDialog,
                          ),
                        if (_matches('preferred default audio language'))
                          _buildActionTile(
                            icon: Icons.audiotrack_rounded,
                            title: 'Preferred Audio Language',
                            subtitle: preferredAudio,
                            onTap: _showAudioLanguageDialog,
                          ),
                        if (_matches('preferred default subtitle language'))
                          _buildActionTile(
                            icon: Icons.subtitles_rounded,
                            title: 'Preferred Subtitle Language',
                            subtitle: preferredSubtitle,
                            onTap: _showSubtitleLanguageDialog,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'Downloads',
                    child: Column(
                      children: [
                        if (_matches('preferred download audio language'))
                          _buildActionTile(
                            icon: Icons.audio_file_rounded,
                            title: 'Preferred Download Audio',
                            subtitle: ref.watch(preferredDownloadAudioLanguageProvider),
                            onTap: _showDownloadAudioLanguageDialog,
                          ),
                        if (_matches('preferred download subtitle language'))
                          _buildActionTile(
                            icon: Icons.subtitles_rounded,
                            title: 'Preferred Download Subtitle',
                            subtitle: ref.watch(preferredDownloadSubtitleLanguageProvider),
                            onTap: _showDownloadSubtitleLanguageDialog,
                          ),
                        if (_matches('download concurrency parallel connections'))
                          _buildActionTile(
                            icon: Icons.speed_rounded,
                            title: 'Parallel Download Connections',
                            subtitle: '${ref.watch(downloadConcurrencyProvider)}',
                            onTap: _showDownloadConcurrencyDialog,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'Content Feed',
                    child: Column(
                      children: [
                        if (_matches('customize home layout order arrange shelves'))
                          _buildActionTile(
                            icon: Icons.dashboard_customize_rounded,
                            title: 'Customize Home Layout',
                            subtitle: 'Rearrange the order of shelves on the home screen',
                            onTap: () => _showHomeLayoutDialog(context),
                          ),
                        if (_matches('anime language audio sub dub subbed dubbed')) ...[
                          _buildActionTile(
                            icon: Icons.record_voice_over_rounded,
                            title: 'Preferred Anime Audio',
                            subtitle: languagePrefs.animePreferredAudio == 'sub' ? 'Subbed' : 'Dubbed',
                            onTap: _showAnimeAudioDialog,
                          ),
                          _buildSwitchTile(
                            icon: Icons.animation_rounded,
                            title: 'Anime',
                            subtitle: 'Show anime rows on home',
                            value: languagePrefs.showAnime,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleAnime(value);
                            },
                          ),
                        ],
                        if (_matches('tamil language'))
                          _buildSwitchTile(
                            icon: Icons.movie_filter_rounded,
                            title: 'Tamil',
                            subtitle: 'Show Tamil rows on home',
                            value: languagePrefs.showTamil,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleTamil(value);
                            },
                          ),
                        if (_matches('telugu language'))
                          _buildSwitchTile(
                            icon: Icons.movie_creation_outlined,
                            title: 'Telugu',
                            subtitle: 'Show Telugu rows on home',
                            value: languagePrefs.showTelugu,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleTelugu(value);
                            },
                          ),
                        if (_matches('hindi language'))
                          _buildSwitchTile(
                            icon: Icons.theaters_rounded,
                            title: 'Hindi',
                            subtitle: 'Show Hindi rows on home',
                            value: languagePrefs.showHindi,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleHindi(value);
                            },
                          ),
                        if (_matches('korean language kdrama'))
                          _buildSwitchTile(
                            icon: Icons.live_tv_rounded,
                            title: 'Korean',
                            subtitle: 'Show Korean rows on home',
                            value: languagePrefs.showKorean,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleKorean(value);
                            },
                          ),
                        if (_matches('malayalam language'))
                          _buildSwitchTile(
                            icon: Icons.movie_outlined,
                            title: 'Malayalam',
                            subtitle: 'Show Malayalam rows on home',
                            value: languagePrefs.showMalayalam,
                            onChanged: (value) {
                              ref
                                  .read(languagePreferencesProvider.notifier)
                                  .toggleMalayalam(value);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'Episode Alerts',
                    child: Column(
                      children: [
                        if (_matches('alerts notifications'))
                          _buildSwitchTile(
                            icon: Icons.notifications_active_outlined,
                            title: 'New Episode Alerts',
                            subtitle: episodeCheckEnabled
                                ? 'Enabled'
                                : 'Disabled',
                            value: episodeCheckEnabled,
                            onChanged: (value) {
                              ref
                                  .read(episodeCheckEnabledProvider.notifier)
                                  .setEnabled(value);
                            },
                          ),

                        if (_matches('new episodes inbox'))
                          _buildActionTile(
                            icon: Icons.notifications_none_rounded,
                            title: 'Open New Episodes',
                            subtitle: 'View recently detected episodes',
                            onTap: () => context.go('/library'),
                          ),
                        if (_matches('check now refresh'))
                          _buildActionTile(
                            icon: Icons.sync_rounded,
                            title: 'Check Now',
                            subtitle: 'Manually check for newly aired episodes',
                            onTap: _checkNow,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'App & Updates',
                    child: Column(
                      children: [
                        if (_matches('theme color accent main app'))
                          _buildActionTile(
                            icon: Icons.palette_outlined,
                            title: 'Theme Color',
                            subtitle: appAccentLabelFromKey(appAccentKey),
                            onTap: _showThemeColorDialog,
                          ),
                        if (_matches('update app version release github'))
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
                        if (_matches('update github release app install apk'))
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
                        if (_matches('changelog whats new release notes version features'))
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
                        if (_matches('sponsor donate support fund'))
                          _buildActionTile(
                            icon: Icons.favorite_rounded,
                            title: 'Sponsor Nivio',
                            subtitle: 'Support the development on GitHub',
                            titleColor: Colors.pinkAccent,
                            onTap: () {
                              final sponsorUrl = dotenv.env['GITHUB_SPONSOR_URL'] ?? 'https://github.com/sponsors/nirmaleeswar30';
                              launchUrl(
                                Uri.parse(sponsorUrl),
                                mode: LaunchMode.externalApplication,
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),

                            SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: _buildSectionCard(
                    title: 'Data & Account',
                    child: Column(
                      children: [
                        if (_matches('clear history data'))
                          _buildActionTile(
                            icon: Icons.delete_sweep_outlined,
                            title: 'Clear Watch History',
                            subtitle: 'Remove all watch progress and activity',
                            onTap: _showClearHistoryDialog,
                          ),
                        if (_matches('clear cache data storage'))
                          _buildActionTile(
                            icon: Icons.cleaning_services_outlined,
                            title: 'Clear Cache',
                            subtitle: 'Clear cached API and image metadata',
                            onTap: _showClearCacheDialog,
                          ),
                        if (_matches('sign out logout'))
                          _buildActionTile(
                            icon: Icons.logout_rounded,
                            title: user.isAnonymous
                                ? 'Exit Guest Mode'
                                : 'Sign Out',
                            subtitle: user.email ?? 'Current session',
                            titleColor: NivioTheme.accentColorOf(context),
                            onTap: _showSignOutDialog,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader(User user) {
    final avatarUrl = user.photoURL;
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
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
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
              final cfBypass = ref.watch(cloudflareBypassProvider);
              final newTvBypass = ref.watch(newTvBypassProvider);
              final apiStatus = ref.watch(apiStatusProvider);
              
              final isBypassing = cfBypass.isBypassing || newTvBypass.isBypassing;
              final isReady = cfBypass.isReady && newTvBypass.isReady;
              final isApiDown = apiStatus.anilistStatus == ApiServiceStatus.offline || apiStatus.newTvStatus == ApiServiceStatus.offline;
              
              Color dotColor = Colors.grey;
              String statusText = 'Disconnected';
              
              if (isApiDown) {
                dotColor = Colors.redAccent;
                if (apiStatus.anilistStatus == ApiServiceStatus.offline && apiStatus.newTvStatus == ApiServiceStatus.offline) {
                  statusText = 'AniList & NewTV Offline';
                } else if (apiStatus.anilistStatus == ApiServiceStatus.offline) {
                  statusText = 'AniList Offline';
                } else {
                  statusText = 'NewTV Offline';
                }
              } else if (isBypassing) {
                dotColor = Colors.orangeAccent;
                statusText = 'Bypassing Cloudflare...';
              } else if (isReady) {
                dotColor = Colors.greenAccent;
                statusText = 'Scraping engines ready';
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
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value.trim()),
      style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search profile settings...',
        prefixIcon: Icon(
          Icons.search_rounded,
          color: Colors.white.withValues(alpha: 0.75),
        ),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
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
          backgroundColor: const Color(0xFF1F1F1F),
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
    
    return Column(
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
    );
  }

  Widget _buildSearchResultsCard({
    required User user,
    required LanguagePreferences languagePrefs,
    required double playbackSpeed,
    required String videoQuality,
    required String preferredAudio,
    required String preferredSubtitle,
    required bool episodeCheckEnabled,

    required String appAccentKey,
  }) {
    final results = <Widget>[];

    if (_matches('playback speed')) {
      results.add(
        _buildActionTile(
          icon: Icons.speed_rounded,
          title: 'Default Playback Speed',
          subtitle: '${playbackSpeed}x',
          onTap: _showPlaybackSpeedDialog,
        ),
      );
    }
    if (_matches('video quality resolution')) {
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
    if (_matches('anime language audio sub dub subbed dubbed')) {
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
    if (_matches('preferred download audio language')) {
      results.add(
        _buildActionTile(
          icon: Icons.audio_file_rounded,
          title: 'Preferred Download Audio',
          subtitle: ref.watch(preferredDownloadAudioLanguageProvider),
          onTap: _showDownloadAudioLanguageDialog,
        ),
      );
    }
    if (_matches('preferred download subtitle language')) {
      results.add(
        _buildActionTile(
          icon: Icons.subtitles_rounded,
          title: 'Preferred Download Subtitle',
          subtitle: ref.watch(preferredDownloadSubtitleLanguageProvider),
          onTap: _showDownloadSubtitleLanguageDialog,
        ),
      );
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
    if (_matches('alerts notifications')) {
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
    if (_matches('new episodes inbox')) {
      results.add(
        _buildActionTile(
          icon: Icons.notifications_none_rounded,
          title: 'Open New Episodes',
          subtitle: 'View recently detected episodes',
          onTap: () => context.go('/library'),
        ),
      );
    }
    if (_matches('theme color accent main app')) {
      results.add(
        _buildActionTile(
          icon: Icons.palette_outlined,
          title: 'Theme Color',
          subtitle: appAccentLabelFromKey(appAccentKey),
          onTap: _showThemeColorDialog,
        ),
      );
    }
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
    if (_matches('clear history data')) {
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

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? titleColor,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(
        icon,
        color: titleColor ?? NivioTheme.netflixWhite,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor ?? NivioTheme.netflixWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: NivioTheme.netflixGrey,
      ),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final accentColor = Theme.of(context).colorScheme.primary;

    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Icon(icon, color: NivioTheme.netflixWhite, size: 22),
      title: Text(
        title,
        style: TextStyle(
          color: NivioTheme.netflixWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
      ),
      value: value,
      activeThumbColor: accentColor,
      onChanged: onChanged,
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

    final tmdbService = ref.watch(tmdbServiceProvider);
    final preview = watchlist.take(8).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 122,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: preview.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = preview[index];
              return GestureDetector(
                onTap: () =>
                    context.push('/media/${item.id}?type=${item.mediaType}'),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.posterPath == null
                      ? Container(
                          width: 78,
                          color: NivioTheme.netflixDarkGrey,
                          child: Icon(
                            Icons.movie_outlined,
                            color: NivioTheme.netflixGrey,
                          ),
                        )
                      : CachedNetworkImage(
                          imageUrl: tmdbService.getPosterUrl(item.posterPath),
                          width: 78,
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

        final tmdb = ref.watch(tmdbServiceProvider);
        final sorted = [...history]
          ..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
        final preview = sorted.take(4).toList();

        return Column(
          children: preview.map((entry) {
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
                  child:
                      (entry.posterPath != null && entry.posterPath!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: tmdb.getPosterUrl(entry.posterPath),
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



  Future<void> _showCustomHexDialog() async {
    final current = ref.read(appAccentColorProvider);
    String currentHex = current.startsWith('#') ? current.substring(1) : '';
    final TextEditingController hexController =
        TextEditingController(text: currentHex);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
          title: const Text(
            'Custom Hex Color',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: hexController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              prefixText: '#',
              prefixStyle: TextStyle(color: Colors.white70),
              hintText: 'RRGGBB',
              hintStyle: TextStyle(color: Colors.white38),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: NivioTheme.netflixWhite),
              ),
            ),
            maxLength: 6,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () async {
                final hex = hexController.text.trim().toUpperCase();
                if (hex.length == 6) {
                  // Basic validation
                  final RegExp hexRegex = RegExp(r'^[0-9A-F]{6}$');
                  if (hexRegex.hasMatch(hex)) {
                    await ref
                        .read(appAccentColorProvider.notifier)
                        .setAccentColor('#$hex');
                    if (context.mounted) Navigator.pop(context);
                  }
                }
              },
              child: const Text(
                'Save',
                style: TextStyle(color: NivioTheme.netflixWhite),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showHomeLayoutDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: NivioTheme.netflixDarkGrey,
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

  Future<void> _showPlaybackSpeedDialog() async {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    final currentSpeed = ref.read(playbackSpeedProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Playback Speed',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...speeds.map((speed) {
                final isSelected = speed == currentSpeed;
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
                    '${speed}x',
                    style: TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  onTap: () {
                    ref.read(playbackSpeedProvider.notifier).setSpeed(speed);
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

  Future<void> _showVideoQualityDialog() async {
    const options = ['auto', '2160p', '1080p', '720p', '480p'];
    final current = ref.read(videoQualityProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
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



  Future<void> _showThemeColorDialog() async {
    final current = ref.read(appAccentColorProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(
                title: Text(
                  'Theme Color',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...appAccentOptions.map((option) {
                final isSelected = option.key == current;
                return ListTile(
                  leading: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: option.color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected
                            ? NivioTheme.netflixWhite
                            : Colors.white24,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                  title: Text(
                    option.label,
                    style: TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  trailing: isSelected
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: NivioTheme.accentColorOf(context),
                        )
                      : null,
                  onTap: () async {
                    await ref
                        .read(appAccentColorProvider.notifier)
                        .setAccentColor(option.key);
                    if (sheetContext.mounted) {
                      Navigator.pop(sheetContext);
                    }
                  },
                );
              }),
              ListTile(
                leading: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: current.startsWith('#')
                        ? appAccentColorFromKey(current)
                        : Colors.grey[800],
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: current.startsWith('#')
                          ? NivioTheme.netflixWhite
                          : Colors.white24,
                      width: current.startsWith('#') ? 2 : 1,
                    ),
                  ),
                ),
                title: const Text(
                  'Custom Hex...',
                  style: TextStyle(color: NivioTheme.netflixWhite),
                ),
                trailing: current.startsWith('#')
                    ? Icon(
                        Icons.check_circle_rounded,
                        color: NivioTheme.accentColorOf(context),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showCustomHexDialog();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _checkNow() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
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
          backgroundColor: NivioTheme.netflixDarkGrey,
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
        content: Text('Watch history cleared'),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }

  Future<void> _showClearCacheDialog() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
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
    
    // Clear WebView cache (used by scrapers)
    try {
      await InAppWebViewController.clearAllCache();
    } catch (e) {
      debugPrint('Error clearing WebView cache: $e');
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Cache cleared'),
        backgroundColor: NivioTheme.accentColorOf(context),
      ),
    );
  }

  Future<void> _showSignOutDialog() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
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
        return '$baseVersion Ã¢â‚¬Â¢ patch: base';
      }
      return '$baseVersion Ã¢â‚¬Â¢ patch: $patch';
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
          backgroundColor: NivioTheme.netflixDarkGrey,
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
              await GitHubReleaseUpdateService.openReleasePage(result.releaseUrl);
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
      backgroundColor: NivioTheme.netflixDarkGrey,
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
      backgroundColor: NivioTheme.netflixDarkGrey,
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

  Future<void> _showDownloadAudioLanguageDialog() async {
    final current = ref.read(preferredDownloadAudioLanguageProvider);
    final options = ['Original', 'English', 'Japanese', 'Hindi', 'Tamil', 'Telugu', 'Spanish', 'French', 'Korean', 'German', 'Italian'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
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
                'Preferred Download Audio',
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
                      ref.read(preferredDownloadAudioLanguageProvider.notifier).setLanguage(option);
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

  Future<void> _showDownloadSubtitleLanguageDialog() async {
    final current = ref.read(preferredDownloadSubtitleLanguageProvider);
    final options = ['Auto', 'Off', 'English', 'Japanese', 'Hindi', 'Tamil', 'Telugu', 'Spanish', 'French', 'Korean', 'German', 'Italian'];

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
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
                'Preferred Download Subtitle',
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
                      ref.read(preferredDownloadSubtitleLanguageProvider.notifier).setLanguage(option);
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
      backgroundColor: NivioTheme.netflixDarkGrey,
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
    'popular_movies': 'All Time Popular',
    'trending_movies': 'Trending Now',
    'top_rated_movies': 'Top Rated Movies',
    'popular_tv': 'Popular TV Shows',
    'trending_tv': 'Trending TV Shows',
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



