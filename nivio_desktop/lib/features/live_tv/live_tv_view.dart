import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../core/config/app_environment.dart';
import '../../shared/models/iptv_channel.dart';
import '../../shared/models/iptv_playlist.dart';
import '../player/models/playback_request.dart';
import '../player/playback_request_factory.dart';
import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import 'services/iptv_service.dart';

class LiveTvView extends StatefulWidget {
  const LiveTvView({super.key, this.onPlay});

  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  State<LiveTvView> createState() => _LiveTvViewState();
}

class _LiveTvViewState extends State<LiveTvView> {
  static const Duration _loadTimeout = Duration(seconds: 40);

  final DesktopIptvService _service = DesktopIptvService();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = false;
  bool _hasLoadError = false;
  bool _hasLoadedOnce = false;
  String? _error;
  List<IptvChannel> _channels = const [];
  List<IptvChannel> _filteredChannels = const [];
  Map<String, List<IptvChannel>> _groupedChannels = const {};
  String _searchQuery = '';
  String? _selectedGroup;
  LiveTvSourceFilter _selectedSource = LiveTvSourceFilter.iptv;

  @override
  void initState() {
    super.initState();
    _urlController.text = AppEnvironment.iptvPlaylistUrl;
    _loadSavedPlaylist();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoading &&
        !_hasLoadError &&
        (_channels.isNotEmpty || _hasLoadedOnce)) {
      return _buildLoadedView();
    }

