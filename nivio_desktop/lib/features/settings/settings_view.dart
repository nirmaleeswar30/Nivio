import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_flutter/lucide_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/config/app_environment.dart';
import '../../core/services/desktop_cache_service.dart';
import '../../core/services/desktop_update_service.dart';
import '../../shared/theme/index.dart';
import '../../shared/widgets/dialogs/changelog_dialog.dart';
import '../../shared/widgets/dialogs/update_dialog.dart';
import '../../shared/widgets/feedback/error_view.dart';
import '../../shared/widgets/feedback/loading_view.dart';
import '../auth/desktop_cloud_sync_service.dart';
import '../history/desktop_watch_history_repository.dart';
import '../home/controllers/home_controller.dart';
import '../library/services/episode_tracking_service.dart';
import '../library/services/library_persistence.dart';
import '../live_tv/services/iptv_service.dart';
import '../party/services/watch_party_identity.dart';
import '../party/services/watch_party_supabase_config.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    this.onBack,
    this.embedded = false,
    this.onHomeLayoutChanged,
    this.sectionFilter,
    this.query = '',
    this.showHeader = true,
  });

  final VoidCallback? onBack;
  final bool embedded;
  final VoidCallback? onHomeLayoutChanged;
  final String? sectionFilter;
  final String query;
  final bool showHeader;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final _controller = SettingsController();
  int _selectedCategoryIndex = 0;

  static const List<_SettingsCategory> _categories = [
    _SettingsCategory('playback', 'Playback', LucideIcons.play),
    _SettingsCategory(
      'subtitles',
      'Subtitle Appearance',
      LucideIcons.subtitles,
    ),
    _SettingsCategory('downloads', 'Downloads', LucideIcons.download),
    _SettingsCategory('home', 'Content Feed', LucideIcons.rows3),
    _SettingsCategory('episodes', 'Episode Alerts', LucideIcons.bell),
    _SettingsCategory('app', 'App & Updates', LucideIcons.info),
    _SettingsCategory('data', 'Data & Account', LucideIcons.database),
    _SettingsCategory('offline', 'Offline & Cache', LucideIcons.hardDrive),
  ];

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showHomeLayoutDialog() async {
    final nextOrder = await showDialog<List<String>>(
      context: context,
      builder: (context) => _HomeLayoutDialog(
        sectionOrder: _controller.state.settings.homeSectionOrder,
      ),
    );
    if (nextOrder == null) return;
    await _controller.updateStringList(
      SettingsKeys.homeSectionOrder,
      nextOrder,
    );
    widget.onHomeLayoutChanged?.call();
  }

  Future<void> _runEpisodeCheckNow() async {
    final messenger = ScaffoldMessenger.of(context);
    final count = await _controller.checkForNewEpisodesNow();
    if (!mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Episode check complete: $count new found')),
    );
  }

  Future<void> _resetSubtitleDelays() async {
    final message = await _controller.clearSubtitleDelaySettings();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runSettingsAction(Future<String> Function() action) async {
    final message = await action();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setOfflineMode(bool enabled) async {
    await _controller.setOfflineMode(enabled);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? 'Offline mode enabled. Desktop will prefer local data.'
              : 'Offline mode disabled.',
        ),
      ),
    );
  }

  Future<void> _updateHomeFeedString(String key, String value) async {
    await _controller.updateString(key, value);
    widget.onHomeLayoutChanged?.call();
  }

  Future<void> _updateHomeFeedBool(String key, bool value) async {
    await _controller.updateBool(key, value);
    widget.onHomeLayoutChanged?.call();
  }

  Future<void> _showChangelog() async {
    await _controller.markChangelogSeen();
    if (!mounted) return;
    final release = await DesktopUpdateService.checkFullRelease();
    if (!mounted) return;
    final releaseNotes = release.releaseNotes?.trim();
    final titleVersion = release.latestVersion.trim().isNotEmpty
        ? release.latestVersion
        : _controller.state.appVersion;
    await showDialog<void>(
      context: context,
      builder: (context) => ChangelogDialog(
        title: 'What\'s New in $titleVersion',
        changes: releaseNotes?.isNotEmpty == true
            ? releaseNotes!
            : _desktopChangelog(),
      ),
    );
  }

  Future<void> _checkForUpdates() async {
    final result = await _controller.checkForUpdates();
    if (!mounted) return;

    final fullRelease = result.fullRelease;
    if (fullRelease.hasUpdate) {
      await showDialog<void>(
        context: context,
        builder: (context) => UpdateDialog(
          currentVersion: fullRelease.installedVersion,
          latestVersion: fullRelease.latestVersion,
          releaseNotes: fullRelease.releaseNotes?.trim().isNotEmpty == true
              ? fullRelease.releaseNotes!
              : 'A new Linux desktop release is available.',
          onLater: () => Navigator.of(context).maybePop(),
          onInstall: () {
            Navigator.of(context).maybePop();
            unawaited(DesktopUpdateService.openInstallTarget(fullRelease));
          },
        ),
      );
      return;
    }

    final patch = result.patch;
    if (patch.action == DesktopPatchUpdateAction.downloaded ||
        patch.action == DesktopPatchUpdateAction.restartRequired) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restart Required'),
          content: Text(patch.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Later'),
            ),
          ],
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    final state = _controller.state;
    if (state.isLoading) {
      return const LoadingView(
        title: 'Loading Settings',
        message: 'Reading local preferences and environment status.',
      );
    }
    if (state.fatalError != null) {
      return ErrorView(
        title: 'Settings unavailable',
        message: state.fatalError!,
        onRetry: _controller.load,
      );
    }

    final visibleQuery = widget.query.trim().toLowerCase();
    final providedSection = widget.sectionFilter?.trim().toLowerCase();
    final selectedSection = widget.embedded
        ? providedSection
        : providedSection ??
              (visibleQuery.isEmpty
                  ? _categories[_selectedCategoryIndex].id
                  : null);
    final sections = _buildSettingsSections(
      state,
      visibleSection: selectedSection,
      visibleQuery: visibleQuery,
    );

    final children = <Widget>[
      if (widget.embedded && widget.showHeader) ...[
        _SettingsHeader(onBack: widget.onBack),
        const SizedBox(height: AppSpacing.xxl),
      ],
      ...sections,
      if (visibleQuery.isNotEmpty && sections.isEmpty)
        const _SettingsEmptySearch(),
      const SizedBox(height: AppSpacing.massive),
    ];

    if (widget.embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.surface, AppColors.background],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          final title = visibleQuery.isEmpty
              ? _categories[_selectedCategoryIndex].label
              : 'Search Results';
          final horizontalPadding = desktop ? AppSpacing.huge : AppSpacing.lg;
          final contentWidth = desktop ? 1080.0 : double.infinity;

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  AppSpacing.lg,
                  horizontalPadding,
                  AppSpacing.massive,
                ),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: contentWidth),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SettingsHeader(onBack: widget.onBack),
                          const SizedBox(height: AppSpacing.xxl),
                          _SettingsCategoryWrap(
                            categories: _categories,
                            selectedIndex: _selectedCategoryIndex,
                            onSelected: (index) {
                              setState(() => _selectedCategoryIndex = index);
                            },
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          Text(title, style: AppTypography.pageTitle),
                          const SizedBox(height: AppSpacing.lg),
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            child: _SettingsContentCard(
                              key: ValueKey('$title-$selectedSection'),
                              children: children,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _buildSettingsSections(
    SettingsState state, {
    required String? visibleSection,
    required String visibleQuery,
  }) {
    bool showSection(
      String id,
      String title, [
      List<String> keywords = const [],
    ]) {
      if (visibleSection != null && visibleSection.isNotEmpty) {
        return id == visibleSection;
      }
      if (visibleQuery.isEmpty) return true;
      final haystack = [id, title, ...keywords].join(' ').toLowerCase();
      return haystack.contains(visibleQuery);
    }

    return [
      if (showSection('playback', 'Playback', [
        'speed',
        'quality',
        'audio',
        'subtitle',
        'autoplay',
        'resume',
        'debanding',
      ]))
        _Section(
          title: 'Playback',
          icon: LucideIcons.play,
          error: state.sectionErrors['playback'],
          child: Column(
            children: [
              _ChoiceTile(
                title: 'Default Playback Speed',
                value: state.settings.playbackSpeed.toString(),
                options: SettingsDefaults.playbackSpeeds
                    .map((speed) => speed.toString())
                    .toList(),
                onChanged: (value) => _controller.updateDouble(
                  SettingsKeys.playbackSpeed,
                  double.parse(value),
                ),
              ),
              _ChoiceTile(
                title: 'Preferred Video Quality',
                value: state.settings.videoQuality,
                options: SettingsDefaults.videoQualities,
                onChanged: (value) =>
                    _controller.updateString(SettingsKeys.videoQuality, value),
              ),
              _ChoiceTile(
                title: 'Preferred Audio Language',
                value: state.settings.preferredAudioLanguage,
                options: SettingsDefaults.audioLanguages,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.preferredAudioLanguage,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Preferred Subtitle Language',
                value: state.settings.preferredSubtitleLanguage,
                options: SettingsDefaults.subtitleLanguages,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.preferredSubtitleLanguage,
                  value,
                ),
              ),
              _SwitchTile(
                title: 'Autoplay Next Episode',
                value: state.settings.autoplay,
                onChanged: (value) =>
                    _controller.updateBool(SettingsKeys.autoplay, value),
              ),
              _SwitchTile(
                title: 'Resume Playback',
                value: state.settings.resumePlayback,
                onChanged: (value) =>
                    _controller.updateBool(SettingsKeys.resumePlayback, value),
              ),
              _SwitchTile(
                title: 'Video Debanding',
                value: state.settings.videoDebanding,
                onChanged: (value) =>
                    _controller.updateBool(SettingsKeys.videoDebanding, value),
              ),
            ],
          ),
        ),
      if (showSection('subtitles', 'Subtitle Appearance', [
        'subtitle',
        'font',
        'background',
        'outline',
        'delay',
      ]))
        _Section(
          title: 'Subtitle Appearance',
          icon: LucideIcons.subtitles,
          error: state.sectionErrors['subtitles'],
          child: Column(
            children: [
              _ChoiceTile(
                title: 'Subtitle Font Size',
                value: state.settings.subtitleFontSizeLabel,
                options: SettingsDefaults.subtitleFontSizeLabels,
                onChanged: (value) => _controller.updateDouble(
                  SettingsKeys.subtitleFontSize,
                  SettingsDefaults.subtitleFontSizes[value] ??
                      SettingsDefaults.defaultSubtitleFontSize,
                ),
              ),
              _ChoiceTile(
                title: 'Subtitle Background',
                value: state.settings.subtitleBackground,
                options: SettingsDefaults.subtitleBackgrounds,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.subtitleBackground,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Subtitle Text Style',
                value: state.settings.subtitleOutline,
                options: SettingsDefaults.subtitleOutlines,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.subtitleOutline,
                  value,
                ),
              ),
              _ActionTile(
                title: 'Reset Subtitle Delays',
                subtitle: 'Clear saved per-media subtitle sync offsets',
                icon: LucideIcons.rotateCcw,
                onTap: _resetSubtitleDelays,
              ),
            ],
          ),
        ),
      if (showSection('downloads', 'Downloads', [
        'download',
        'audio',
        'subtitle',
        'parallel',
        'wifi',
      ]))
        _Section(
          title: 'Downloads',
          icon: LucideIcons.download,
          error: state.sectionErrors['downloads'],
          child: Column(
            children: [
              _ChoiceTile(
                title: 'Preferred Download Audio',
                value: state.settings.preferredDownloadAudioLanguage,
                options: SettingsDefaults.audioLanguages,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.preferredDownloadAudioLanguage,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Preferred Download Subtitle',
                value: state.settings.preferredDownloadSubtitleLanguage,
                options: SettingsDefaults.subtitleLanguages,
                onChanged: (value) => _controller.updateString(
                  SettingsKeys.preferredDownloadSubtitleLanguage,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Parallel Download Connections',
                value: state.settings.downloadConcurrency.toString(),
                options: const ['1', '2', '3', '4', '5', '6', '8'],
                onChanged: (value) => _controller.updateInt(
                  SettingsKeys.downloadConcurrency,
                  int.parse(value),
                ),
              ),
              _SwitchTile(
                title: 'Wi-Fi Only Downloads',
                value: state.settings.wifiOnlyDownloads,
                onChanged: (value) => _controller.updateBool(
                  SettingsKeys.wifiOnlyDownloads,
                  value,
                ),
              ),
            ],
          ),
        ),
      if (showSection('home', 'Content Feed', [
        'home',
        'layout',
        'feed',
        'anime',
        'source',
        'audio',
        'sub',
        'dub',
        'tamil',
        'telugu',
        'hindi',
        'korean',
        'malayalam',
      ]))
        _Section(
          title: 'Content Feed',
          icon: LucideIcons.rows3,
          error: state.sectionErrors['home'],
          child: Column(
            children: [
              _ActionTile(
                title: 'Customize Home Layout',
                subtitle: state.settings.homeLayoutSummary,
                icon: LucideIcons.listOrdered,
                onTap: _showHomeLayoutDialog,
              ),
              _ChoiceTile(
                title: 'Preferred Anime Source',
                value: state.settings.preferredAnimeSource,
                options: SettingsDefaults.animeSources,
                onChanged: (value) => _updateHomeFeedString(
                  SettingsKeys.preferredAnimeSource,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Preferred Anime Audio',
                value: state.settings.animePreferredAudio == 'dub'
                    ? 'Dubbed'
                    : 'Subbed',
                options: const ['Subbed', 'Dubbed'],
                onChanged: (value) => _updateHomeFeedString(
                  SettingsKeys.animePreferredAudio,
                  value == 'Dubbed' ? 'dub' : 'sub',
                ),
              ),
              _SwitchTile(
                title: 'Anime',
                value: state.settings.showAnime,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showAnime, value),
              ),
              _SwitchTile(
                title: 'Tamil',
                value: state.settings.showTamil,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showTamil, value),
              ),
              _SwitchTile(
                title: 'Telugu',
                value: state.settings.showTelugu,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showTelugu, value),
              ),
              _SwitchTile(
                title: 'Hindi',
                value: state.settings.showHindi,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showHindi, value),
              ),
              _SwitchTile(
                title: 'Korean',
                value: state.settings.showKorean,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showKorean, value),
              ),
              _SwitchTile(
                title: 'Malayalam',
                value: state.settings.showMalayalam,
                onChanged: (value) =>
                    _updateHomeFeedBool(SettingsKeys.showMalayalam, value),
              ),
            ],
          ),
        ),
      if (showSection('episodes', 'Episode Alerts', [
        'episode',
        'alerts',
        'notifications',
        'check',
      ]))
        _Section(
          title: 'Episode Alerts',
          icon: LucideIcons.bell,
          error: state.sectionErrors['episodes'],
          child: Column(
            children: [
              _SwitchTile(
                title: 'New Episode Alerts',
                value: state.settings.episodeCheckEnabled,
                onChanged: (value) => _controller.updateBool(
                  SettingsKeys.episodeCheckEnabled,
                  value,
                ),
              ),
              _ChoiceTile(
                title: 'Check Frequency',
                value: state.settings.episodeCheckFrequencyHours.toString(),
                options: SettingsDefaults.episodeCheckFrequencies
                    .map((hours) => hours.toString())
                    .toList(),
                onChanged: (value) => _controller.updateInt(
                  SettingsKeys.episodeCheckFrequencyHours,
                  int.parse(value),
                ),
              ),
              _InfoTile(
                title: 'Last Checked',
                value: state.episodeLastCheckLabel,
              ),
              _ActionTile(
                title: 'Check Now',
                subtitle: 'Scan watchlist shows for newly aired episodes',
                icon: LucideIcons.refreshCw,
                onTap: _runEpisodeCheckNow,
              ),
            ],
          ),
        ),
      if (showSection('app', 'App & Updates', [
        'theme',
        'version',
        'changelog',
        'updates',
      ]))
        _Section(
          title: 'App & Updates',
          icon: LucideIcons.info,
          error: state.sectionErrors['appearance'],
          child: Column(
            children: [
              _ChoiceTile(
                title: 'Theme Color',
                value: state.settings.accentColor,
                options: SettingsDefaults.accentColors,
                onChanged: (value) =>
                    _controller.updateString(SettingsKeys.accentColor, value),
              ),
              _InfoTile(title: 'App Version', value: state.appVersion),
              _ActionTile(
                title: 'What\'s New',
                subtitle: state.changelogSeenLabel,
                icon: LucideIcons.megaphone,
                onTap: _showChangelog,
              ),
              _ActionTile(
                title: 'Check for Updates',
                subtitle: 'Verify the desktop build update channel',
                icon: LucideIcons.refreshCw,
                onTap: _checkForUpdates,
              ),
            ],
          ),
        ),
      if (showSection('data', 'Data & Account', [
        'data',
        'account',
        'history',
        'metadata',
      ]))
        _Section(
          title: 'Data & Account',
          icon: LucideIcons.database,
          error: state.sectionErrors['storage'],
          child: Column(
            children: [
              _DestructiveTile(
                title: 'Clear Watch History',
                onConfirm: _controller.clearWatchHistory,
              ),
              _DestructiveTile(
                title: 'Clear Download Metadata',
                onConfirm: _controller.clearDownloadsMetadata,
              ),
            ],
          ),
        ),
      if (showSection('offline', 'Offline & Cache', [
        'offline',
        'cache',
        'storage',
        'network',
        'partial',
        'missing',
      ]))
        _Section(
          title: 'Offline & Cache',
          icon: LucideIcons.hardDrive,
          error: state.sectionErrors['storage'],
          child: Column(
            children: [
              _SwitchTile(
                title: 'Offline Mode',
                value: state.cacheStats.offlineModeEnabled,
                onChanged: (value) => unawaited(_setOfflineMode(value)),
              ),
              _InfoTile(
                title: 'Network Status',
                value: state.cacheStats.networkOnline ? 'Online' : 'Offline',
              ),
              _InfoTile(
                title: 'API Cache',
                value:
                    '${state.cacheStats.validApiEntries} valid, ${state.cacheStats.expiredApiEntries} expired',
              ),
              _InfoTile(
                title: 'Downloads',
                value:
                    '${state.cacheStats.completedDownloadCount} completed, ${state.cacheStats.missingDownloadFiles} missing files',
              ),
              _InfoTile(
                title: 'Managed Storage',
                value: _formatBytes(state.cacheStats.localStorageBytes),
              ),
              _ActionTile(
                title: 'Refresh Status',
                subtitle: 'Recheck network, cache, and download storage',
                icon: LucideIcons.refreshCw,
                onTap: () => unawaited(_controller.load()),
              ),
              _ActionTile(
                title: 'Clean Expired API Cache',
                subtitle: 'Remove stale cached metadata entries',
                icon: LucideIcons.brushCleaning,
                onTap: () => unawaited(
                  _runSettingsAction(_controller.cleanExpiredApiCache),
                ),
              ),
              _ActionTile(
                title: 'Clean Partial Downloads',
                subtitle: 'Remove leftover .part and temporary HLS folders',
                icon: LucideIcons.fileX,
                onTap: () => unawaited(
                  _runSettingsAction(_controller.cleanPartialDownloads),
                ),
              ),
              _ActionTile(
                title: 'Remove Missing Download Records',
                subtitle: 'Forget completed downloads whose files are gone',
                icon: LucideIcons.unlink,
                onTap: () => unawaited(
                  _runSettingsAction(_controller.removeMissingDownloadRecords),
                ),
              ),
              _DestructiveTile(
                title: 'Clear API Cache',
                onConfirm: _controller.clearApiCache,
              ),
              _DestructiveTile(
                title: 'Clear Image Cache',
                onConfirm: _controller.clearImageCache,
              ),
            ],
          ),
        ),
    ];
  }
}

