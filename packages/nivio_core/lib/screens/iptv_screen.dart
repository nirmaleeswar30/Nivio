import 'dart:io';
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
  const IptvScreen({super.key});

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
    
    showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      isScrollControlled: true,
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
    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: SafeArea(
        child: Stack(
          children: [
            // Background Logo
            Center(
              child: Opacity(
                opacity: 0.05,
                child: Image.asset(
                  'assets/images/nivio-dark.png',
                  width: MediaQuery.of(context).size.width * 0.6,
                ),
              ),
            ),
            // Content
            _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : _channels.isEmpty 
                    ? _buildEmptyState()
                    : _buildPopulatedState(),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 60),
          Icon(
            PhosphorIconsRegular.television,
            size: 80,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 24),
          const Text(
            'Add your IPTV Playlist',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter an M3U URL to stream live TV channels directly in the app.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white60,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 40),
          TextField(
            controller: _urlController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'https://example.com/playlist.m3u',
              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
              filled: true,
              fillColor: NivioTheme.netflixDarkGrey,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              prefixIcon: Icon(
                PhosphorIconsRegular.link,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            onSubmitted: _fetchPlaylist,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => _fetchPlaylist(_urlController.text.trim()),
            style: ElevatedButton.styleFrom(
              backgroundColor: NivioTheme.accentColorOf(context),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Load Playlist',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 40),
          const Row(
            children: [
              Expanded(child: Divider(color: Colors.white24)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text('OR', style: TextStyle(color: Colors.white60)),
              ),
              Expanded(child: Divider(color: Colors.white24)),
            ],
          ),
          const SizedBox(height: 40),
          OutlinedButton.icon(
            onPressed: () {
              // https://iptv-org.github.io/iptv/index.m3u
              _urlController.text = 'https://iptv-org.github.io/iptv/index.m3u';
              _fetchPlaylist(_urlController.text);
            },
            icon: const PhosphorIcon(PhosphorIconsRegular.globe, size: 20),
            label: const Text('Load Free Public Channels (iptv-org)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPopulatedState() {
    final groups = ['All', 'Favorites', ..._groupedChannels.keys];
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;

    return Column(
      children: [
        // Search and Filter Bar
        Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16.0, 16.0, 16.0, 8.0),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search channels...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.1),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
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
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: NivioTheme.netflixDarkGrey,
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
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _selectedGroup ?? 'All',
                              style: const TextStyle(color: Colors.white, fontSize: 14),
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
              const SizedBox(width: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: IconButton(
                  icon: PhosphorIcon(PhosphorIconsRegular.list, color: Colors.white70, size: 20),
                  onPressed: _showPlaylistManager,
                  tooltip: 'Manage Playlists',
                ),
              ),
            ],
          ),
        ),
        
        // Channel List
        Expanded(
          child: _filteredChannels.isEmpty
              ? Center(
                  child: Text(
                    'No channels found',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                )
              : AppListView.builder(
                  padding: const EdgeInsets.all(16),
                  cacheExtent: 250,
                  scrollSpeed: 2.0,
                  silkyScrollDuration: const Duration(milliseconds: 500),
                  animationCurve: Curves.easeOutQuart,
                  itemCount: _filteredChannels.length,
                  itemBuilder: (context, index) {
                    final channel = _filteredChannels[index];
                    return RepaintBoundary(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: channel.logo.isNotEmpty
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: CachedNetworkImage(
                                      imageUrl: channel.logo,
                                      fit: BoxFit.contain,
                                      errorWidget: (context, url, error) => Icon(
                                        PhosphorIconsRegular.television,
                                        color: Colors.white.withValues(alpha: 0.3),
                                      ),
                                    ),
                                  )
                                : Icon(
                                    PhosphorIconsRegular.television,
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                          ),
                          title: Text(
                            channel.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          subtitle: Text(
                            channel.group,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: PhosphorIcon(
                                  channel.isFavorite ? PhosphorIconsFill.heart : PhosphorIconsRegular.heart,
                                  color: channel.isFavorite ? Colors.red : Colors.white54,
                                ),
                                onPressed: () => _toggleFavorite(channel),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                PhosphorIconsRegular.playCircle,
                                color: NivioTheme.accentColorOf(context),
                              ),
                            ],
                          ),
                          onTap: () => _playChannel(channel),
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
