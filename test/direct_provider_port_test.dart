import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/services/playback/built_in_direct_sources.dart';
import 'package:nivio/services/scrapers/castle_tv_source.dart';
import 'package:nivio/services/scrapers/movie_box_source.dart';
import 'package:nivio/services/scrapers/net_mirror_source.dart';

const _movie = SearchResult(
  id: 27205,
  title: 'Inception',
  releaseDate: '2010-07-15',
  mediaType: 'movie',
);

void main() {
  test(
    'MovieBox resolves separate catalog entries for the same release',
    () async {
      final played = <Object?>[];
      final client = _client((request) {
        switch (request.uri.path.split('/').last) {
          case 'home':
            return _response(
              request,
              {},
              headers: {
                'x-user': ['{"token":"guest"}'],
              },
            );
          case 'search':
            return _response(request, {
              'items': [
                _movieBoxTitle('hi', 'Inception [Hindi]', '2010-09-01'),
                _movieBoxTitle('en', 'Inception', '2010-07-16'),
                _movieBoxTitle('remake', 'Inception', '2024-07-16'),
                _movieBoxTitle('extra', 'Behind the Scenes', '2010-07-16')
                  ..['postTitle'] = 'Inception',
              ],
            });
          case 'play':
            final id = request.queryParameters['subjectId'];
            played.add(id);
            return _response(request, {
              'streams': [
                {
                  'id': '$id',
                  'url': 'https://cdn.example.com/$id.mp4',
                  'resolutions': id == 'en' ? '1080' : '480',
                },
              ],
            });
          case 'caption':
            return _response(request, {
              'captions': [
                {'url': 'https://cdn.example.com/en.vtt', 'lanName': 'English'},
              ],
            });
          default:
            throw StateError('Unexpected request ${request.uri.path}');
        }
      });
      addTearDown(() => client.close(force: true));
      final result = await MovieBoxSource(
        client: client,
      ).resolve(_movie, season: 1, episode: 1);
      expect(played, unorderedEquals(['en', 'hi']));
      expect(
        result.map((item) => item['quality']),
        unorderedEquals(['480p', '1080p']),
      );
      expect(result.first['language'], 'Hindi');
      expect(result.last['subtitles'], hasLength(1));
    },
  );

  test(
    'CastleTV promotes the unsigned mirror renditions including 1080p',
    () async {
      final requests = <(String, String)>[];
      final client = _client((request) {
        final segments = request.uri.pathSegments;
        if (segments.last == 'index.m3u8') {
          // Probe for an unsigned sibling rendition on the "img" host.
          expect(request.uri.host, 'img.cdn.example.com');
          final language = segments[segments.length - 3];
          final height = segments[segments.length - 2];
          final available =
              height == '720' || (height == '1080' && language == '1');
          return _raw(request, available ? '#EXTM3U\n#EXT-X-VERSION:3' : '');
        }
        final Object data = switch (segments.last) {
          '1' => base64Encode(utf8.encode('abcdefghij')),
          'searchByKeyword' => {
            'rows': [
              {
                'id': 1,
                'title': 'Inception',
                'movieType': 2,
                'publishTime': DateTime.utc(2010, 7, 16).millisecondsSinceEpoch,
              },
            ],
          },
          'movie' => {
            'episodes': [
              {
                'id': 2,
                'videos': [
                  {'resolution': 2, 'resolutionDescription': '720p'},
                  {'resolution': 3, 'resolutionDescription': '1080p'},
                  {
                    'resolution': 4,
                    'resolutionDescription': '2160p',
                    'premiumProPermission': true,
                  },
                ],
                'tracks': [
                  {
                    'languageId': 1,
                    'languageName': 'English',
                    'isDefault': true,
                  },
                  {
                    'languageId': 2,
                    'languageName': 'Tamil',
                    'existIndividualVideo': true,
                  },
                ],
              },
            ],
          },
          'getVideo2' => _castlePlay(request, requests),
          _ => throw StateError('Unexpected request ${request.uri.path}'),
        };
        return _response(
          request,
          data,
          plain: request.responseType == ResponseType.plain,
        );
      });
      addTearDown(() => client.close(force: true));
      final result = await CastleTvSource(
        client: client,
      ).resolve(_movie, season: 1, episode: 1);
      // Each audio track is fetched once at the signed 720p resolution.
      expect(requests, unorderedEquals([('1', '2'), ('2', '2')]));
      // 1080p surfaces for English; Tamil keeps 720p; the CDN does not serve
      // 480p so it is dropped. Every link is on the unsigned mirror host.
      expect(
        result.map((item) => (item['language'], item['quality'])),
        unorderedEquals([
          ('English', '720p'),
          ('English', '1080p'),
          ('Tamil', '720p'),
        ]),
      );
      expect(
        result.every(
          (item) =>
              (item['url'] as String).startsWith('https://img.cdn.example.com/'),
        ),
        isTrue,
      );
    },
  );

  test(
    'MovieBox IN uses its regional catalog and resolves the web playback path',
    () async {
      final client = _client((request) {
        switch (request.uri.path.split('/').last) {
          case 'ranking-list':
            expect(request.uri.host, 'apig.inmoviebox.com');
            expect(request.headers['X-Tr-Signature'], isNotEmpty);
            return _response(
              request,
              {},
              headers: {
                'x-user': ['{"token":"india-guest"}'],
              },
            );
          case 'v2':
            expect(request.headers['Authorization'], 'Bearer india-guest');
            return _response(request, {
              'results': [
                {
                  'subjects': [
                    _movieBoxTitle('hi', 'Inception [Hindi]', '2010-09-01')
                      ..remove('detailPath'),
                  ],
                },
              ],
            });
          case 'home':
            return _response(
              request,
              {},
              headers: {
                'x-user': ['{"token":"web-guest"}'],
              },
            );
          case 'get':
            expect(request.headers['Authorization'], 'Bearer india-guest');
            return _response(request, {
              'detailUrl': 'https://movie-box.co/movies/inception-hi',
            });
          case 'play':
            expect(request.headers['Authorization'], 'Bearer web-guest');
            expect(request.queryParameters['detailPath'], 'inception-hi');
            expect(request.queryParameters['streamSignType'], 1);
            return _response(request, {
              'streams': [
                {'url': 'https://cdn.example.com/hi.mp4', 'resolutions': '720'},
              ],
            });
          default:
            throw StateError('Unexpected request ${request.uri.path}');
        }
      });
      addTearDown(() => client.close(force: true));
      final result = await MovieBoxSource(
        client: client,
        india: true,
      ).resolve(_movie, season: 1, episode: 1);
      expect(result.single['quality'], '720p');
      expect(result.single['language'], 'Hindi');
    },
  );

  test('PrimeVideoM resolves the requested season and episode', () async {
    final client = _client((request) {
      switch (request.uri.path) {
        case '/mobile/pv/search.php':
          expect(request.uri.queryParameters['s'], 'Example Show');
          return _raw(request, {
            'searchResult': [
              {'id': 'series', 't': 'Example Show', 'y': '2021'},
            ],
          });
        case '/mobile/pv/post.php':
          return _raw(request, {
            'season': [
              {'id': 'season2', 's': 'S2'},
            ],
          });
        case '/mobile/pv/episodes.php':
          expect(request.uri.queryParameters['s'], 'season2');
          expect(request.uri.queryParameters['series'], 'series');
          return _raw(request, {
            'episodes': [
              {'id': 'premiere', 's': '2', 'ep': '1'},
              {'id': 'requested', 's': '2', 'ep': '2'},
            ],
          });
        case '/mobile/pv/playlist.php':
          expect(request.uri.queryParameters['id'], 'requested');
          return _raw(request, [
            {
              'sources': [
                {'file': '/mobile/pv/hls/requested.m3u8', 'label': 'Auto'},
              ],
              'tracks': [
                {'file': '/en.vtt', 'kind': 'captions', 'label': 'English'},
              ],
            },
          ]);
        case '/mobile/pv/hls/requested.m3u8':
          return _raw(request, ResponseBody.fromString('#EXTM3U\n', 200));
        default:
          throw StateError('Unexpected request ${request.uri.path}');
      }
    });
    addTearDown(() => client.close(force: true));
    final result = await NetMirrorSource(client: client).resolve(
      'PrimeVideoM',
      const SearchResult(
        id: 123,
        name: 'Example Show',
        firstAirDate: '2021-11-01',
        mediaType: 'tv',
      ),
      season: 2,
      episode: 2,
    );
    expect(
      result.single['url'],
      'https://net52.cc/mobile/pv/hls/requested.m3u8',
    );
    expect(result.single['subtitles'], hasLength(1));
  });

  test('the direct movie and series registry includes the ported names', () {
    expect(
      BuiltInDirectSources.names,
      containsAll([
        'MovieBox IN',
        'CineTv',
        'Netflix',
        'NetflixM',
        'Prime Video',
        'PrimeVideoM',
        'Hotstar',
        'HotstarM',
        'Disney',
        'DisneyM',
        'Marvel',
        'MarvelM',
        'Star Wars',
        'Star WarsM',
        'Pixar',
        'PixarM',
      ]),
    );
  });
}