class _SettingsCategory {
  const _SettingsCategory(this.id, this.label, this.icon);

  final String id;
  final String label;
  final IconData icon;
}

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({this.onBack});

  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            style: IconButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              hoverColor: Colors.white.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.extraLarge),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
            ),
            icon: const Icon(LucideIcons.chevronLeft, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Settings', style: AppTypography.display),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Playback, download, app, and account preferences.',
                style: AppTypography.body,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsCategoryWrap extends StatelessWidget {
  const _SettingsCategoryWrap({
    required this.categories,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SettingsCategory> categories;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (var index = 0; index < categories.length; index++)
          _SettingsCategoryButton(
            category: categories[index],
            selected: selectedIndex == index,
            onTap: () => onSelected(index),
          ),
      ],
    );
  }
}

class _SettingsCategoryButton extends StatelessWidget {
  const _SettingsCategoryButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _SettingsCategory category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        hoverColor: Colors.white.withValues(alpha: 0.05),
        splashColor: Colors.transparent,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category.icon,
                color: selected ? AppColors.textPrimary : Colors.white60,
                size: 18,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: AppTypography.body.copyWith(
                    color: selected ? AppColors.textPrimary : Colors.white60,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  child: Text(
                    category.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsContentCard extends StatelessWidget {
  const _SettingsContentCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class SettingsController extends ChangeNotifier {
  SettingsState state = SettingsState.loading();
  bool _isDisposed = false;
  int _loadGeneration = 0;
  int _refreshGeneration = 0;

  @override
  void dispose() {
    _isDisposed = true;
    _loadGeneration++;
    _refreshGeneration++;
    super.dispose();
  }

  Future<void> load() async {
    if (_isDisposed) return;
    final generation = ++_loadGeneration;
    state = SettingsState.loading();
    notifyListeners();

    final errors = <String, String>{};
    var settings = DesktopSettings.defaults();
    var playlistCount = 0;
    var downloadBytes = 0;
    var cacheStats = _emptyCacheStats();
    var partyUserName = 'Guest';
    var appVersion = '1.0.0';
    var buildNumber = '1';
    var episodeLastCheckLabel = 'Never';
    var serviceStatus = const ServiceStatus(
      tmdb: 'Checking',
      anilist: 'Checking',
      iptv: 'Checking',
      supabase: 'Checking',
      realtime: 'Checking',
    );

    try {
      settings = await DesktopSettings.load();
    } catch (error) {
      errors['preferences'] = 'Could not load preferences: $error';
    }

    try {
      await LibraryPersistence.init();
      downloadBytes = await _downloadStorageBytes();
      cacheStats = await DesktopCacheService.instance.getStats();
    } catch (error) {
      errors['downloads'] = 'Could not read download/cache metadata: $error';
    }

    try {
      final playlists = await DesktopIptvService().getPlaylists();
      playlistCount = playlists.length;
    } catch (error) {
      errors['liveTv'] = 'Could not read IPTV playlists: $error';
    }

    try {
      final identity = await WatchPartyIdentityStore().load();
      partyUserName = identity.userName;
    } catch (error) {
      errors['party'] = 'Could not read party identity: $error';
    }

    try {
      final versionInfo = await _readVersionInfo();
      appVersion = versionInfo.$1;
      buildNumber = versionInfo.$2;
    } catch (error) {
      errors['environment'] = 'Could not read app version: $error';
    }

    try {
      final lastCheck = await LibraryEpisodeTrackingService.instance
          .getLastCheckTime();
      episodeLastCheckLabel = _formatDateTime(lastCheck);
    } catch (error) {
      errors['episodes'] = 'Could not read episode alert status: $error';
    }

    if (_isDisposed || generation != _loadGeneration) return;

    state = SettingsState.loaded(
      settings: settings,
      sectionErrors: errors,
      iptvPlaylistCount: playlistCount,
      downloadBytes: downloadBytes,
      cacheStats: cacheStats,
      partyUserName: partyUserName,
      appVersion: appVersion,
      buildNumber: buildNumber,
      episodeLastCheckLabel: episodeLastCheckLabel,
      serviceStatus: serviceStatus,
    );
    notifyListeners();

    unawaited(_refreshServiceStatus(loadGeneration: generation));
  }

  Future<void> updateString(String key, String value) async {
    if (key == SettingsKeys.accentColor) {
      await AppAccentController.instance.setAccentColor(value);
      await load();
      return;
    }
    await _save(key, value);
  }

  Future<void> updateBool(String key, bool value) async {
    await _save(key, value);
  }

  Future<void> updateInt(String key, int value) async {
    await _save(key, value);
  }

  Future<void> updateDouble(String key, double value) async {
    await _save(key, value);
  }

  Future<void> updateStringList(String key, List<String> value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, value);
    unawaited(DesktopCloudSyncService.instance.syncSettings({key: value}));
    await load();
  }

  Future<void> _save(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    switch (value) {
      case String():
        await prefs.setString(key, value);
      case bool():
        await prefs.setBool(key, value);
      case int():
        await prefs.setInt(key, value);
      case double():
        await prefs.setDouble(key, value);
    }
    unawaited(DesktopCloudSyncService.instance.syncSettings({key: value}));
    await load();
  }

  Future<void> refreshIptvStatus() => _refreshServiceStatus();

  Future<void> _refreshServiceStatus({int? loadGeneration}) async {
    if (_isDisposed) return;
    final refreshGeneration = ++_refreshGeneration;
    final current = state;
    if (current.isLoading || current.fatalError != null) return;

    final previous = current.serviceStatus;
    final tmdb = _checkGet('${AppEnvironment.imageProxyUrl}/3/configuration');
    final anilist = _checkPost(AppEnvironment.anilistApiUrl);
    final iptv = _checkGet(current.settings.iptvPlaylistUrl);
    final supabase = Future.value(
      WatchPartySupabaseConfig.isConfigured
          ? WatchPartySupabaseConfig.isAvailable
                ? 'Online'
                : 'Configured'
          : 'Not configured',
    );

    final results = await Future.wait([tmdb, anilist, iptv, supabase]);
    if (_isDisposed ||
        refreshGeneration != _refreshGeneration ||
        (loadGeneration != null && loadGeneration != _loadGeneration)) {
      return;
    }
    state = current.copyWith(
      serviceStatus: ServiceStatus(
        tmdb: results[0],
        anilist: results[1],
        iptv: results[2],
        supabase: results[3],
        realtime: WatchPartySupabaseConfig.isAvailable
            ? 'Available'
            : previous.realtime == 'Checking'
            ? 'Offline'
            : previous.realtime,
      ),
    );
    notifyListeners();
  }

  Future<String> clearImageCache() async {
    await DesktopCacheService.instance.clearImageCache();
    await load();
    return 'Image cache cleared';
  }

  Future<String> clearApiCache() async {
    await DesktopCacheService.instance.clearApiCache();
    await load();
    return 'API cache cleared';
  }

  Future<String> cleanExpiredApiCache() async {
    final count = await DesktopCacheService.instance.cleanExpiredApiCache();
    await load();
    return count == 1
        ? 'Removed 1 expired cache entry'
        : 'Removed $count expired cache entries';
  }

  Future<String> cleanPartialDownloads() async {
    final count = await DesktopCacheService.instance
        .cleanOrphanDownloadPartials();
    await load();
    return count == 1
        ? 'Removed 1 partial download file'
        : 'Removed $count partial download files';
  }

  Future<String> removeMissingDownloadRecords() async {
    final count = await DesktopCacheService.instance
        .removeMissingDownloadRecords();
    await load();
    return count == 1
        ? 'Removed 1 missing download record'
        : 'Removed $count missing download records';
  }

  Future<void> setOfflineMode(bool enabled) async {
    await DesktopCacheService.instance.setOfflineMode(enabled);
    await load();
  }

  Future<String> clearSearchHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('search_history');
    await prefs.remove('recent_searches');
    return 'Search history cleared';
  }

  Future<String> clearWatchHistory() async {
    await DesktopWatchHistoryRepository.instance.clearWatchHistory();
    return 'Watch history cleared';
  }

  Future<String> clearPlaybackCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_playback_position');
    await prefs.remove('last_playback_media');
    final box = await Hive.openBox<String>('watch_history');
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw == null) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) continue;
      decoded
        ..remove('preferredAudioTrack')
        ..remove('preferredSubtitleTrack')
        ..remove('preferredResolution')
        ..remove('preferredProviderIndex');
      await box.put(key, jsonEncode(decoded));
    }
    return 'Playback cache cleared';
  }

  Future<String> clearSubtitleDelaySettings() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys()) {
      if (key.startsWith(SettingsKeys.subtitleDelayPrefix)) {
        await prefs.remove(key);
      }
    }
    return 'Subtitle delay settings cleared';
  }

  Future<int> checkForNewEpisodesNow() async {
    final count = await LibraryEpisodeTrackingService.instance.checkNow();
    await load();
    return count;
  }

  Future<void> markChangelogSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      SettingsKeys.lastSeenChangelogVersion,
      state.appVersion,
    );
    await load();
  }

  Future<DesktopUpdateCheckResult> checkForUpdates() {
    return DesktopUpdateService.checkForUpdates(
      forceRefresh: true,
      includeShorebird: true,
      downloadShorebirdPatch: true,
    );
  }

  Future<String> clearDownloadsMetadata() async {
    await LibraryPersistence.init();
    await LibraryPersistence.downloadsBox.clear();
    await load();
    return 'Downloads metadata cleared';
  }
}

