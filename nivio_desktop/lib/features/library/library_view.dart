import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import 'models/library_models.dart';
import 'services/episode_tracking_service.dart';
import 'services/library_data_service.dart';
import 'services/library_persistence.dart';
import 'widgets/downloads_grid.dart';
import 'widgets/library_empty_state.dart';
import 'widgets/library_tabs.dart';
import 'widgets/new_episodes_panel.dart';
import 'widgets/release_timeline.dart';
import 'widgets/schedule_calendar.dart';
import 'widgets/watchlist_grid.dart';
import '../player/models/playback_request.dart';
import '../../core/interfaces/watch_history_repository.dart';

class LibraryView extends StatefulWidget {
  const LibraryView({
    super.key,
    required this.watchHistoryRepository,
    this.onOpenDetail,
    this.onPlay,
  });

  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;
  final WatchHistoryRepository watchHistoryRepository;

  @override
  State<LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<LibraryView> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _watchlistScrollController = ScrollController();
  final LibraryScheduleService _scheduleService = LibraryScheduleService();
  final LibraryWatchlistService _watchlistService = LibraryWatchlistService();
  final LibraryDownloadsService _downloadsService = LibraryDownloadsService();
  final LibraryEpisodeTrackingService _episodeTrackingService =
      LibraryEpisodeTrackingService.instance;

  LibraryTab _selectedTab = LibraryTab.schedule;
  late DateTime _focusedDate;
  late DateTime _selectedScheduleDate;
  bool _watchlistOnly = true;
  late Future<LibrarySectionResult<List<LibraryScheduleItem>>> _scheduleFuture;
  Map<int, Map<String, dynamic>> _historyByMediaId = const {};

  @override
  void initState() {
    super.initState();
    _focusedDate = DateTime.now();
    _selectedScheduleDate = _focusedDate;
    _scheduleFuture = _loadSchedule();
    unawaited(_episodeTrackingService.runAppLaunchCheck());
    if (widget.watchHistoryRepository case final Listenable listenable) {
      listenable.addListener(_onHistoryChanged);
    }
    unawaited(_loadHistory());
  }

  @override
  void dispose() {
    if (widget.watchHistoryRepository case final Listenable listenable) {
      listenable.removeListener(_onHistoryChanged);
    }
    _scrollController.dispose();
    _watchlistScrollController.dispose();
    super.dispose();
  }

  void _onHistoryChanged() => unawaited(_loadHistory());

  Future<void> _loadHistory() async {
    final entries = await widget.watchHistoryRepository.getWatchHistory();
    if (!mounted) return;
    setState(() {
      _historyByMediaId = <int, Map<String, dynamic>>{
        for (final entry in entries)
          if (entry['tmdbId'] is num) (entry['tmdbId'] as num).toInt(): entry,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedTab == LibraryTab.watchlist) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.sizeOf(context).height;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppBreakpoints.contentMaxWidth,
              ),
              child: SizedBox(
                height: availableHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: AppSpacing.xxl),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildLibraryTabs(),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Expanded(child: _buildSelectedTab()),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return DesktopScrollbar(
      controller: _scrollController,
      child: SingleChildScrollView(
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        child: PageContainer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              Align(
                alignment: Alignment.centerRight,
                child: _buildLibraryTabs(),
              ),
              const SizedBox(height: AppSpacing.lg),
              _buildSelectedTab(),
              const SizedBox(height: AppSpacing.massive),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedTab() {
    return switch (_selectedTab) {
      LibraryTab.schedule => _ScheduleTab(
        focusedDate: _focusedDate,
        selectedDate: _selectedScheduleDate,
        watchlistOnly: _watchlistOnly,
        scheduleFuture: _scheduleFuture,
        onPreviousWeek: () => _moveWeek(-1),
        onNextWeek: () => _moveWeek(1),
        onPickMonth: _showMonthPicker,
        onDateSelected: (date) {
          setState(() {
            _focusedDate = date;
            _selectedScheduleDate = date;
            _scheduleFuture = _loadSchedule();
          });
        },
        onFilterChanged: (value) {
          setState(() {
            _watchlistOnly = value;
            _scheduleFuture = _loadSchedule();
          });
        },
        onRetry: () => setState(() => _scheduleFuture = _loadSchedule()),
        onOpenDetail: widget.onOpenDetail,
      ),
      LibraryTab.newEpisodes => NewEpisodesPanel(
        service: _episodeTrackingService,
        onOpenDetail: widget.onOpenDetail,
      ),
      LibraryTab.watchlist => _WatchlistTab(
        service: _watchlistService,
        historyByMediaId: _historyByMediaId,
        scrollController: _watchlistScrollController,
        onOpenDetail: widget.onOpenDetail,
        onPlay: widget.onPlay,
      ),
      LibraryTab.downloads => _DownloadsTab(
        service: _downloadsService,
        onOpenDetail: widget.onOpenDetail,
        onPlay: widget.onPlay,
      ),
    };
  }

  Widget _buildLibraryTabs() {
    if (!LibraryPersistence.isReady) {
      return LibraryTabs(
        selectedTab: _selectedTab,
        onTabSelected: (tab) => setState(() => _selectedTab = tab),
      );
    }

    return ValueListenableBuilder<Box<LibraryNewEpisodeItem>>(
      valueListenable: _episodeTrackingService.listenable(),
      builder: (context, box, _) {
        final unreadCount = box.values
            .where((episode) => !episode.isRead)
            .length;
        return LibraryTabs(
          selectedTab: _selectedTab,
          unreadEpisodeCount: unreadCount,
          onTabSelected: (tab) {
            setState(() => _selectedTab = tab);
          },
        );
      },
    );
  }

  Future<LibrarySectionResult<List<LibraryScheduleItem>>> _loadSchedule() {
    return _scheduleService.fetchForDate(
      _selectedScheduleDate,
      watchlistOnly: _watchlistOnly,
    );
  }

  void _moveWeek(int direction) {
    setState(() {
      _focusedDate = _focusedDate.add(Duration(days: 7 * direction));
    });
  }

  Future<void> _showMonthPicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _focusedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked == null) return;
    setState(() {
      _focusedDate = picked;
      _selectedScheduleDate = picked;
      _scheduleFuture = _loadSchedule();
    });
  }
}

class _ScheduleTab extends StatelessWidget {
  const _ScheduleTab({
    required this.focusedDate,
    required this.selectedDate,
    required this.watchlistOnly,
    required this.scheduleFuture,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onPickMonth,
    required this.onDateSelected,
    required this.onFilterChanged,
    required this.onRetry,
    this.onOpenDetail,
  });

  final DateTime focusedDate;
  final DateTime selectedDate;
  final bool watchlistOnly;
  final Future<LibrarySectionResult<List<LibraryScheduleItem>>> scheduleFuture;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPickMonth;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<bool> onFilterChanged;
  final VoidCallback onRetry;
  final ValueChanged<String>? onOpenDetail;

  @override
  Widget build(BuildContext context) {
    final calendar = ScheduleCalendar(
      focusedDate: focusedDate,
      selectedDate: selectedDate,
      onPreviousWeek: onPreviousWeek,
      onNextWeek: onNextWeek,
      onPickMonth: onPickMonth,
      onDateSelected: onDateSelected,
    );
    final filters = _ScheduleFilters(
      watchlistOnly: watchlistOnly,
      onFilterChanged: onFilterChanged,
    );
    final timeline =
        FutureBuilder<LibrarySectionResult<List<LibraryScheduleItem>>>(
          future: scheduleFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingView(message: 'Loading schedule...');
            }
            final result = snapshot.data;
            if (snapshot.hasError || result == null || result.hasError) {
              return _SectionError(
                title: result?.isOffline == true
                    ? 'Schedule unavailable offline'
                    : 'Schedule failed to load',
                message: 'Retry to refresh releases for the selected date.',
                onRetry: onRetry,
              );
            }
            return ReleaseTimeline(
              releases: result.data ?? const [],
              watchlistOnly: watchlistOnly,
              onOpenDetail: onOpenDetail,
            );
          },
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        calendar,
        const SizedBox(height: AppSpacing.lg),
        Align(alignment: Alignment.centerLeft, child: filters),
        const SizedBox(height: AppSpacing.xxl),
        timeline,
      ],
    );
  }
}

