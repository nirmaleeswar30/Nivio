import 'package:dio/dio.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/skip_times_models.dart';

class TheIntroDBService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.theintrodb.org/v3',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static Future<List<SkipTime>> getSkipTimes(int tmdbId, int season, int episode) async {
    try {
      final response = await _dio.get(
        '/media',
        queryParameters: {
          'tmdb_id': tmdbId,
          'season': season,
          'episode': episode,
        },
        options: Options(
          headers: {
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final List<SkipTime> skipTimes = [];

        void addSkipTimes(String typeKey, String mappedType) {
          if (data[typeKey] is List) {
            for (final r in data[typeKey]) {
              final startMs = (r['start_ms'] as num?)?.toInt() ?? 0;
              final endMs = (r['end_ms'] as num?)?.toInt() ?? 0;
              
              skipTimes.add(
                SkipTime(
                  startTime: Duration(milliseconds: startMs),
                  endTime: endMs > 0 ? Duration(milliseconds: endMs) : const Duration(hours: 99), // If null/0, it's until the end
                  type: mappedType,
                ),
              );
            }
          }
        }

        addSkipTimes('intro', 'op');
        addSkipTimes('credits', 'ed');
        addSkipTimes('recap', 'recap');
        addSkipTimes('preview', 'preview');
        
        appDebugLog('✅ TheIntroDB returned ${skipTimes.length} skip times for TMDB $tmdbId S${season}E$episode');
        return skipTimes;
      }
    } catch (e) {
      if (e is DioException && (e.response?.statusCode == 404 || e.response?.statusCode == 400)) {
         appDebugLog('ℹ️ TheIntroDB: No skip times found for TMDB $tmdbId S${season}E$episode');
      } else {
         appDebugLog('❌ Error fetching TheIntroDB for TMDB $tmdbId S${season}E$episode: $e');
      }
    }
    return [];
  }
}
