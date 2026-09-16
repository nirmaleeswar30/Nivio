import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/search_result.dart';
import 'torrent_models.dart';

class AnimeQueryBuilder {
  AnimeQueryBuilder({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  static const _anilistQuery = r'''
query ($id: Int) {
  Media(id: $id, type: ANIME) {
    title { romaji english }
    episodes
  }
}''';

  static String _getShortBaseTitle(String title) {
    var short = title;
    if (short.contains(': ')) short = short.split(': ')[0];
    else if (short.contains(' - ')) short = short.split(' - ')[0];
    
    short = short.replaceAll(RegExp(r'(?:\d+(?:st|nd|rd|th)? Season|Season \d+|Part \d+|Cour \d+)', caseSensitive: false), ' ');
    short = short.replaceAll(RegExp(r'\b(?:VIII|VII|III|IV|VI|IX|II|V|X)\b', caseSensitive: true), ' ');
    short = short.replaceAll(':', ' ').replaceAll('-', ' ');
    return short.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _cleanFullBaseTitle(String title) {
    var clean = title.replaceAll(RegExp(r'(?:\d+(?:st|nd|rd|th)? Season|Season \d+|Part \d+|Cour \d+)', caseSensitive: false), ' ');
    clean = clean.replaceAll(RegExp(r'\b(?:VIII|VII|III|IV|VI|IX|II|V|X)\b', caseSensitive: true), ' ');
    return clean.replaceAll(':', ' ').replaceAll('-', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Future<AnimeQuery> build(
    SearchResult media,
    int episode, {
    required int season,
    String resolution = '1080',
    List<String> exclusions = const [],
    int? absoluteEpisode,
  }) async {
    final anilistId = media.id;
    
    String rawTitle = media.title ?? media.name ?? '';
    String? englishTitle;
    int? episodeCount;

    try {
      final anilistRes = await _http.post(
        Uri.parse('https://graphql.anilist.co'),
        headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
        body: jsonEncode({
          'query': _anilistQuery,
          'variables': {'id': anilistId},
        }),
      ).timeout(const Duration(seconds: 10));
      
      if (anilistRes.statusCode == 200) {
        final mediaNode = jsonDecode(anilistRes.body)['data']['Media'];
        if (mediaNode != null && mediaNode['title'] != null) {
          if (mediaNode['title']['romaji'] != null) rawTitle = mediaNode['title']['romaji'];
          if (mediaNode['title']['english'] != null) englishTitle = mediaNode['title']['english'];
        }
        episodeCount = mediaNode?['episodes'] as int?;
      }
    } catch (_) {}

    int? resolvedAbsoluteEpisode = absoluteEpisode;
    int resolvedSeason = season;
    
    try {
      final anizipRes = await _http.get(
        Uri.parse('https://api.ani.zip/mappings?anilist_id=$anilistId')
      ).timeout(const Duration(seconds: 4));
      
      if (anizipRes.statusCode == 200) {
        final data = jsonDecode(anizipRes.body);
        final episodes = data['episodes'] as Map?;
        if (episodes != null) {
          final epData = episodes[episode.toString()];
          if (epData != null) {
            resolvedAbsoluteEpisode = epData['absoluteEpisodeNumber'] as int?;
            if (epData['seasonNumber'] != null) {
              resolvedSeason = epData['seasonNumber'] as int;
            }
          }
        }
      }
    } catch (_) {}

    final shortBase = _getShortBaseTitle(rawTitle);
    final fullBase = _cleanFullBaseTitle(rawTitle);
    
    final epStr = episode.toString().padLeft(2, '0');
    final sStr = resolvedSeason.toString().padLeft(2, '0');
    final absStr = resolvedAbsoluteEpisode?.toString().padLeft(2, '0');
    
    final queries = <String>[];

    if (resolvedSeason > 1) {
      queries.add('$shortBase S$resolvedSeason - $epStr');
      queries.add('$shortBase S${sStr}E$epStr');
      if (shortBase != fullBase) queries.add('$fullBase S$resolvedSeason - $epStr');
    } else {
      queries.add('$shortBase - $epStr');
      queries.add('$shortBase E$epStr');
    }

    if (resolvedAbsoluteEpisode != null && resolvedAbsoluteEpisode != episode) {
      queries.add('$shortBase - $absStr');
      if (shortBase != fullBase) queries.add('$fullBase - $absStr');
    }

    final literalNoColon = rawTitle.replaceAll(':', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    queries.add('$literalNoColon - $epStr');

    if (englishTitle != null) {
      final engBase = _getShortBaseTitle(englishTitle);
      queries.add('$engBase S${sStr}E$epStr');
    }

    return AnimeQuery(
      titles: queries.toSet().toList(),
      episode: episode,
      season: resolvedSeason,
      anilistId: anilistId,
      episodeCount: episodeCount,
      absoluteEpisode: resolvedAbsoluteEpisode,
      resolution: resolution,
      exclusions: exclusions,
    );
  }
}
