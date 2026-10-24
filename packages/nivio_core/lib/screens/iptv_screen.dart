import 'package:nivio/core/app_platform.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import '../models/iptv_channel.dart';
import '../services/iptv_service.dart';
import 'package:cached_network_image/cached_network_image.dart';

class IptvScreen extends ConsumerStatefulWidget {
  /// When embedded inside the TV/Sports tab, skip the outer Scaffold and the
  /// top safe-area padding (the host provides both).
  final bool embedded;
  const IptvScreen({super.key, this.embedded = false});

  @override
  ConsumerState<IptvScreen> createState() => _IptvScreenState();
}

class _IptvScreenState extends ConsumerState<IptvScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  List<IptvChannel> _channels = [];
  List<IptvChannel> _filteredChannels = [];
  Map<String, List<IptvChannel>> _groupedChannels = {};
  
  String _searchQuery = '';
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _loadSavedPlaylist();
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedPlaylist() async {
    setState(() => _isLoading = true);
    try {
      final service = ref.read(iptvServiceProvider);
      final channels = await service.loadAllChannels();
      if (channels.isNotEmpty) {
        _processChannels(channels);
      }
    } catch (e) {
      debugPrint('Error loading saved playlists: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchPlaylist(String url, {String name = 'New Playlist'}) async {
    if (url.isEmpty) return;
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    try {
      final service = ref.read(iptvServiceProvider);
      await service.fetchAndSavePlaylist(url, name);
      await _loadSavedPlaylist();
    } catch (e) {
      setState(() {
        _error = 'Failed to load playlist. Make sure the URL is valid and accessible.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
  
  void _processChannels(List<IptvChannel> channels) {
    // Group channels
    final Map<String, List<IptvChannel>> grouped = {};
    for (var c in channels) {
      if (!grouped.containsKey(c.group)) {
        grouped[c.group] = [];
      }
      grouped[c.group]!.add(c);
    }
    
    // Sort groups alphabetically
    final sortedGroups = Map.fromEntries(
      grouped.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
    );

    setState(() {
      _channels = channels;
      _groupedChannels = sortedGroups;
      _filterChannels();
    });
  }

  void _filterChannels() {
    List<IptvChannel> result = _channels;
    
    if (_selectedGroup == 'Favorites') {
      result = result.where((c) => c.isFavorite).toList();
    } else if (_selectedGroup != null && _selectedGroup != 'All') {
      result = result.where((c) => c.group == _selectedGroup).toList();
    }
    
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result.where((c) => c.name.toLowerCase().contains(query)).toList();
    }
    
    setState(() {
      _filteredChannels = result;
    });
  }

  Future<void> _toggleFavorite(IptvChannel channel) async {
    final service = ref.read(iptvServiceProvider);
    await service.toggleFavorite(channel.url);
    await _loadSavedPlaylist(); // Reload to refresh list and sorting
  }

  Future<void> _showPlaylistManager() async {
    final service = ref.read(iptvServiceProvider);
    final playlists = await service.getPlaylists();
    
    if (!mounted) return;
    final isDesktop = AppPlatform.useDesktopLayout;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      isScrollControlled: true,
      constraints: BoxConstraints(maxWidth: isDesktop ? 520 : double.infinity),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.6,
              maxChildSize: 0.9,
              minChildSize: 0.4,
              builder: (context, scrollController) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text(
                        'Manage Playlists',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (playlists.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('No playlists loaded.', style: TextStyle(color: Colors.white70)),
                        ),
                      )
                    else
                      Expanded(
                        child: AppListView.builder(
                          controller: scrollController,
                          cacheExtent: 250,
                          scrollSpeed: 2.0,
                          silkyScrollDuration: const Duration(milliseconds: 500),
                          animationCurve: Curves.easeOutQuart,
                          itemCount: playlists.length,
                          itemBuilder: (context, index) {
                            final p = playlists[index];
                            return ListTile(
                              leading: const Icon(PhosphorIconsRegular.list, color: Colors.white54),
                              title: Text(p.name, style: const TextStyle(color: Colors.white)),
                              subtitle: Text(p.url, style: const TextStyle(color: Colors.white54, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                              trailing: IconButton(
                                icon: const Icon(PhosphorIconsRegular.trash, color: Colors.red),
                                onPressed: () async {
                                  await service.deletePlaylist(p.id);
                                  setSheetState(() {
                                    playlists.removeAt(index);
                                  });
                                  if (playlists.isEmpty) {
                                    setState(() {
                                      _channels = [];
                                      _filteredChannels = [];
                                      _groupedChannels = {};
                                    });
                                  } else {
                                    await _loadSavedPlaylist();
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          setState(() {
                            _channels = []; // Triggers empty state to add new
                          });
                        },
                        icon: const Icon(PhosphorIconsRegular.plus),
                        label: const Text('Add New Playlist'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivioTheme.accentColorOf(context),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _playChannel(IptvChannel channel) {
    final uri = Uri(
      path: '/player/0',
      queryParameters: {
        'directStreamUrl': channel.url,
        'directStreamTitle': channel.name,
        'isLive': 'true',
      },
    );
    context.push(uri.toString());
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;

    final body = Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151922), NivioTheme.netflixBlack],
        ),
      ),
      child: SafeArea(
        top: !widget.embedded,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _channels.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 24, 24, 24, 24),
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 500),
                        child: _buildEmptyState(),
                      ),
                    ),
                  )
                : _buildPopulatedState(isDesktop),
      ),
    );

    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: body,
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 24.0),
          child: Center(
            child: Text(
              'Live IPTV',
              style: TextStyle(
                color: NivioTheme.netflixWhite,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: Icon(
              PhosphorIconsRegular.television,
              size: 48,
              color: NivioTheme.accentColorOf(context),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Add your IPTV Playlist',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Enter an M3U URL to stream live TV channels directly in the app.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white60,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 28),
        TvTextFieldGate(builder: (context, focusNode) => TextField(focusNode: focusNode,
          controller: _urlController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'https://example.com/playlist.m3u',
            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
            ),
            prefixIcon: Icon(
              PhosphorIconsRegular.link,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
          onSubmitted: _fetchPlaylist,
        ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            _error!,
            style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _fetchPlaylist(_urlController.text.trim()),
          icon: const Icon(PhosphorIconsRegular.downloadSimple, size: 20),
          label: const Text('Load Playlist'),
          style: FilledButton.styleFrom(
            backgroundColor: NivioTheme.accentColorOf(context),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(child: Divider(color: Colors.white12)),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            Expanded(child: Divider(color: Colors.white12)),
          ],
        ),
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Free channel catalogs',
            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.3),
          ),
        ),
        const SizedBox(height: 10),
        ..._curatedSources.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _quickAddButton(s),
            )),
      ],
    );
  }

  // Curated free, direct-m3u8 catalogs users can load in one tap.
  static const List<Map<String, String>> _curatedSources = [
    {'label': 'Pluto TV (US)', 'name': 'Pluto TV', 'url': 'https://i.mjh.nz/PlutoTV/us.m3u8'},
    {'label': 'Samsung TV Plus (US)', 'name': 'Samsung TV Plus', 'url': 'https://i.mjh.nz/SamsungTVPlus/us.m3u8'},
    {'label': 'Plex Live TV', 'name': 'Plex', 'url': 'https://i.mjh.nz/Plex/all.m3u8'},
    {'label': 'All Free Channels (iptv-org)', 'name': 'iptv-org', 'url': 'https://iptv-org.github.io/iptv/index.m3u'},
  ];

  Widget _quickAddButton(Map<String, String> source) {
    return OutlinedButton.icon(
      onPressed: () {
        _urlController.text = source['url']!;
        _fetchPlaylist(source['url']!, name: source['name'] ?? 'Channels');
      },
      icon: const PhosphorIcon(PhosphorIconsRegular.globe, size: 20),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(source['label']!),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        minimumSize: const Size(double.infinity, 52),
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildPopulatedState(bool isDesktop) {
    final groups = ['All', 'Favorites', ..._groupedChannels.keys];

    return Column(
      children: [
        // Top Header
        Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16.0, widget.embedded ? 4.0 : 16.0, 16.0, 12.0),
          child: Row(
            children: [
              Text(
                widget.embedded ? 'TV Channels' : 'Live IPTV',
                style: const TextStyle(
                  color: NivioTheme.netflixWhite,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _showPlaylistManager,
                icon: const PhosphorIcon(PhosphorIconsRegular.list, size: 18),
                label: Text('${_channels.length} Channels'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
              ),
            ],
          ),
        ),

        // Search and Filter Bar
        Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16.0, 0, 16.0, 12.0),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 600 : double.infinity),
                  child: TvTextFieldGate(builder: (context, focusNode) => TextField(focusNode: focusNode,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search channels...',
                      hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.06),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: NivioTheme.accentColorOf(context)),
                      ),
                      prefixIcon: Icon(
                        PhosphorIconsRegular.magnifyingGlass,
                        color: Colors.white.withValues(alpha: 0.5),
                        size: 20,
                      ),
                    ),
                    onChanged: (val) {
                      _searchQuery = val;
                      _filterChannels();
                    },
                  ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: isDesktop ? 220 : 130,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: NivioTheme.netflixDarkGrey,
                        constraints: BoxConstraints(maxWidth: isDesktop ? 500 : double.infinity),
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (context) {
                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'Select Category',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: AppListView.builder(
                                  cacheExtent: 250,
                                  scrollSpeed: 2.0,
                                  silkyScrollDuration: const Duration(milliseconds: 500),
                                  animationCurve: Curves.easeOutQuart,
                                  itemCount: groups.length,
                                  itemBuilder: (context, index) {
                                    final g = groups[index];
                                    final isSelected = (_selectedGroup ?? 'All') == g;
                                    return ListTile(
                                      title: Text(
                                        g,
                                        style: TextStyle(
                                          color: isSelected ? NivioTheme.accentColorOf(context) : Colors.white,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                        ),
                                      ),
                                      trailing: isSelected
                                          ? Icon(Icons.check, color: NivioTheme.accentColorOf(context))
                                          : null,
                                      onTap: () {
                                        setState(() {
                                          _selectedGroup = g;
                                          _filterChannels();
                                        });
                                        Navigator.pop(context);
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedGroup ?? 'All',
                              style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(PhosphorIconsRegular.caretDown, color: Colors.white.withValues(alpha: 0.5), size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        
        // Channel List / Grid
        Expanded(
          child: _filteredChannels.isEmpty
              ? Center(
                  child: Padding(
                    padding: EdgeInsets.only(left: isDesktop ? 68 : 0),
                    child: Text(
                      'No channels found',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
                    ),
                  ),
                )
              : isDesktop
                  ? AppGridView.builder(
                      padding: const EdgeInsets.fromLTRB(68, 4, 16, 24),
                      cacheExtent: 1000,
                      scrollSpeed: 2.0,
                      silkyScrollDuration: const Duration(milliseconds: 500),
                      animationCurve: Curves.easeOutQuart,
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 380,
                        childAspectRatio: 4.2,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _filteredChannels.length,
                      itemBuilder: (context, index) {
                        final channel = _filteredChannels[index];
                        return _ChannelCard(
                          key: ValueKey(channel.url),
                          channel: channel,
                          onPlay: () => _playChannel(channel),
                          onToggleFavorite: () => _toggleFavorite(channel),
                        );
                      },
                    )
                  : AppListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      cacheExtent: 350,
                      scrollSpeed: 2.0,
                      silkyScrollDuration: const Duration(milliseconds: 500),
                      animationCurve: Curves.easeOutQuart,
                      itemCount: _filteredChannels.length,
                      itemBuilder: (context, index) {
                        final channel = _filteredChannels[index];
                        return _ChannelCard(
                          key: ValueKey(channel.url),
                          channel: channel,
                          onPlay: () => _playChannel(channel),
                          onToggleFavorite: () => _toggleFavorite(channel),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

class _ChannelCard extends StatefulWidget {
  final IptvChannel channel;
  final VoidCallback onPlay;
  final VoidCallback onToggleFavorite;

  const _ChannelCard({
    super.key,
    required this.channel,
    required this.onPlay,
    required this.onToggleFavorite,
  });

  @override
  State<_ChannelCard> createState() => _ChannelCardState();
}

class _ChannelCardState extends State<_ChannelCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final channel = widget.channel;
    final accent = NivioTheme.accentColorOf(context);

    return RepaintBoundary(
      child: DpadFocusable(
        onActivate: widget.onPlay,
        child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onPlay,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _isHovered ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _isHovered
                    ? const Color(0xFF1B202D)
                    : Colors.white.withValues(alpha: 0.04),
                border: Border.all(
                  color: _isHovered
                      ? accent.withValues(alpha: 0.45)
                      : Colors.white.withValues(alpha: 0.08),
                  width: _isHovered ? 1.5 : 1.0,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                      ),
                      child: channel.logo.isNotEmpty
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: CachedNetworkImage(
                                imageUrl: channel.logo,
                                fit: BoxFit.contain,
                                errorWidget: (context, url, error) => Icon(
                                  PhosphorIconsRegular.television,
                                  color: Colors.white.withValues(alpha: 0.3),
                                  size: 22,
                                ),
                              ),
                            )
                          : Icon(
                              PhosphorIconsRegular.television,
                              color: Colors.white.withValues(alpha: 0.3),
                              size: 22,
                            ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            channel.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            channel.group,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.45),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: PhosphorIcon(
                        channel.isFavorite ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                        color: channel.isFavorite ? Colors.redAccent : Colors.white38,
                        size: 20,
                      ),
                      onPressed: widget.onToggleFavorite,
                    ),
                    const SizedBox(width: 4),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isHovered
                            ? accent
                            : accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        boxShadow: _isHovered
                            ? [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        PhosphorIconsRegular.play,
                        color: _isHovered ? Colors.white : accent,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