class _SettingsEmptySearch extends StatelessWidget {
  const _SettingsEmptySearch();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            const Icon(LucideIcons.searchX, color: AppColors.textMuted),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'No matching settings found.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsState {
  const SettingsState._({
    required this.isLoading,
    required this.settings,
    required this.sectionErrors,
    required this.iptvPlaylistCount,
    required this.downloadBytes,
    required this.cacheStats,
    required this.partyUserName,
    required this.appVersion,
    required this.buildNumber,
    required this.episodeLastCheckLabel,
    required this.serviceStatus,
    this.fatalError,
  });

  factory SettingsState.loading() => SettingsState._(
    isLoading: true,
    settings: DesktopSettings.defaults(),
    sectionErrors: const {},
    iptvPlaylistCount: 0,
    downloadBytes: 0,
    cacheStats: _emptyCacheStats(),
    partyUserName: 'Guest',
    appVersion: '1.0.0',
    buildNumber: '1',
    episodeLastCheckLabel: 'Never',
    serviceStatus: const ServiceStatus(
      tmdb: 'Checking',
      anilist: 'Checking',
      iptv: 'Checking',
      supabase: 'Checking',
      realtime: 'Checking',
    ),
  );

  factory SettingsState.loaded({
    required DesktopSettings settings,
    required Map<String, String> sectionErrors,
    required int iptvPlaylistCount,
    required int downloadBytes,
    required DesktopCacheStats cacheStats,
    required String partyUserName,
    required String appVersion,
    required String buildNumber,
    required String episodeLastCheckLabel,
    required ServiceStatus serviceStatus,
  }) => SettingsState._(
    isLoading: false,
    settings: settings,
    sectionErrors: sectionErrors,
    iptvPlaylistCount: iptvPlaylistCount,
    downloadBytes: downloadBytes,
    cacheStats: cacheStats,
    partyUserName: partyUserName,
    appVersion: appVersion,
    buildNumber: buildNumber,
    episodeLastCheckLabel: episodeLastCheckLabel,
    serviceStatus: serviceStatus,
  );

