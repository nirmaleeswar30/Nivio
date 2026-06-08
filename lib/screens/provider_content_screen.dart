import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/widgets/search_result_card.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

class ProviderContentScreen extends ConsumerStatefulWidget {
  final int providerId;
  final String providerName;

  const ProviderContentScreen({
    super.key,
    required this.providerId,
    required this.providerName,
  });

  @override
  ConsumerState<ProviderContentScreen> createState() => _ProviderContentScreenState();
}

class _ProviderContentScreenState extends ConsumerState<ProviderContentScreen> {
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _isSearching = false;
  
  List<SearchResult> _items = [];
  List<SearchResult> _searchResults = [];
  
  String _mediaType = 'movie'; // 'movie' or 'tv'
  String _searchQuery = '';
  
  int _currentPage = 1;
  final ScrollController _scrollController = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _fetchContent();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_searchQuery.isNotEmpty) return; // Disable infinite scroll during deep search
    
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_isLoading && !_isFetchingMore) {
        _loadMore();
      }
    }
  }

  Future<void> _loadMore() async {
    setState(() {
      _isFetchingMore = true;
    });

    _currentPage++;
    final tmdbService = ref.read(tmdbServiceProvider);
    
    try {
      final results = await tmdbService.getByProvider(widget.providerId, mediaType: _mediaType, page: _currentPage);
      if (mounted) {
        setState(() {
          final newItems = results.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            map['media_type'] = _mediaType;
            return SearchResult.fromJson(map);
          }).toList();
          
          _items.addAll(newItems);
          
          // Remove duplicates
          final seen = <int>{};
          _items.retainWhere((item) => seen.add(item.id));
          
          _isFetchingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingMore = false;
          _currentPage--; // Revert page count on error
        });
      }
    }
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
    });

    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults.clear();
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 700), () {
      _performDeepSearch(query);
    });
  }

  Future<void> _performDeepSearch(String query) async {
    setState(() {
      _isSearching = true;
      _isLoading = true;
    });

    final tmdbService = ref.read(tmdbServiceProvider);
    final results = await tmdbService.searchByProvider(query, widget.providerId, _mediaType);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchContent() async {
    setState(() {
      _isLoading = true;
      _searchQuery = '';
      _currentPage = 1;
      _items.clear();
    });

    final tmdbService = ref.read(tmdbServiceProvider);
    
    try {
      final results = await tmdbService.getByProvider(widget.providerId, mediaType: _mediaType, page: _currentPage);
      if (mounted) {
        setState(() {
          _items = results.map((item) {
            final map = Map<String, dynamic>.from(item as Map);
            map['media_type'] = _mediaType;
            return SearchResult.fromJson(map);
          }).toList();
          
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0F14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0F14),
        elevation: 0,
        leading: IconButton(
          icon: const PhosphorIcon(PhosphorIconsRegular.caretLeft, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.providerName,
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                _buildTab('Movies', 'movie'),
                const SizedBox(width: 12),
                _buildTab('TV Shows', 'tv'),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22252A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Colors.white38, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context)),
            )
          : Builder(
              builder: (context) {
                final displayItems = _isSearching ? _searchResults : _items;
                    
                if (displayItems.isEmpty) {
                  return const Center(
                    child: Text(
                      'No content found.',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }
                
                return Column(
                  children: [
                    Expanded(
                      child: GridView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 0.68,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                        ),
                        itemCount: displayItems.length,
                        itemBuilder: (context, index) {
                          final item = displayItems[index];
                          return SearchResultCard(media: item);
                        },
                      ),
                    ),
                    if (_isFetchingMore && !_isSearching)
                      const Padding(
                        padding: EdgeInsets.all(16.0),
                        child: CircularProgressIndicator(),
                      ),
                  ],
                );
              }
            ),
    );
  }

  Widget _buildTab(String title, String type) {
    final isSelected = _mediaType == type;
    return GestureDetector(
      onTap: () {
        if (!isSelected) {
          setState(() {
            _mediaType = type;
          });
          _fetchContent();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? NivioTheme.accentColorOf(context) : const Color(0xFF22252A),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.black : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