    return NivioPageBackdrop(
      child: DesktopScrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.huge,
            AppSpacing.xxl,
            AppSpacing.massive,
          ),
          child: PageContainer(
            child: _isLoading
                ? const LoadingView(message: 'Loading channels...')
                : _hasLoadError
                ? _LiveTvErrorState(
                    message: _error ?? 'Live TV failed to load.',
                    onRetry: _loadSavedPlaylist,
                    onAddNew: _showAddPlaylistForm,
                  )
                : _EmptyPlaylistState(
                    controller: _urlController,
                    error: _error,
                    onLoad: () => _fetchPlaylist(_urlController.text.trim()),
                    onLoadPublic: _loadDefaultPlaylist,
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadedView() {
    final groups = ['All', 'Favorites', ..._groupedChannels.keys];
    return NivioPageBackdrop(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageContainer(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xxl,
                AppSpacing.lg,
                AppSpacing.xxl,
                AppSpacing.sm,
              ),
              child: _LiveTvToolbar(
                searchController: _searchController,
                selectedGroup: _selectedGroup ?? 'All',
                selectedSource: _selectedSource,
                groups: groups,
                onSearchChanged: (value) {
                  _searchQuery = value;
                  _filterChannels();
                },
                onGroupSelected: (value) {
                  setState(() {
                    _selectedGroup = value;
                    _filteredChannels = _filteredChannelsFor();
                  });
                  _resetListScroll();
                },
                onSourceSelected: (value) {
                  if (value == _selectedSource) return;
                  setState(() {
                    _selectedSource = value;
                    _selectedGroup = null;
                    _channels = const [];
                    _filteredChannels = const [];
                    _groupedChannels = const {};
                  });
                  _loadSavedPlaylist();
                },
                onManagePlaylists: _showPlaylistManager,
              ),
            ),
          ),
          Expanded(
            child: PageContainer(
              child: _filteredChannels.isEmpty
                  ? Center(
                      child: Text(
                        'No channels found',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textMuted,
                        ),
                      ),
                    )
                  : _ChannelList(
                      controller: _scrollController,
                      channels: _filteredChannels,
                      onToggleFavorite: _toggleFavorite,
                      onPlay: _playChannel,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSavedPlaylist() async {
    _log('loadSavedPlaylist start');
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
      _error = null;
    });
    try {
      final channels = await _service
          .loadAllChannels(sourceFilter: _selectedSource)
          .timeout(_loadTimeout);
      _log('loadSavedPlaylist service complete channels=${channels.length}');
      if (!mounted) return;
      _processChannels(channels);
      _hasLoadedOnce = true;
      _log(
        'loadSavedPlaylist end state=${channels.isEmpty ? 'empty' : 'loaded'}',
      );
    } catch (error, stackTrace) {
      _log(
        'loadSavedPlaylist exception type=${error.runtimeType} error=$error',
      );
      debugPrintStack(stackTrace: stackTrace, label: '[live_tv] load stack');
      if (!mounted) return;
      setState(() {
        _hasLoadError = true;
        _error = 'Failed to load saved playlists: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _log('loadSavedPlaylist finally loading=false');
      }
    }
  }

  Future<void> _loadDefaultPlaylist() async {
    final url = await _service.defaultPlaylistUrl();
    if (!mounted) return;
    _urlController.text = url;
    await _fetchPlaylist(url, name: 'Default Playlist');
  }

  Future<void> _fetchPlaylist(
    String url, {
    String name = 'New Playlist',
  }) async {
    if (url.isEmpty) return;
    _log('fetchPlaylist start url=$url');
    setState(() {
      _isLoading = true;
      _hasLoadError = false;
      _error = null;
    });
    try {
      await _service.fetchAndSavePlaylist(url, name).timeout(_loadTimeout);
      _log('fetchPlaylist save complete');
      await _loadSavedPlaylist();
      _log('fetchPlaylist end loaded');
    } catch (error, stackTrace) {
      _log('fetchPlaylist exception type=${error.runtimeType} error=$error');
      debugPrintStack(stackTrace: stackTrace, label: '[live_tv] fetch stack');
      if (!mounted) return;
      setState(() {
        _hasLoadError = true;
        _error = 'Failed to load playlist: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _log('fetchPlaylist finally loading=false');
      }
    }
  }

  void _processChannels(List<IptvChannel> channels) {
    final grouped = <String, List<IptvChannel>>{};
    for (final channel in channels) {
      grouped.putIfAbsent(channel.group, () => []).add(channel);
    }
    final sortedGroups = Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );

    setState(() {
      _channels = channels;
      _groupedChannels = sortedGroups;
      _filteredChannels = _filteredChannelsFor(channels: channels);
      _hasLoadError = false;
      _error = null;
    });
  }

  void _filterChannels() {
    setState(() => _filteredChannels = _filteredChannelsFor());
    _resetListScroll();
  }

  List<IptvChannel> _filteredChannelsFor({List<IptvChannel>? channels}) {
    var result = channels ?? _channels;
    if (_selectedGroup == 'Favorites') {
      result = result.where((channel) => channel.isFavorite).toList();
    } else if (_selectedGroup != null && _selectedGroup != 'All') {
      result = result
          .where((channel) => channel.group == _selectedGroup)
          .toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((channel) => channel.name.toLowerCase().contains(query))
          .toList();
    }

    return result;
  }

  Future<void> _toggleFavorite(IptvChannel channel) async {
    await _service.toggleFavorite(channel.url);
    await _loadSavedPlaylist();
  }

  void _playChannel(IptvChannel channel) {
    widget.onPlay?.call(PlaybackRequestFactory.fromIptv(channel));
  }

  Future<void> _showPlaylistManager() async {
    final playlists = await _service.getPlaylists();
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) => _PlaylistManagerDialog(
        playlists: playlists,
        onDelete: (playlist) async {
          await _service.deletePlaylist(playlist.id);
          await _loadSavedPlaylist();
        },
        onAddNew: () {
          setState(() {
            _channels = const [];
            _filteredChannels = const [];
            _groupedChannels = const {};
            _selectedGroup = null;
            _selectedSource = LiveTvSourceFilter.iptv;
            _searchQuery = '';
            _hasLoadError = false;
            _hasLoadedOnce = false;
            _error = null;
            _searchController.clear();
          });
        },
      ),
    );
  }

  void _showAddPlaylistForm() {
    setState(() {
      _channels = const [];
      _filteredChannels = const [];
      _groupedChannels = const {};
      _selectedGroup = null;
      _selectedSource = LiveTvSourceFilter.iptv;
      _searchQuery = '';
      _hasLoadError = false;
      _hasLoadedOnce = false;
      _error = null;
      _isLoading = false;
      _searchController.clear();
    });
  }

  void _log(String message) {
    debugPrint('[live_tv] $message');
  }

  void _resetListScroll() {
    if (!_scrollController.hasClients) return;
    _scrollController.jumpTo(0);
  }
}

class _LiveTvErrorState extends StatelessWidget {
  const _LiveTvErrorState({
    required this.message,
    required this.onRetry,
    required this.onAddNew,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onAddNew;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        EmptyState(title: 'Live TV failed to load', message: message),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.center,
          children: [
            PrimaryButton(label: 'Retry', onPressed: onRetry),
            SecondaryButton(label: 'Add New Playlist', onPressed: onAddNew),
          ],
        ),
      ],
    );
  }
}