  final bool isLoading;
  final DesktopSettings settings;
  final Map<String, String> sectionErrors;
  final int iptvPlaylistCount;
  final int downloadBytes;
  final DesktopCacheStats cacheStats;
  final String partyUserName;
  final String appVersion;
  final String buildNumber;
  final String episodeLastCheckLabel;
  final ServiceStatus serviceStatus;
  final String? fatalError;

  String get downloadStorageLabel => _formatBytes(downloadBytes);
  String get flutterVersion => Platform.version.split(' ').first;
  String get platformLabel => '${Platform.operatingSystem} ${Platform.version}';
  String get changelogSeenLabel =>
      settings.lastSeenChangelogVersion == appVersion ? 'Read' : 'Unread';

  SettingsState copyWith({ServiceStatus? serviceStatus}) => SettingsState._(
    isLoading: isLoading,
    settings: settings,
    sectionErrors: sectionErrors,
    iptvPlaylistCount: iptvPlaylistCount,
    downloadBytes: downloadBytes,
    cacheStats: cacheStats,
    partyUserName: partyUserName,
    appVersion: appVersion,
    buildNumber: buildNumber,
    episodeLastCheckLabel: episodeLastCheckLabel,
    serviceStatus: serviceStatus ?? this.serviceStatus,
    fatalError: fatalError,
  );
}

