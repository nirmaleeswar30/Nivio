import 'package:dio/dio.dart';
import 'package:nivio/core/debug_log.dart';
import 'package:nivio/services/skip_times_models.dart';

class AniSkipService {
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.aniskip.com/v2',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  static Future<List<SkipTime>> getSkipTimes(int malId, int episodeNumber) async {
    try {
      final response = await _dio.get(
        '/skip-times/$malId/$episodeNumber',
        queryParameters: {
          'types': ['op', 'ed', 'recap', 'mixed-op', 'mixed-ed'],
          'episodeLength': 0, // 0 tells AniSkip to ignore strict length matching
        },
      );

      if (response.statusCode == 200 && response.data['found'] == true) {
        final List<dynamic> results = response.data['results'];
        final List<SkipTime> skipTimes = [];

        for (final r in results) {
          final interval = r['interval'];
          if (interval != null) {
            final double start = (interval['startTime'] as num).toDouble();
            final double end = (interval['endTime'] as num).toDouble();
            skipTimes.add(
              SkipTime(
                startTime: Duration(milliseconds: (start * 1000).toInt()),
                endTime: Duration(milliseconds: (end * 1000).toInt()),
                type: r['skipType'] ?? 'unknown',
              ),
            );
          }
        }
        
        appDebugLog('✅ AniSkip returned ${skipTimes.length} skip times for MAL $malId Ep $episodeNumber');
        return skipTimes;
      }
    } catch (e) {
      appDebugLog('❌ Error fetching AniSkip for MAL $malId Ep $episodeNumber: $e');
    }
    return [];
  }
}
