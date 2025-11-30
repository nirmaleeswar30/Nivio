import 'package:dio/dio.dart';

/// Service for interacting with AniList API
/// Converts TMDB IDs to AniList IDs for anime content
class AniListService {
  final Dio _dio;
  static const String _baseUrl = 'https://graphql.anilist.co';

  AniListService() : _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));

  /// Search for anime by title and year to find AniList ID
  /// Returns null if no match found
  Future<int?> getAniListIdFromTMDB({
    required String title,
    String? year,
    int? tmdbId,
  }) async {
    try {
      // GraphQL query to search for anime
      const query = '''
        query (\$search: String, \$season: MediaSeason, \$seasonYear: Int) {
          Media(search: \$search, type: ANIME, season: \$season, seasonYear: \$seasonYear, sort: POPULARITY_DESC) {
            id
            idMal
            title {
              romaji
              english
              native
            }
            startDate {
              year
            }
            season
            seasonYear
          }
        }
      ''';

      final variables = {
        'search': title,
        if (year != null) 'seasonYear': int.tryParse(year),
      };

      print('🔍 Searching AniList for: $title ${year ?? ''}');

      final response = await _dio.post(
        '',
        data: {
          'query': query,
          'variables': variables,
        },
      );

      if (response.statusCode == 200 && response.data['data']['Media'] != null) {
        final anilistId = response.data['data']['Media']['id'] as int;
        print('✅ Found AniList ID: $anilistId for $title');
        return anilistId;
      }

      print('❌ No AniList match found for: $title');
      return null;
    } on DioException catch (e) {
      print('❌ DioException fetching AniList ID: ${e.message}');
      return null;
    } catch (e) {
      print('❌ Error fetching AniList ID: $e');
      return null;
    }
  }

  /// Check if a title is likely anime by searching AniList
  Future<bool> isAnime(String title, String? year) async {
    final id = await getAniListIdFromTMDB(title: title, year: year);
    return id != null;
  }
}