class DesktopSettings {
  const DesktopSettings({
    required this.accentColor,
    required this.videoQuality,
    required this.playbackSpeed,
    required this.preferredAudioLanguage,
    required this.preferredSubtitleLanguage,
    required this.preferredDownloadAudioLanguage,
    required this.preferredDownloadSubtitleLanguage,
    required this.autoplay,
    required this.resumePlayback,
    required this.videoDebanding,
    required this.subtitleFontSize,
    required this.subtitleBackground,
    required this.subtitleOutline,
    required this.downloadLocation,
    required this.downloadQuality,
    required this.downloadConcurrency,
    required this.wifiOnlyDownloads,
    required this.imageQuality,
    required this.imageProxyUrl,
    required this.iptvPlaylistUrl,
    required this.iptvCacheHours,
    required this.episodeCheckEnabled,
    required this.episodeCheckFrequencyHours,
    required this.homeSectionOrder,
    required this.preferredAnimeSource,
    required this.animePreferredAudio,
    required this.showAnime,
    required this.showTamil,
    required this.showTelugu,
    required this.showHindi,
    required this.showKorean,
    required this.showMalayalam,
    required this.lastSeenChangelogVersion,
  });

  factory DesktopSettings.defaults() => DesktopSettings(
    accentColor: 'red',
    videoQuality: 'auto',
    playbackSpeed: 1,
    preferredAudioLanguage: 'Original',
    preferredSubtitleLanguage: 'Auto',
    preferredDownloadAudioLanguage: 'Original',
    preferredDownloadSubtitleLanguage: 'Auto',
    autoplay: true,
    resumePlayback: true,
    videoDebanding: false,
    subtitleFontSize: SettingsDefaults.defaultSubtitleFontSize,
    subtitleBackground: 'Transparent',
    subtitleOutline: 'Outline',
    downloadLocation: '',
    downloadQuality: 'auto',
    downloadConcurrency: 6,
    wifiOnlyDownloads: false,
    imageQuality: 'w500',
    imageProxyUrl: AppEnvironment.imageProxyUrl,
    iptvPlaylistUrl: AppEnvironment.iptvPlaylistUrl,
    iptvCacheHours: 24,
    episodeCheckEnabled: true,
    episodeCheckFrequencyHours: 24,
    homeSectionOrder: HomeController.sectionOrder,
    preferredAnimeSource: 'Animex',
    animePreferredAudio: 'sub',
    showAnime: true,
    showTamil: true,
    showTelugu: true,
    showHindi: true,
    showKorean: true,
    showMalayalam: true,
    lastSeenChangelogVersion: '',
  );

