import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> defaultSectionOrder = [
  'popular_movies',
  'trending_movies',
  'top_rated_movies',
  'popular_tv',
  'trending_tv',
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
