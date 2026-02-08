import 'dart:async';
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
  Timer? _searchDebounce;
  bool _isLoadingMore = false;
  bool _isInitialLoading = false;
  List<SearchResult> _allResults = [];
  int _currentPage = 1;
  int _totalPages = 1;
  int _searchRequestId = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
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

    final query = ref.read(searchQueryProvider);
    if (query.isEmpty) return;

    setState(() => _isLoadingMore = true);

    try {
      final language = ref.read(searchLanguageFilterProvider);
      final sortBy = ref.read(searchSortProvider);
      final tmdb = ref.read(tmdbServiceProvider);

      // Fetch next page in background
      final nextPage = _currentPage + 1;
      final results = await tmdb.search(
        query,
        page: nextPage,
        language: language,
        sortBy: sortBy,
      );

      if (mounted) {
        final activeQuery = ref.read(searchQueryProvider);
        if (activeQuery != query) {
          setState(() => _isLoadingMore = false);
          return;
        }

        setState(() {
          _allResults = _mergeUniqueResults(_allResults, results.results);
          _currentPage = nextPage;
          _isLoadingMore = false;
        });

        // If this page is sparse, auto-load one more page.
        if (results.results.length < 10 && _currentPage < _totalPages) {
          Future.delayed(const Duration(milliseconds: 100), _loadMoreResults);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _onSearch(String value) {
    final query = value.trim();
    if (query.isEmpty) return;

    _searchDebounce?.cancel();
    FocusScope.of(context).unfocus();
    ref.read(searchQueryProvider.notifier).state = query;
    setState(() {
      _allResults = [];
      _currentPage = 1;
      _totalPages = 1;
      _isInitialLoading = true;
    });
    _performInitialSearch();
  }

  void _onQueryChanged(String value) {
    setState(() {});

    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      ref.read(searchQueryProvider.notifier).state = '';
      setState(() {
        _allResults = [];
        _currentPage = 1;
        _totalPages = 1;
        _isInitialLoading = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      _onSearch(query);
    });
  }

  Future<void> _performInitialSearch() async {
    final requestId = ++_searchRequestId;
    try {
      final query = ref.read(searchQueryProvider);
      final language = ref.read(searchLanguageFilterProvider);
      final sortBy = ref.read(searchSortProvider);
      final tmdb = ref.read(tmdbServiceProvider);

      final results = await tmdb.search(
        query,
        page: 1,
        language: language,
        sortBy: sortBy,
      );

      if (mounted && requestId == _searchRequestId) {
        setState(() {
          _allResults = List.from(results.results);
          _currentPage = 1;
          _totalPages = results.totalPages;
          _isInitialLoading = false;
        });

        if (results.results.length < 10 && _totalPages > 1) {
          Future.delayed(const Duration(milliseconds: 100), _loadMoreResults);
        }
      }
    } catch (_) {
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
              title: const Text(
                'Filter & Sort',
                style: TextStyle(color: Colors.white),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Language Filter
                    const Text(
                      'Language',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip('All', selectedLanguage == null, () {
                          setDialogState(() => selectedLanguage = null);
                        }),
                        _buildFilterChip(
                          'English',
                          selectedLanguage == 'en',
                          () {
                            setDialogState(() => selectedLanguage = 'en');
                          },
                        ),
                        _buildFilterChip('Tamil', selectedLanguage == 'ta', () {
                          setDialogState(() => selectedLanguage = 'ta');
                        }),
                        _buildFilterChip(
                          'Telugu',
                          selectedLanguage == 'te',
                          () {
                            setDialogState(() => selectedLanguage = 'te');
                          },
                        ),
                        _buildFilterChip('Hindi', selectedLanguage == 'hi', () {
                          setDialogState(() => selectedLanguage = 'hi');
                        }),
                        _buildFilterChip(
                          'Korean',
                          selectedLanguage == 'ko',
                          () {
                            setDialogState(() => selectedLanguage = 'ko');
                          },
                        ),
                        _buildFilterChip(
                          'Japanese',
                          selectedLanguage == 'ja',
                          () {
                            setDialogState(() => selectedLanguage = 'ja');
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Sort Options
                    const Text(
                      'Sort By',
                      style: TextStyle(color: Colors.white70, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildFilterChip('Default', selectedSort == null, () {
                          setDialogState(() => selectedSort = null);
                        }),
                        _buildFilterChip(
                          'Rating',
                          selectedSort == 'popularity',
                          () {
                            setDialogState(() => selectedSort = 'popularity');
                          },
                        ),
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
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    ref.read(searchLanguageFilterProvider.notifier).state =
                        selectedLanguage;
                    ref.read(searchSortProvider.notifier).state = selectedSort;
                    Navigator.pop(dialogContext);
                    if (_controller.text.trim().isNotEmpty) {
                      _onSearch(_controller.text);
                    }
                  },
                  child: const Text(
                    'Apply',
                    style: TextStyle(color: NivioTheme.netflixRed),
                  ),
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
          color: isSelected
              ? NivioTheme.netflixRed
              : Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? NivioTheme.netflixRed
                : Colors.white.withValues(alpha: 0.3),
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
    final hasFilters = languageFilter != null || sortBy != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: NivioTheme.netflixBlack,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 76,
        titleSpacing: 12,
        title: _buildSearchField(),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.tune_rounded, color: Colors.white),
                onPressed: _showFilterDialog,
              ),
              if (hasFilters)
                Positioned(
                  right: 10,
                  top: 12,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: NivioTheme.netflixRed,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black, width: 1.2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFF1A1A1A),
              NivioTheme.netflixBlack,
              NivioTheme.netflixBlack,
            ],
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          child: query.isEmpty
              ? _buildStartState()
              : _isInitialLoading
              ? const Center(
                  child: CircularProgressIndicator(
                    color: NivioTheme.netflixRed,
                  ),
                )
              : _allResults.isEmpty
              ? _buildNoResultsState(query)
              : _buildResultsState(query, languageFilter, sortBy),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 15),
        decoration: InputDecoration(
          hintText: 'Search movies, shows, actors...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: Colors.white.withValues(alpha: 0.7),
          ),
          suffixIcon: _controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  onPressed: () {
                    _searchDebounce?.cancel();
                    _controller.clear();
                    ref.read(searchQueryProvider.notifier).state = '';
                    setState(() {
                      _allResults = [];
                      _currentPage = 1;
                      _totalPages = 1;
                      _isInitialLoading = false;
                    });
                  },
                )
              : null,
        ),
        onChanged: _onQueryChanged,
        onSubmitted: _onSearch,
      ),
    );
  }

  Widget _buildStartState() {
    const quickQueries = [
      'Interstellar',
      'Breaking Bad',
      'Money Heist',
      'Korean drama',
      'Anime',
      'Tamil',
    ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      NivioTheme.netflixRed.withValues(alpha: 0.35),
                      NivioTheme.netflixRed.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.travel_explore_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Find Something Worth Watching',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Search globally across movies and series.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: quickQueries
                    .map(
                      (item) => ActionChip(
                        backgroundColor: Colors.white.withValues(alpha: 0.08),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        label: Text(
                          item,
                          style: const TextStyle(color: Colors.white),
                        ),
                        onPressed: () {
                          _controller.text = item;
                          _controller.selection = TextSelection.collapsed(
                            offset: item.length,
                          );
                          _onSearch(item);
                        },
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoResultsState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 80,
              color: Colors.white.withValues(alpha: 0.28),
            ),
            const SizedBox(height: 16),
            Text(
              'No matches for "$query"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Try a shorter title, different spelling, or remove filters.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsState(
    String query,
    String? languageFilter,
    String? sortBy,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _getGridColumns(constraints.maxWidth);
        return Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Row(
                children: [
                  Text(
                    '${_allResults.length} results',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Page $_currentPage/$_totalPages',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.72),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (languageFilter != null || sortBy != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (languageFilter != null)
                      _activeFilterPill(
                        'Lang: ${languageFilter.toUpperCase()}',
                      ),
                    if (sortBy != null)
                      _activeFilterPill('Sort: ${sortBy.toUpperCase()}'),
                  ],
                ),
              ),
            Expanded(
              child: GridView.builder(
                key: PageStorageKey<String>('search_grid_$query'),
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 20),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: _getGridAspectRatio(columns),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 14,
                ),
                addAutomaticKeepAlives: true,
                addRepaintBoundaries: true,
                itemCount: _allResults.length + (_isLoadingMore ? columns : 0),
                itemBuilder: (context, index) {
                  if (index >= _allResults.length) {
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: NivioTheme.netflixRed,
                            strokeWidth: 2,
                          ),
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
        );
      },
    );
  }

  Widget _activeFilterPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: NivioTheme.netflixRed.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: NivioTheme.netflixRed.withValues(alpha: 0.55),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  int _getGridColumns(double width) {
    if (width >= 1300) return 6;
    if (width >= 1050) return 5;
    if (width >= 820) return 4;
    if (width >= 560) return 3;
    return 2;
  }

  double _getGridAspectRatio(int columns) {
    if (columns >= 5) return 0.66;
    if (columns == 4) return 0.64;
    if (columns == 3) return 0.62;
    return 0.60;
  }

  List<SearchResult> _mergeUniqueResults(
    List<SearchResult> existing,
    List<SearchResult> incoming,
  ) {
    final merged = List<SearchResult>.from(existing);
    final seen = existing.map((item) => '${item.mediaType}_${item.id}').toSet();

    for (final item in incoming) {
      if (seen.add('${item.mediaType}_${item.id}')) {
        merged.add(item);
      }
    }
    return merged;
  }
}
