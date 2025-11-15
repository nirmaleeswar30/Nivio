import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/providers/search_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/widgets/search_result_card.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _isLoadingMore = false;
  bool _isInitialLoading = false;
  List<SearchResult> _allResults = [];
  int _currentPage = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final scrollPosition = _scrollController.position.pixels;
    final maxExtent = _scrollController.position.maxScrollExtent;
    
    // Trigger when 500px from bottom
    if (scrollPosition >= maxExtent - 500) {
      _loadMoreResults();
    }
  }

  Future<void> _loadMoreResults() async {
    // Prevent multiple simultaneous loads
    if (_isLoadingMore) return;
    
    // Check if we have more pages to load
    if (_currentPage >= _totalPages) return;
    
    print('📄 Loading page ${_currentPage + 1} of $_totalPages');
    
    setState(() => _isLoadingMore = true);
    
    try {
      final query = ref.read(searchQueryProvider);
      final language = ref.read(searchLanguageFilterProvider);
      final sortBy = ref.read(searchSortProvider);
      final tmdb = ref.read(tmdbServiceProvider);
      
      // Fetch next page in background
      final nextPage = _currentPage + 1;
      final results = await tmdb.search(query, page: nextPage, language: language, sortBy: sortBy);
      
      print('✅ Loaded ${results.results.length} more results for page $nextPage');
      
      if (mounted) {
        setState(() {
          _allResults.addAll(results.results);
          _currentPage = nextPage;
          _isLoadingMore = false;
        });
        
        // If we got very few results (likely filtered out people), try loading next page automatically
        if (results.results.length < 10 && _currentPage < _totalPages) {
          print('⚠️ Only got ${results.results.length} results, auto-loading next page...');
          Future.delayed(const Duration(milliseconds: 100), _loadMoreResults);
        }
      }
    } catch (e) {
      print('❌ Failed to load more results: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearch(String value) {
    if (value.trim().isNotEmpty) {
      ref.read(searchQueryProvider.notifier).state = value.trim();
      setState(() {
        _allResults = [];
        _currentPage = 1;
        _isInitialLoading = true;
      });
      _performInitialSearch();
    }
  }

  Future<void> _performInitialSearch() async {
    try {
      final query = ref.read(searchQueryProvider);
      final language = ref.read(searchLanguageFilterProvider);
      final sortBy = ref.read(searchSortProvider);
      final tmdb = ref.read(tmdbServiceProvider);
      
      print('🔍 Initial search for "$query"');
      
      final results = await tmdb.search(query, page: 1, language: language, sortBy: sortBy);
      
      print('✅ Found ${results.results.length} results (Page 1/${results.totalPages})');
      
      if (mounted) {
        setState(() {
          _allResults = List.from(results.results); // Create modifiable copy
          _currentPage = 1;
          _totalPages = results.totalPages;
          _isInitialLoading = false;
        });
        
        // If first page has very few results (likely filtered out people), auto-load more
        if (results.results.length < 10 && _totalPages > 1) {
          print('⚠️ Only got ${results.results.length} results on page 1, auto-loading page 2...');
          Future.delayed(const Duration(milliseconds: 100), _loadMoreResults);
        }
      }
    } catch (e) {
      print('❌ Search failed: $e');
      if (mounted) {
        setState(() => _isInitialLoading = false);
      }
    }
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) {
        String? selectedLanguage = ref.read(searchLanguageFilterProvider);
        String? selectedSort = ref.read(searchSortProvider);
        
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: NivioTheme.netflixDarkGrey,
              title: const Text('Filter & Sort', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language Filter
                    const Text('Language', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip('All', selectedLanguage == null, () {
                          setDialogState(() => selectedLanguage = null);
                        }),
                        _buildFilterChip('English', selectedLanguage == 'en', () {
                          setDialogState(() => selectedLanguage = 'en');
                        }),
                        _buildFilterChip('Tamil', selectedLanguage == 'ta', () {
                          setDialogState(() => selectedLanguage = 'ta');
                        }),
                        _buildFilterChip('Telugu', selectedLanguage == 'te', () {
                          setDialogState(() => selectedLanguage = 'te');
                        }),
                        _buildFilterChip('Hindi', selectedLanguage == 'hi', () {
                          setDialogState(() => selectedLanguage = 'hi');
                        }),
                        _buildFilterChip('Korean', selectedLanguage == 'ko', () {
                          setDialogState(() => selectedLanguage = 'ko');
                        }),
                        _buildFilterChip('Japanese', selectedLanguage == 'ja', () {
                          setDialogState(() => selectedLanguage = 'ja');
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Sort Options
                    const Text('Sort By', style: TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip('Default', selectedSort == null, () {
                          setDialogState(() => selectedSort = null);
                        }),
                        _buildFilterChip('Rating', selectedSort == 'popularity', () {
                          setDialogState(() => selectedSort = 'popularity');
                        }),
                        _buildFilterChip('Title', selectedSort == 'title', () {
                          setDialogState(() => selectedSort = 'title');
                        }),
                        _buildFilterChip('Year', selectedSort == 'year', () {
                          setDialogState(() => selectedSort = 'year');
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(searchLanguageFilterProvider.notifier).state = selectedLanguage;
                    ref.read(searchSortProvider.notifier).state = selectedSort;
                    Navigator.pop(dialogContext);
                    // Re-search with new filters
                    _performInitialSearch();
                  },
                  child: const Text('Apply', style: TextStyle(color: NivioTheme.netflixRed)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? NivioTheme.netflixRed : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NivioTheme.netflixRed : Colors.white.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);
    final languageFilter = ref.watch(searchLanguageFilterProvider);
    final sortBy = ref.watch(searchSortProvider);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: NivioTheme.netflixBlack,
        title: TextField(
          controller: _controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search for movies or TV shows...',
            hintStyle: TextStyle(color: NivioTheme.netflixGrey),
            border: InputBorder.none,
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, color: Colors.white),
                    onPressed: () {
                      _controller.clear();
                      ref.read(searchQueryProvider.notifier).state = '';
                      setState(() {
                        _allResults = [];
                        _currentPage = 1;
                        _totalPages = 1;
                      });
                    },
                  )
                : null,
          ),
          onChanged: (value) {
            setState(() {});
          },
          onSubmitted: _onSearch,
        ),
        actions: [
          // Filter button with badge if filters are active
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.filter_list, color: Colors.white),
                onPressed: _showFilterDialog,
              ),
              if (languageFilter != null || sortBy != null)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: NivioTheme.netflixRed,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => _onSearch(_controller.text),
          ),
        ],
      ),
      body: query.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.search,
                    size: 80,
                    color: NivioTheme.netflixGrey,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Search for movies and TV shows',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type in the search box above to get started',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            )
          : _isInitialLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: NivioTheme.netflixRed,
                  ),
                )
              : _allResults.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.movie_outlined,
                            size: 80,
                            color: NivioTheme.netflixGrey,
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'No results found',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Try a different search term',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                  ),
                )
              : Column(
                  children: [
                    // Results count and filters info
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      color: Colors.white.withOpacity(0.05),
                      child: Row(
                        children: [
                          Text(
                            '${_allResults.length} results',
                            style: const TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          if (languageFilter != null || sortBy != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: NivioTheme.netflixRed.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Filtered',
                                style: const TextStyle(
                                  color: NivioTheme.netflixRed,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          Text(
                            'Page $_currentPage/$_totalPages',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Results grid with key to preserve scroll position
                    Expanded(
                      child: GridView.builder(
                        key: PageStorageKey<String>('search_grid_$query'),
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.65,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 16,
                        ),
                        addAutomaticKeepAlives: true,
                        addRepaintBoundaries: true,
                        itemCount: _allResults.length + (_isLoadingMore ? 3 : 0),
                        itemBuilder: (context, index) {
                          if (index >= _allResults.length) {
                            // Loading indicator at the bottom (3 placeholders)
                            return Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  color: NivioTheme.netflixRed,
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final item = _allResults[index];
                          return SearchResultCard(
                            key: ValueKey('${item.mediaType}_${item.id}'),
                            media: item,
                          );
                        },
                      ),
                    ),
                  ],
                ),
    );
  }
}
