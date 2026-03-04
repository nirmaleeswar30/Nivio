import 'package:cached_network_image/cached_network_image.dart';
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
import 'package:nivio/services/episode_check_service.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

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
      loading: () => const Scaffold(
        backgroundColor: NivioTheme.netflixBlack,
        body: Center(
          child: CircularProgressIndicator(color: NivioTheme.netflixRed),
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
    final subtitlesEnabled = ref.watch(subtitlesEnabledProvider);
    final animationsEnabled = ref.watch(animationsEnabledProvider);
    final episodeCheckEnabled = ref.watch(episodeCheckEnabledProvider);
    final episodeFrequency = ref.watch(episodeCheckFrequencyProvider);

    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: Container(
        decoration: const BoxDecoration(
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
                  child: _buildProfileHeader(user),
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
              if (_matches('watchlist my list saved'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
                    child: _buildSectionCard(
                      title: 'Watchlist',
                      child: _buildWatchlistPreview(watchlist),
                    ),
                  ),
                ),
              if (_matches('activity history continue'))
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                    child: _buildSectionCard(
                      title: 'Recent Activity',
                      child: _buildRecentActivity(historyAsync),
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
                        if (_matches('subtitles captions'))
                          _buildSwitchTile(
                            icon: Icons.subtitles_outlined,
                            title: 'Subtitles',
                            subtitle: subtitlesEnabled ? 'Enabled' : 'Disabled',
                            value: subtitlesEnabled,
                            onChanged: (value) {
                              ref
                                  .read(subtitlesEnabledProvider.notifier)
                                  .toggle();
                            },
                          ),
                        if (_matches('animations motion'))
                          _buildSwitchTile(
                            icon: Icons.auto_awesome_rounded,
                            title: 'Animations',
                            subtitle: animationsEnabled
                                ? 'Enabled'
                                : 'Disabled',
                            value: animationsEnabled,
                            onChanged: (value) {
                              ref
                                  .read(animationsEnabledProvider.notifier)
                                  .toggle();
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
                    title: 'Content Feed',
                    child: Column(
                      children: [
                        if (_matches('anime language'))
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
                        if (episodeCheckEnabled &&
                            _matches('frequency check schedule'))
                          _buildActionTile(
                            icon: Icons.schedule_rounded,
                            title: 'Check Frequency',
                            subtitle: _frequencyLabel(episodeFrequency),
                            onTap: _showFrequencyDialog,
                          ),
                        if (_matches('new episodes inbox'))
                          _buildActionTile(
                            icon: Icons.notifications_none_rounded,
                            title: 'Open New Episodes',
                            subtitle: 'View recently detected episodes',
                            onTap: () => context.push('/new-episodes'),
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
                        if (_matches('sign out logout'))
                          _buildActionTile(
                            icon: Icons.logout_rounded,
                            title: user.isAnonymous
                                ? 'Exit Guest Mode'
                                : 'Sign Out',
                            subtitle: user.email ?? 'Current session',
                            titleColor: NivioTheme.netflixRed,
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
    final subtitle = user.isAnonymous
        ? 'Guest mode'
        : (user.email ?? 'Signed in');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: NivioTheme.netflixDarkGrey,
            backgroundImage: (avatarUrl != null && avatarUrl.isNotEmpty)
                ? CachedNetworkImageProvider(avatarUrl)
                : null,
            child: (avatarUrl == null || avatarUrl.isEmpty)
                ? const PhosphorIcon(
                    PhosphorIconsRegular.userCircle,
                    color: NivioTheme.netflixWhite,
                    size: 24,
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: NivioTheme.netflixLightGrey,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
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
          borderSide: const BorderSide(color: NivioTheme.netflixRed),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: NivioTheme.netflixLightGrey,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: NivioTheme.netflixWhite,
              fontWeight: FontWeight.w700,
              fontSize: 19,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: NivioTheme.netflixWhite,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
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
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
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
        style: const TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
      ),
      trailing: const Icon(
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
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      leading: Icon(icon, color: NivioTheme.netflixWhite, size: 22),
      title: Text(
        title,
        style: const TextStyle(
          color: NivioTheme.netflixWhite,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: NivioTheme.netflixGrey, fontSize: 12),
      ),
      trailing: Switch(
        value: value,
        activeThumbColor: NivioTheme.netflixRed,
        onChanged: onChanged,
      ),
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
                          child: const Icon(
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
          onPressed: () => context.push('/watchlist'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: const Icon(Icons.bookmark_rounded, size: 18),
          label: const Text('Open full watchlist'),
        ),
      ],
    );
  }

  Widget _buildRecentActivity(AsyncValue<List<dynamic>> historyAsync) {
    return historyAsync.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(14),
        child: Center(
          child: CircularProgressIndicator(
            color: NivioTheme.netflixRed,
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 2),
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
                style: const TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: NivioTheme.netflixGrey,
                  fontSize: 12,
                ),
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

  String _frequencyLabel(int value) {
    switch (value) {
      case 12:
        return 'Every 12 hours';
      case 24:
        return 'Daily';
      case 48:
        return 'Every 2 days';
      default:
        return 'Every $value hours';
    }
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
                        ? NivioTheme.netflixRed
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    '${speed}x',
                    style: const TextStyle(color: NivioTheme.netflixWhite),
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
                        ? NivioTheme.netflixRed
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    _qualityLabel(option),
                    style: const TextStyle(color: NivioTheme.netflixWhite),
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

  Future<void> _showFrequencyDialog() async {
    const values = [12, 24, 48];
    final current = ref.read(episodeCheckFrequencyProvider);

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
                  'Episode Check Frequency',
                  style: TextStyle(
                    color: NivioTheme.netflixWhite,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...values.map((value) {
                final isSelected = value == current;
                return ListTile(
                  leading: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected
                        ? NivioTheme.netflixRed
                        : NivioTheme.netflixGrey,
                  ),
                  title: Text(
                    _frequencyLabel(value),
                    style: const TextStyle(color: NivioTheme.netflixWhite),
                  ),
                  onTap: () {
                    ref
                        .read(episodeCheckFrequencyProvider.notifier)
                        .setFrequency(value);
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

  Future<void> _checkNow() async {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return const AlertDialog(
          backgroundColor: NivioTheme.netflixDarkGrey,
          content: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: NivioTheme.netflixRed,
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
        backgroundColor: NivioTheme.netflixRed,
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
              child: const Text(
                'Clear',
                style: TextStyle(color: NivioTheme.netflixRed),
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
      const SnackBar(
        content: Text('Watch history cleared'),
        backgroundColor: NivioTheme.netflixRed,
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
              child: const Text(
                'Sign Out',
                style: TextStyle(color: NivioTheme.netflixRed),
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
}