  static Future<DesktopSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final defaults = DesktopSettings.defaults();
    final fallbackDownloadDir = await _defaultDownloadDirectory();
    return DesktopSettings(
      accentColor:
          prefs.getString(SettingsKeys.accentColor) ?? defaults.accentColor,
      videoQuality:
          prefs.getString(SettingsKeys.videoQuality) ?? defaults.videoQuality,
      playbackSpeed:
          prefs.getDouble(SettingsKeys.playbackSpeed) ?? defaults.playbackSpeed,
      preferredAudioLanguage:
          prefs.getString(SettingsKeys.preferredAudioLanguage) ??
          defaults.preferredAudioLanguage,
      preferredSubtitleLanguage:
          prefs.getString(SettingsKeys.preferredSubtitleLanguage) ??
          defaults.preferredSubtitleLanguage,
      preferredDownloadAudioLanguage:
          prefs.getString(SettingsKeys.preferredDownloadAudioLanguage) ??
          defaults.preferredDownloadAudioLanguage,
      preferredDownloadSubtitleLanguage:
          prefs.getString(SettingsKeys.preferredDownloadSubtitleLanguage) ??
          defaults.preferredDownloadSubtitleLanguage,
      autoplay: prefs.getBool(SettingsKeys.autoplay) ?? defaults.autoplay,
      resumePlayback:
          prefs.getBool(SettingsKeys.resumePlayback) ?? defaults.resumePlayback,
      videoDebanding:
          prefs.getBool(SettingsKeys.videoDebanding) ?? defaults.videoDebanding,
      subtitleFontSize:
          prefs.getDouble(SettingsKeys.subtitleFontSize) ??
          defaults.subtitleFontSize,
      subtitleBackground:
          prefs.getString(SettingsKeys.subtitleBackground) ??
          defaults.subtitleBackground,
      subtitleOutline:
          prefs.getString(SettingsKeys.subtitleOutline) ??
          defaults.subtitleOutline,
      downloadLocation:
          prefs.getString(SettingsKeys.downloadLocation) ?? fallbackDownloadDir,
      downloadQuality:
          prefs.getString(SettingsKeys.downloadQuality) ??
          defaults.downloadQuality,
      downloadConcurrency:
          prefs.getInt(SettingsKeys.downloadConcurrency) ??
          defaults.downloadConcurrency,
      wifiOnlyDownloads:
          prefs.getBool(SettingsKeys.wifiOnlyDownloads) ??
          defaults.wifiOnlyDownloads,
      imageQuality:
          prefs.getString(SettingsKeys.imageQuality) ?? defaults.imageQuality,
      imageProxyUrl:
          prefs.getString(SettingsKeys.imageProxyUrl) ?? defaults.imageProxyUrl,
      iptvPlaylistUrl:
          prefs.getString(SettingsKeys.iptvPlaylistUrl) ??
          defaults.iptvPlaylistUrl,
      iptvCacheHours:
          prefs.getInt(SettingsKeys.iptvCacheHours) ?? defaults.iptvCacheHours,
      episodeCheckEnabled:
          prefs.getBool(SettingsKeys.episodeCheckEnabled) ??
          defaults.episodeCheckEnabled,
      episodeCheckFrequencyHours:
          prefs.getInt(SettingsKeys.episodeCheckFrequencyHours) ??
          defaults.episodeCheckFrequencyHours,
      homeSectionOrder: HomeController.normalizeSectionOrder(
        prefs.getStringList(SettingsKeys.homeSectionOrder),
      ),
      preferredAnimeSource: SettingsDefaults.normalizedAnimeSource(
        prefs.getString(SettingsKeys.preferredAnimeSource),
      ),
      animePreferredAudio:
          prefs.getString(SettingsKeys.animePreferredAudio) ??
          defaults.animePreferredAudio,
      showAnime: prefs.getBool(SettingsKeys.showAnime) ?? defaults.showAnime,
      showTamil: prefs.getBool(SettingsKeys.showTamil) ?? defaults.showTamil,
      showTelugu: prefs.getBool(SettingsKeys.showTelugu) ?? defaults.showTelugu,
      showHindi: prefs.getBool(SettingsKeys.showHindi) ?? defaults.showHindi,
      showKorean: prefs.getBool(SettingsKeys.showKorean) ?? defaults.showKorean,
      showMalayalam:
          prefs.getBool(SettingsKeys.showMalayalam) ?? defaults.showMalayalam,
      lastSeenChangelogVersion:
          prefs.getString(SettingsKeys.lastSeenChangelogVersion) ??
          defaults.lastSeenChangelogVersion,
    );
  }

  final String accentColor;
  final String videoQuality;
  final double playbackSpeed;
  final String preferredAudioLanguage;
  final String preferredSubtitleLanguage;
  final String preferredDownloadAudioLanguage;
  final String preferredDownloadSubtitleLanguage;
  final bool autoplay;
  final bool resumePlayback;
  final bool videoDebanding;
  final double subtitleFontSize;
  final String subtitleBackground;
  final String subtitleOutline;
  final String downloadLocation;
  final String downloadQuality;
  final int downloadConcurrency;
  final bool wifiOnlyDownloads;
  final String imageQuality;
  final String imageProxyUrl;
  final String iptvPlaylistUrl;
  final int iptvCacheHours;
  final bool episodeCheckEnabled;
  final int episodeCheckFrequencyHours;
  final List<String> homeSectionOrder;
  final String preferredAnimeSource;
  final String animePreferredAudio;
  final bool showAnime;
  final bool showTamil;
  final bool showTelugu;
  final bool showHindi;
  final bool showKorean;
  final bool showMalayalam;
  final String lastSeenChangelogVersion;

  String get subtitleFontSizeLabel {
    for (final entry in SettingsDefaults.subtitleFontSizes.entries) {
      if (entry.value == subtitleFontSize) return entry.key;
    }
    return 'Medium';
  }

  String get homeLayoutSummary {
    final firstSections = homeSectionOrder
        .take(3)
        .map((id) => HomeController.sectionTitles[id] ?? id)
        .join(', ');
    return '$firstSections${homeSectionOrder.length > 3 ? ', ...' : ''}';
  }
}

