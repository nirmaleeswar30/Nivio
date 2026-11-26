import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class ParentalWarning {
  const ParentalWarning(this.label, this.severity);

  final String label;
  final String severity;
}

// Adapted for Nivio from NuvioMobile's GPL-3.0 parental guide repository.
// https://github.com/NuvioMedia/NuvioMobile/blob/0d20af832d381e5ab3a385deccfbc47c12b93bf1/composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/ParentalGuideRepository.kt
class ParentalGuideService {
  ParentalGuideService(this._client);

  static final _imdbId = RegExp(r'^tt\d+$');
  static const _categories = {
    'SEXUAL_CONTENT': 'Nudity',
    'VIOLENCE': 'Violence',
    'PROFANITY': 'Profanity',
    'ALCOHOL_DRUGS': 'Alcohol/Drugs',
    'FRIGHTENING_INTENSE_SCENES': 'Frightening',
  };
  static const _severities = {
    'severe': 'Severe',
    'moderate': 'Moderate',
    'mild': 'Mild',
  };

  final http.Client _client;
  final _cache = <String, List<ParentalWarning>>{};

  Future<List<ParentalWarning>> fetch(String imdbId) async {
    if (!_imdbId.hasMatch(imdbId)) return const [];
    final cached = _cache[imdbId];
    if (cached != null) return cached;
    try {
      final response = await _client
          .get(
            Uri.https('api.tiffara.com', '/titles/$imdbId/parentsGuide'),
            headers: const {'Accept': 'application/json'},
          )
          .timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return const [];
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map<String, dynamic> ||
          payload['parentsGuide'] is! List) {
        return const [];
      }
      final warnings = _parse(payload['parentsGuide'] as List);
      if (_cache.length >= 128) _cache.remove(_cache.keys.first);
      return _cache[imdbId] = List.unmodifiable(warnings);
    } on Exception {
      // Missing or unavailable ratings must never affect playback.
      return const [];
    }
  }

  static List<ParentalWarning> _parse(List<dynamic> categories) {
    final levels = <String, String>{};
    for (final category in categories.whereType<Map<String, dynamic>>()) {
      final name = category['category']?.toString().toUpperCase();
      final breakdown = category['severityBreakdowns'];
      if (!_categories.containsKey(name) || breakdown is! List) continue;
      var none = 0;
      var highest = 0;
      String? severity;
      for (final item in breakdown.whereType<Map<String, dynamic>>()) {
        final level = item['severityLevel']?.toString().toLowerCase();
        final votes = item['voteCount'];
        if (votes is! int || votes <= 0) continue;
        if (level == 'none') {
          none = votes;
        } else if (_severities.containsKey(level) && votes > highest) {
          highest = votes;
          severity = level;
        }
      }
      if (severity != null && highest > none) levels[name!] = severity;
    }
    return [
      for (final severity in _severities.entries)
        for (final category in _categories.entries)
          if (levels[category.key] == severity.key)
            ParentalWarning(category.value, severity.value),
    ];
  }
}
