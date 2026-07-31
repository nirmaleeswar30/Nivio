// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/search_media_item.dart';
import '../../../core/interfaces/search_repository.dart';

class SearchController extends ChangeNotifier {
  SearchController({required SearchRepository repository})
    : _repository = repository;

  final SearchRepository _repository;
  Timer? _debounceTimer;

  String _query = '';
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  List<SearchMediaItem> _results = const [];
  int _page = 1;
  bool _hasMore = true;
  final List<String> _recentSearches = <String>[];
  SearchLanguageFilter _language = SearchLanguageFilter.all;
  SearchSortOption _sort = SearchSortOption.defaultOrder;
  SearchViewMode _viewMode = SearchViewMode.grid;
  bool _initialized = false;
  int _requestId = 0;
  static const String _recentSearchesKey = 'recent_searches';
  static const String _legacySearchHistoryKey = 'search_history';

  String get query => _query;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get errorMessage => _errorMessage;
  List<SearchMediaItem> get results => List.unmodifiable(_results);
  List<String> get recentSearches => List.unmodifiable(_recentSearches);
  SearchLanguageFilter get language => _language;
  SearchSortOption get sort => _sort;
  SearchViewMode get viewMode => _viewMode;
  bool get hasError => _errorMessage != null;
  bool get hasResults => _results.isNotEmpty;
  bool get hasActiveFilters =>
      _language != SearchLanguageFilter.all ||
      _sort != SearchSortOption.defaultOrder;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    await _loadRecentSearches();
    await _runSearch();
  }

  void setQuery(String value) {
    if (_query == value) {
      return;
    }

    _query = value;
    _requestId++;
    _errorMessage = null;
    _page = 1;
    _hasMore = true;
    _results = const [];
    _isLoading = value.trim().isNotEmpty;
    _isLoadingMore = false;
    _scheduleSearch();
    notifyListeners();
  }

  Future<void> submitQuery() async {
    _debounceTimer?.cancel();
    await _runSearch();
  }

  Future<void> retry() async {
    _debounceTimer?.cancel();
    await _runSearch();
  }

  void setLanguage(SearchLanguageFilter value) {
    if (_language == value) {
      return;
    }
    _language = value;
    unawaited(_runSearch());
    notifyListeners();
  }

  void setSort(SearchSortOption value) {
    if (_sort == value) {
      return;
    }
    _sort = value;
    unawaited(_runSearch());
    notifyListeners();
  }

  void setViewMode(SearchViewMode value) {
    if (_viewMode == value) {
      return;
    }
    _viewMode = value;
    notifyListeners();
  }

  void clearFilters() {
    _language = SearchLanguageFilter.all;
    _sort = SearchSortOption.defaultOrder;
    unawaited(_runSearch());
    notifyListeners();
  }

  void clearRecentSearches() {
    _recentSearches.clear();
    unawaited(_saveRecentSearches());
    notifyListeners();
  }

  void removeRecentSearch(String query) {
    if (_recentSearches.remove(query)) {
      unawaited(_saveRecentSearches());
      notifyListeners();
    }
  }

  void _scheduleSearch() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_runSearch());
    });
  }

  bool _isDisposed = false;

  Future<void> _runSearch() async {
    if (_isDisposed) return;
    final normalizedQuery = _query.trim();
    final requestId = ++_requestId;
    _errorMessage = null;
    _page = 1;
    _hasMore = true;
    _results = [];
    if (normalizedQuery.isEmpty) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();

    try {
      final results = await _repository.search(
        query: normalizedQuery,
        language: _language,
        mediaType: SearchMediaTypeFilter.all,
        sort: _sort,
        page: _page,
      );
      if (_isDisposed || requestId != _requestId) return;
      _results = results;
      _hasMore = results
          .isNotEmpty; // TMDB typically returns empty list when out of bounds
      if (results.isNotEmpty) {
        _pushRecentSearch(normalizedQuery);
      }
    } catch (_) {
      if (_isDisposed || requestId != _requestId) return;
      _results = const [];
      _errorMessage = 'We could not load search results right now.';
      _hasMore = false;
    } finally {
      if (!_isDisposed && requestId == _requestId) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMore() async {
    if (_isDisposed ||
        _isLoading ||
        _isLoadingMore ||
        !_hasMore ||
        _query.trim().isEmpty) {
      return;
    }

    _isLoadingMore = true;
    final requestId = _requestId;
    final query = _query.trim();
    notifyListeners();

    try {
      final nextPage = _page + 1;
      final newResults = await _repository.search(
        query: query,
        language: _language,
        mediaType: SearchMediaTypeFilter.all,
        sort: _sort,
        page: nextPage,
      );

      if (_isDisposed || requestId != _requestId) return;

      if (newResults.isEmpty) {
        _hasMore = false;
      } else {
        _page = nextPage;
        _results = [..._results, ...newResults];
      }
    } catch (_) {
      if (_isDisposed || requestId != _requestId) return;
      _hasMore = false;
    } finally {
      if (!_isDisposed && requestId == _requestId) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  void _pushRecentSearch(String query) {
    _recentSearches.remove(query);
    _recentSearches.insert(0, query);
    if (_recentSearches.length > 5) {
      _recentSearches.removeRange(5, _recentSearches.length);
    }
    unawaited(_saveRecentSearches());
  }

  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final stored =
        prefs.getStringList(_recentSearchesKey) ??
        prefs.getStringList(_legacySearchHistoryKey) ??
        const <String>[];
    _recentSearches
      ..clear()
      ..addAll(
        stored
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .take(5),
      );
    notifyListeners();
  }

  Future<void> _saveRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    await prefs.remove(_legacySearchHistoryKey);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    super.dispose();
  }
}