abstract final class SettingsKeys {
  static const accentColor = appAccentColorPreferenceKey;
  static const videoQuality = 'video_quality';
  static const playbackSpeed = 'playback_speed';
  static const preferredAudioLanguage = 'preferred_audio_language';
  static const preferredSubtitleLanguage = 'preferred_subtitle_language';
  static const preferredDownloadAudioLanguage =
      'preferred_download_audio_language';
  static const preferredDownloadSubtitleLanguage =
      'preferred_download_subtitle_language';
  static const autoplay = 'autoplay_next_episode';
  static const resumePlayback = 'resume_playback';
  static const videoDebanding = 'video_debanding';
  static const subtitleFontSize = 'subtitle_font_size';
  static const subtitleBackground = 'subtitle_background';
  static const subtitleOutline = 'subtitle_outline';
  static const subtitleDelayPrefix = 'subtitle_delay_';
  static const downloadLocation = 'download_location';
  static const downloadQuality = 'download_quality';
  static const downloadConcurrency = 'download_concurrency';
  static const wifiOnlyDownloads = 'download_wifi_only';
  static const imageQuality = 'image_quality';
  static const imageProxyUrl = 'image_proxy_url';
  static const iptvPlaylistUrl = 'iptv_playlist_url';
  static const iptvCacheHours = 'iptv_cache_hours';
  static const episodeCheckEnabled = 'desktop_episode_check_enabled';
  static const episodeCheckFrequencyHours =
      'desktop_episode_check_frequency_hours';
  static const homeSectionOrder = HomeController.homeSectionOrderKey;
  static const preferredAnimeSource = 'preferred_anime_source';
  static const animePreferredAudio = 'animePreferredAudio';
  static const showAnime = 'showAnime';
  static const showTamil = 'showTamil';
  static const showTelugu = 'showTelugu';
  static const showHindi = 'showHindi';
  static const showKorean = 'showKorean';
  static const showMalayalam = 'showMalayalam';
  static const lastSeenChangelogVersion = 'last_seen_changelog_version';
}

abstract final class SettingsDefaults {
  static const accentColors = [
    'red',
    'blue',
    'green',
    'orange',
    'pink',
    'purple',
    'teal',
    'yellow',
    'cyan',
  ];
  static const videoQualities = ['auto', '2160p', '1080p', '720p', '480p'];
  static const playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
  static const defaultSubtitleFontSize = 18.0;
  static const subtitleFontSizes = <String, double>{
    'Small': 14.0,
    'Medium': 18.0,
    'Large': 24.0,
    'Extra Large': 30.0,
  };
  static const subtitleBackgrounds = [
    'Transparent',
    'Semi-Transparent',
    'Solid',
  ];
  static const subtitleOutlines = ['None', 'Subtle Shadow', 'Outline'];
  static const episodeCheckFrequencies = [6, 12, 24, 48, 72];
  static const animeSources = ['Animex', 'Xon'];
  static String normalizedAnimeSource(String? value) {
    final source = value?.trim();
    if (source != null && animeSources.contains(source)) return source;
    return animeSources.first;
  }

  static List<String> get subtitleFontSizeLabels =>
      subtitleFontSizes.keys.toList();
  static const audioLanguages = [
    'Original',
    'English',
    'Japanese',
    'Hindi',
    'Tamil',
    'Telugu',
    'Spanish',
    'French',
    'Korean',
    'German',
    'Italian',
  ];
  static const subtitleLanguages = [
    'Auto',
    'English',
    'Hindi',
    'Tamil',
    'Telugu',
    'Spanish',
    'French',
    'Korean',
    'German',
    'Off',
  ];
}

class ServiceStatus {
  const ServiceStatus({
    required this.tmdb,
    required this.anilist,
    required this.iptv,
    required this.supabase,
    required this.realtime,
  });

  final String tmdb;
  final String anilist;
  final String iptv;
  final String supabase;
  final String realtime;
}

class _HomeLayoutDialog extends StatefulWidget {
  const _HomeLayoutDialog({required this.sectionOrder});

  final List<String> sectionOrder;

  @override
  State<_HomeLayoutDialog> createState() => _HomeLayoutDialogState();
}