Dio _client(Response<Object?> Function(RequestOptions request) response) =>
    Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (request, handler) => handler.resolve(response(request)),
        ),
      );

Response<Object?> _response(
  RequestOptions request,
  Object? data, {
  bool plain = false,
  Map<String, List<String>> headers = const {},
}) {
  final envelope = {'data': data};
  return _raw(
    request,
    plain ? jsonEncode(envelope) : envelope,
    headers: headers,
  );
}

Response<Object?> _raw(
  RequestOptions request,
  Object? data, {
  Map<String, List<String>> headers = const {},
}) => Response<Object?>(
  requestOptions: request,
  data: data,
  statusCode: 200,
  headers: Headers.fromMap(headers),
);

Map<String, Object> _movieBoxTitle(String id, String title, String date) => {
  'subjectId': id,
  'subjectType': 1,
  'title': title,
  'releaseDate': date,
  'detailPath': 'inception-$id',
};

Map<String, Object> _castlePlay(
  RequestOptions options,
  List<(String, String)> requests,
) {
  final data = options.data as Map;
  final language = data['languageId'] as String;
  final resolution = data['resolution'] as String;
  requests.add((language, resolution));
  return {
    'videoUrl': 'https://img1.cdn.example.com/hls_mps/$language/720/index.m3u8',
  };
}