class _ScheduleFilters extends StatelessWidget {
  const _ScheduleFilters({
    required this.watchlistOnly,
    required this.onFilterChanged,
  });

  final bool watchlistOnly;
  final ValueChanged<bool> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        _ScheduleFilterButton(
          label: const Text('My Watchlist'),
          selected: watchlistOnly,
          icon: LucideIcons.check,
          onTap: () => onFilterChanged(true),
        ),
        _ScheduleFilterButton(
          label: const Text('Discover'),
          selected: !watchlistOnly,
          icon: LucideIcons.sparkles,
          onTap: () => onFilterChanged(false),
        ),
      ],
    );
  }
}

class _ScheduleFilterButton extends StatelessWidget {
  const _ScheduleFilterButton({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final Widget label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: selected ? null : onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: selected ? AppColors.secondary : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(AppRadius.medium),
            border: Border.all(
              color: selected ? AppColors.secondary : AppColors.borderSubtle,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              DefaultTextStyle.merge(
                style: AppTypography.body.copyWith(
                  color: selected
                      ? AppColors.textPrimary
                      : AppColors.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
                child: label,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchlistTab extends StatelessWidget {
  const _WatchlistTab({
    required this.service,
    required this.historyByMediaId,
    required this.scrollController,
    this.onOpenDetail,
    this.onPlay,
  });

  final LibraryWatchlistService service;
  final Map<int, Map<String, dynamic>> historyByMediaId;
  final ScrollController scrollController;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<LibraryWatchlistItem>>(
      valueListenable: service.listenable(),
      builder: (context, box, _) {
        return FutureBuilder<LibrarySectionResult<List<LibraryWatchlistItem>>>(
          future: service.getItems(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingView(message: 'Loading watchlist...');
            }
            final result = snapshot.data;
            if (snapshot.hasError || result == null || result.hasError) {
              return _SectionError(
                title: 'Watchlist failed to load',
                message: 'Retry to read your saved titles.',
                onRetry: () {},
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(
                  title: 'My Watchlist',
                  subtitle:
                      'Saved locally and ready for cloud sync when account sync is available.',
                ),
                const SizedBox(height: AppSpacing.lg),
                Expanded(
                  child: WatchlistGrid(
                    items: result.data ?? const [],
                    service: service,
                    historyByMediaId: historyByMediaId,
                    scrollController: scrollController,
                    onOpenDetail: onOpenDetail,
                    onPlay: onPlay,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _DownloadsTab extends StatelessWidget {
  const _DownloadsTab({required this.service, this.onOpenDetail, this.onPlay});

  final LibraryDownloadsService service;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Box<LibraryDownloadItem>>(
      valueListenable: service.listenable(),
      builder: (context, box, _) {
        final downloads = box.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              title: 'Downloads',
              subtitle: 'Active and completed local downloads',
            ),
            const SizedBox(height: AppSpacing.lg),
            DownloadsGrid(
              downloads: downloads,
              service: service,
              onOpenDetail: onOpenDetail,
              onPlay: onPlay,
            ),
          ],
        );
      },
    );
  }
}

class _SectionError extends StatelessWidget {
  const _SectionError({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        LibraryEmptyState(title: title, message: message),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