class _HomeLayoutDialogState extends State<_HomeLayoutDialog> {
  late List<String> _order = HomeController.normalizeSectionOrder(
    widget.sectionOrder,
  );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Customize Home Layout'),
      content: SizedBox(
        width: 520,
        height: 520,
        child: ReorderableListView.builder(
          itemCount: _order.length,
          onReorderItem: (oldIndex, newIndex) {
            setState(() {
              final item = _order.removeAt(oldIndex);
              _order.insert(newIndex, item);
            });
          },
          itemBuilder: (context, index) {
            final sectionId = _order[index];
            return ListTile(
              key: ValueKey(sectionId),
              leading: const Icon(LucideIcons.gripVertical),
              title: Text(HomeController.sectionTitles[sectionId] ?? sectionId),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() => _order = List.of(HomeController.sectionOrder));
          },
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _order),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
    this.error,
  });

  final String title;
  final IconData icon;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              title.toUpperCase(),
              style: AppTypography.metadata.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w800,
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
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                      child: Row(
                        children: [
                          const Icon(
                            LucideIcons.triangleAlert,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              error!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  child,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Retained for settings capabilities that are not exposed by Android Profile.
// ignore: unused_element
class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.title,
    required this.subtitle,
    // ignore: unused_element_parameter
    this.leading,
    // ignore: unused_element_parameter
    this.enabled = true,
  });

  final String title;
  final String subtitle;
  final IconData? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: enabled,
      leading: leading == null ? null : Icon(leading),
      title: Text(title),
      subtitle: Text(subtitle),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          value,
          textAlign: TextAlign.end,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.caption.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(
        title,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: DropdownButton<String>(
        value: options.contains(value) ? value : options.first,
        dropdownColor: AppColors.surfaceVariant,
        style: AppTypography.body.copyWith(color: AppColors.textPrimary),
        items: options
            .map(
              (option) => DropdownMenuItem(value: option, child: Text(option)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

// ignore: unused_element
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      value: value,
      onChanged: onChanged,
      activeThumbColor: AppColors.primary,
      title: Text(
        title,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ignore: unused_element
class _TextSettingTile extends StatelessWidget {
  const _TextSettingTile({
    required this.title,
    required this.value,
    required this.hint,
    required this.validator,
    required this.onSubmitted,
  });

  final String title;
  final String value;
  final String hint;
  final String? Function(String) validator;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(value.isEmpty ? hint : value),
      trailing: IconButton(
        tooltip: 'Edit $title',
        icon: const Icon(LucideIcons.pencil),
        onPressed: () async {
          final next = await _promptText(
            context,
            title: title,
            initialValue: value,
            hint: hint,
            validator: validator,
          );
          if (next != null) onSubmitted(next);
        },
      ),
    );
  }
}

// ignore: unused_element
class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    this.icon = LucideIcons.refreshCw,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: AppColors.textPrimary, size: 22),
      title: Text(
        title,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption.copyWith(color: AppColors.textMuted),
      ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        color: AppColors.textMuted,
        size: 18,
      ),
      onTap: onTap,
    );
  }
}

class _DestructiveTile extends StatelessWidget {
  const _DestructiveTile({required this.title, required this.onConfirm});

  final String title;
  final Future<String> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: const Icon(LucideIcons.trash2, color: AppColors.danger),
      title: Text(
        title,
        style: AppTypography.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: const Text(
        'This action cannot be undone.',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(
        LucideIcons.chevronRight,
        color: AppColors.textMuted,
        size: 18,
      ),
      onTap: () async {
        final confirmed = await _confirm(context, title);
        if (!confirmed) return;
        final message = await onConfirm();
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
    );
  }
}

Future<String?> _promptText(
  BuildContext context, {
  required String title,
  required String initialValue,
  required String hint,
  required String? Function(String) validator,
}) {
  final controller = TextEditingController(text: initialValue);
  String? errorText;
  return showDialog<String>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(hintText: hint, errorText: errorText),
              onSubmitted: (_) {
                final value = controller.text.trim();
                final error = validator(value);
                if (error != null) {
                  setState(() => errorText = error);
                  return;
                }
                Navigator.pop(context, value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final value = controller.text.trim();
                  final error = validator(value);
                  if (error != null) {
                    setState(() => errorText = error);
                    return;
                  }
                  Navigator.pop(context, value);
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<bool> _confirm(BuildContext context, String title) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$title?'),
      content: const Text('This action cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  return result == true;
}

String? _validateHttpUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
    return 'Enter a valid URL.';
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'URL must start with http or https.';
  }
  return null;
}

// ignore: unused_element
String? _validateDirectory(String value) {
  if (value.trim().isEmpty) return 'Enter a directory path.';
  final dir = Directory(value);
  if (!dir.existsSync()) return 'Directory does not exist.';
  return null;
}

Future<String> _checkGet(String url) async {
  final validation = _validateHttpUrl(url);
  if (validation != null) return 'Invalid';
  try {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 6));
    return response.statusCode < 500 ? 'Online' : 'Offline';
  } catch (_) {
    return 'Offline';
  }
}

Future<String> _checkPost(String url) async {
  final validation = _validateHttpUrl(url);
  if (validation != null) return 'Invalid';
  try {
    final response = await http
        .post(
          Uri.parse(url),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({'query': '{ Media(id: 1) { id } }'}),
        )
        .timeout(const Duration(seconds: 6));
    return response.statusCode == 200 ? 'Online' : 'Offline';
  } catch (_) {
    return 'Offline';
  }
}

Future<int> _downloadStorageBytes() async {
  if (!LibraryPersistence.isReady) return 0;
  var total = 0;
  for (final item in LibraryPersistence.downloadsBox.values) {
    try {
      final file = File(item.savePath);
      if (file.existsSync()) total += file.lengthSync();
    } catch (_) {}
  }
  return total;
}

Future<String> _defaultDownloadDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  return '${directory.path}/downloads';
}

Future<(String, String)> _readVersionInfo() async {
  final file = File('pubspec.yaml');
  if (!file.existsSync()) return ('1.0.0', '1');
  final content = await file.readAsString();
  final match = RegExp(
    r'^version:\s*([^\s+]+)(?:\+(\S+))?',
    multiLine: true,
  ).firstMatch(content);
  return (match?.group(1) ?? '1.0.0', match?.group(2) ?? '1');
}

DesktopCacheStats _emptyCacheStats() {
  return DesktopCacheStats(
    apiEntries: 0,
    validApiEntries: 0,
    expiredApiEntries: 0,
    apiCacheBytes: 0,
    hiveBytes: 0,
    downloadBytes: 0,
    downloadCount: 0,
    completedDownloadCount: 0,
    missingDownloadFiles: 0,
    orphanDownloadFiles: 0,
    offlineModeEnabled: false,
    networkOnline: true,
    lastUpdated: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

String _formatDateTime(DateTime? value) {
  if (value == null) return 'Never';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _desktopChangelog() {
  return [
    'Desktop settings now expose Android parity controls for subtitle size, subtitle background, subtitle outline, debanding, episode alerts, and home layout ordering.',
    'Subtitle sync offsets are saved per media item from the player and can be cleared from Settings.',
    'The Home page Studio section remains on Home while provider browsing opens from the existing studio cards.',
    'New episode alerts can be enabled, scheduled, and checked manually from Settings or Library.',
  ].join('\n\n');
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit < 2 ? 0 : 1)} ${units[unit]}';
}
