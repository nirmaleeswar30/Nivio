import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> defaultSectionOrder = [
  'latest_movies_ott',
  'popular_movies',
  'trending_movies',
  'top_rated_movies',
  'latest_tv_ott',
  'popular_tv',
  'trending_tv',
  'latest_anime',
  'popular_anime',
  'trending_anime',
  'tamil',
  'telugu',
  'hindi',
  'korean',
  'malayalam',
];

class HomeLayoutNotifier extends StateNotifier<List<String>> {
  HomeLayoutNotifier() : super(defaultSectionOrder) {
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList('homeSectionOrder');
    
    if (savedOrder != null && savedOrder.isNotEmpty) {
      // Ensure all default sections are present in the saved order
      // (in case a new section was added in an update)
      final mergedOrder = List<String>.from(savedOrder);
      // Smart insertion to keep latest releases as first shelf of their respective categories
      if (!mergedOrder.contains('latest_movies_ott')) {
        final movieIdx = mergedOrder.indexOf('popular_movies');
        if (movieIdx != -1) {
          mergedOrder.insert(movieIdx, 'latest_movies_ott');
        } else {
          mergedOrder.insert(0, 'latest_movies_ott');
        }
      }
      if (!mergedOrder.contains('latest_tv_ott')) {
        final tvIdx = mergedOrder.indexOf('popular_tv');
        if (tvIdx != -1) {
          mergedOrder.insert(tvIdx, 'latest_tv_ott');
        } else {
          mergedOrder.add('latest_tv_ott');
        }
      }
      if (!mergedOrder.contains('latest_anime')) {
        final animeIdx = mergedOrder.indexOf('popular_anime');
        if (animeIdx != -1) {
          mergedOrder.insert(animeIdx, 'latest_anime');
        } else {
          mergedOrder.add('latest_anime');
        }
      }
      for (final section in defaultSectionOrder) {
        if (!mergedOrder.contains(section)) {
          mergedOrder.add(section);
        }
      }
      state = mergedOrder;
    } else {
      state = defaultSectionOrder;
    }
  }

  Future<void> updateOrder(List<String> newOrder) async {
    state = List.from(newOrder);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('homeSectionOrder', newOrder);
  }
}

final homeLayoutProvider = StateNotifierProvider<HomeLayoutNotifier, List<String>>((ref) {
  return HomeLayoutNotifier();
});