class _EmptyPlaylistState extends StatelessWidget {
  const _EmptyPlaylistState({
    required this.controller,
    required this.onLoad,
    required this.onLoadPublic,
    this.error,
  });

  final TextEditingController controller;
  final VoidCallback onLoad;
  final VoidCallback onLoadPublic;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              LucideIcons.tv,
              size: 80,
              color: AppColors.textMuted.withValues(alpha: 0.35),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Add your IPTV Playlist',
              textAlign: TextAlign.center,
              style: AppTypography.sectionTitle.copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Enter an M3U URL to stream live TV channels directly in the app.',
              textAlign: TextAlign.center,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.huge),
            TextField(
              controller: controller,
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              decoration: _referenceInputDecoration(
                hintText: 'Paste playlist URL',
                prefixIcon: LucideIcons.link,
              ),
              onSubmitted: (_) => onLoad(),
            ),
            if (error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                error!,
                textAlign: TextAlign.center,
                style: AppTypography.caption.copyWith(color: AppColors.danger),
              ),
            ],
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Load Playlist',
                onPressed: onLoad,
                minimumSize: const Size(0, 50),
              ),
            ),
            const SizedBox(height: AppSpacing.huge),
            Row(
              children: [
                Expanded(child: Divider(color: AppColors.borderSubtle)),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text('OR', style: AppTypography.caption),
                ),
                Expanded(child: Divider(color: AppColors.borderSubtle)),
              ],
            ),
            const SizedBox(height: AppSpacing.huge),
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                label: 'Load Free Public Channels (iptv-org)',
                icon: const Icon(LucideIcons.globe),
                onPressed: onLoadPublic,
                minimumSize: const Size(0, 50),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _referenceInputDecoration({
  required String hintText,
  required IconData prefixIcon,
}) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: AppTypography.body.copyWith(
      color: AppColors.textPrimary.withValues(alpha: 0.3),
    ),
    filled: true,
    fillColor: AppColors.textPrimary.withValues(alpha: 0.1),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    prefixIcon: Icon(
      prefixIcon,
      color: AppColors.textPrimary.withValues(alpha: 0.5),
      size: 20,
    ),
  );
}

class _LiveTvToolbar extends StatelessWidget {
  const _LiveTvToolbar({
    required this.searchController,
    required this.selectedGroup,
    required this.selectedSource,
    required this.groups,
    required this.onSearchChanged,
    required this.onGroupSelected,
    required this.onSourceSelected,
    required this.onManagePlaylists,
  });

  final TextEditingController searchController;
  final String selectedGroup;
  final LiveTvSourceFilter selectedSource;
  final List<String> groups;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onGroupSelected;
  final ValueChanged<LiveTvSourceFilter> onSourceSelected;
  final VoidCallback onManagePlaylists;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: searchController,
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: _referenceInputDecoration(
                  hintText: 'Search channels...',
                  prefixIcon: LucideIcons.search,
                ),
                onChanged: onSearchChanged,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _CategoryButton(
                selectedGroup: selectedGroup,
                groups: groups,
                onGroupSelected: onGroupSelected,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.textPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.medium),
              ),
              child: IconButton(
                tooltip: 'Manage Playlists',
                onPressed: onManagePlaylists,
                icon: const Icon(
                  LucideIcons.list,
                  color: AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _LiveTvSourceSelector(
          selectedSource: selectedSource,
          onSourceSelected: onSourceSelected,
        ),
      ],
    );
  }
}

class _LiveTvSourceSelector extends StatelessWidget {
  const _LiveTvSourceSelector({
    required this.selectedSource,
    required this.onSourceSelected,
  });

  final LiveTvSourceFilter selectedSource;
  final ValueChanged<LiveTvSourceFilter> onSourceSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: LiveTvSourceFilter.values
            .map((source) {
              final selected = source == selectedSource;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  selected: selected,
                  label: Text(_sourceLabel(source)),
                  onSelected: (_) => onSourceSelected(source),
                  labelStyle: AppTypography.caption.copyWith(
                    color: selected ? Colors.black : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.textPrimary.withValues(
                    alpha: 0.08,
                  ),
                  side: BorderSide(
                    color: selected
                        ? AppColors.primary
                        : AppColors.textPrimary.withValues(alpha: 0.1),
                  ),
                ),
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

String _sourceLabel(LiveTvSourceFilter source) {
  return switch (source) {
    LiveTvSourceFilter.all => 'All',
    LiveTvSourceFilter.iptv => 'IPTV',
    LiveTvSourceFilter.tamilUltra => 'TamilUltra / Tamil',
    LiveTvSourceFilter.sportzx => 'SportzX / Sports',
  };
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.selectedGroup,
    required this.groups,
    required this.onGroupSelected,
  });

  final String selectedGroup;
  final List<String> groups;
  final ValueChanged<String> onGroupSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        onTap: () => _showCategoryPicker(context),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.textPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selectedGroup,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.body.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              Icon(
                LucideIcons.chevronDown,
                color: AppColors.textPrimary.withValues(alpha: 0.5),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCategoryPicker(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.panel),
        ),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Select Category',
                  style: AppTypography.sectionTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    final isSelected = group == selectedGroup;
                    return ListTile(
                      title: Text(
                        group,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.body.copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : AppColors.textPrimary,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(
                              LucideIcons.check,
                              color: AppColors.primary,
                              size: 20,
                            )
                          : null,
                      onTap: () {
                        onGroupSelected(group);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChannelList extends StatelessWidget {
  const _ChannelList({
    required this.controller,
    required this.channels,
    required this.onToggleFavorite,
    required this.onPlay,
  });

  final ScrollController controller;
  final List<IptvChannel> channels;
  final ValueChanged<IptvChannel> onToggleFavorite;
  final ValueChanged<IptvChannel> onPlay;

  @override
  Widget build(BuildContext context) {
    return DesktopScrollbar(
      controller: controller,
      child: ListView.builder(
        controller: controller,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: AppSpacing.massive),
        itemCount: channels.length,
        itemBuilder: (context, index) {
          final channel = channels[index];
          return RepaintBoundary(
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.xxl,
                right: AppSpacing.xxl,
                bottom: AppSpacing.md,
              ),
              child: Material(
                color: AppColors.textPrimary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: AppColors.textPrimary.withValues(alpha: 0.1),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.large),
                ),
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  leading: _ChannelLogo(channel: channel),
                  title: Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    channel.group,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textPrimary.withValues(alpha: 0.5),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: channel.isFavorite
                            ? 'Remove favorite'
                            : 'Add favorite',
                        onPressed: () => onToggleFavorite(channel),
                        icon: Icon(
                          channel.isFavorite
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: channel.isFavorite
                              ? AppColors.danger
                              : AppColors.textSecondary.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Icon(
                        LucideIcons.circlePlay,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ],
                  ),
                  onTap: () => onPlay(channel),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});

  final IptvChannel channel;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.medium),
      child: SizedBox.square(
        dimension: 48,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.26),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: channel.logo.isEmpty
              ? Icon(
                  LucideIcons.tv,
                  color: AppColors.textPrimary.withValues(alpha: 0.3),
                )
              : CachedNetworkImage(
                  imageUrl: channel.logo,
                  fit: BoxFit.contain,
                  errorWidget: (context, url, error) => Icon(
                    LucideIcons.tv,
                    color: AppColors.textPrimary.withValues(alpha: 0.3),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PlaylistManagerDialog extends StatefulWidget {
  const _PlaylistManagerDialog({
    required this.playlists,
    required this.onDelete,
    required this.onAddNew,
  });

  final List<IptvPlaylist> playlists;
  final ValueChanged<IptvPlaylist> onDelete;
  final VoidCallback onAddNew;

  @override
  State<_PlaylistManagerDialog> createState() => _PlaylistManagerDialogState();
}

class _PlaylistManagerDialogState extends State<_PlaylistManagerDialog> {
  late final List<IptvPlaylist> _playlists = List.of(widget.playlists);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manage Playlists'),
      content: SizedBox(
        width: 620,
        child: _playlists.isEmpty
            ? const EmptyState(
                title: 'No playlists loaded.',
                message: 'Add an M3U playlist to load channels.',
              )
            : ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (context, index) {
                  final playlist = _playlists[index];
                  return ListTile(
                    leading: const Icon(Icons.list),
                    title: Text(playlist.name),
                    subtitle: Text(
                      playlist.url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: IconButton(
                      tooltip: 'Delete playlist',
                      onPressed: () {
                        widget.onDelete(playlist);
                        setState(() => _playlists.removeAt(index));
                      },
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        ElevatedButton.icon(
          onPressed: () {
            widget.onAddNew();
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add New Playlist'),
        ),
      ],
    );
  }
}
