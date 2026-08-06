import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivio_desktop/features/player/models/playback_request.dart';
import 'package:nivio_desktop/features/player/services/anime_stream_providers.dart';
import 'package:nivio_desktop/features/player/services/castle_tv_stream_provider.dart';
import 'package:nivio_desktop/features/player/services/moviebox_stream_provider.dart';
import 'package:nivio_desktop/features/player/services/netmirror_stream_provider.dart';
import 'package:nivio_desktop/features/player/services/provider_registry.dart';
import 'package:nivio_desktop/features/player/services/streamflix_stream_provider.dart';
import 'package:pointycastle/export.dart';

void main() {
  group('NetMirror desktop parity', () {
    test('resolves NetMirror Android API proxy stream for movies', () async {
      final requestedUrls = <Uri>[];
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          requestedUrls.add(options.uri);
          if (options.uri.path == '/api/variants-tmdb/movie/1367220') {
            return {
              'ok': true,
              'defaultSubjectId': 'default-subject',
              'defaultDetailPath': 'karuppu-default',
              'variants': [
                {
                  'dubSubjectId': 'default-subject',
                  'language': 'Default',
                  'detailPath': 'karuppu-default',
                },
              ],
            };
          }
          if (options.uri.path == '/api/embed-tmdb/1367220') {
            return {
              'ok': true,
              'tmdbId': 1367220,
              'title': 'Karuppu',
              'mode': 'proxy',
              'mp4': 'https://bcdnw.hakunaymatata.com/karuppu-1080.mp4',
              'resolution': 1080,
              'direct': false,
              'exp': 1785675681,
              'sig': 'signed',
              'streams': [
                {
                  'url': 'https://bcdnw.hakunaymatata.com/karuppu-1080.mp4',
                  'resolution': 1080,
                },
              ],
              'captions': [
                {'url': 'https://subs.example/karuppu.vtt', 'name': 'English'},
              ],
            };
          }
          fail('Unexpected NetMirror request: ${options.uri}');
        });

      final result = await NetMirrorStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'movie:1367220',
          title: 'Karuppu',
          mediaType: PlaybackMediaType.movie,
        ),
      );

      expect(result, isNotNull);
      expect(result!.url, 'https://bcdnw.hakunaymatata.com/karuppu-1080.mp4');
      expect(result.isM3U8, isFalse);
      expect(result.headers['Referer'], 'https://net27.cc/');
      expect(result.headers['Origin'], 'https://net27.cc');
      expect(result.headers['User-Agent'], contains('Android 13'));
      expect(result.sources.single.url, result.url);
      expect(result.subtitles.single.url, 'https://subs.example/karuppu.vtt');
      expect(
        requestedUrls.map((uri) => uri.path),
        contains('/api/embed-tmdb/1367220'),
      );
      final embed = requestedUrls.singleWhere(
        (uri) => uri.path == '/api/embed-tmdb/1367220',
      );
      expect(embed.queryParameters['type'], 'movie');
      expect(embed.queryParameters['se'], '0');
      expect(embed.queryParameters['ep'], '0');
      expect(embed.queryParameters['sid'], 'default-subject');
      expect(embed.queryParameters['dp'], 'karuppu-default');
    });

    test('returns null when NetMirror Android API reports no source', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/api/variants-tmdb/movie/1367220') {
            return {
              'ok': true,
              'defaultSubjectId': 'default-subject',
              'defaultDetailPath': 'karuppu-default',
              'variants': [
                {
                  'dubSubjectId': 'default-subject',
                  'language': 'Default',
                  'detailPath': 'karuppu-default',
                },
              ],
            };
          }
          if (options.uri.path == '/api/embed-tmdb/1367220') {
            return {
              'ok': true,
              'tmdbId': 1367220,
              'mode': 'none',
              'noSource': true,
              'error': 'This title is still being added to NetMirror.',
            };
          }
          fail('Unexpected NetMirror request: ${options.uri}');
        });

      final result = await NetMirrorStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'movie:1367220',
          title: 'Karuppu',
          mediaType: PlaybackMediaType.movie,
        ),
      );

      expect(result, isNull);
    });

    test('passes browser headers for direct NetMirror media', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/api/variants-tmdb/movie/1367220') {
            return {
              'ok': true,
              'defaultSubjectId': 'default-subject',
              'defaultDetailPath': 'karuppu-default',
              'variants': [
                {
                  'dubSubjectId': 'default-subject',
                  'language': 'Default',
                  'detailPath': 'karuppu-default',
                },
              ],
            };
          }
          if (options.uri.path == '/api/embed-tmdb/1367220') {
            return {
              'ok': true,
              'mode': 'proxy',
              'mp4': 'https://net27-r2-cache.example/v1/movie/480.mp4',
              'resolution': 480,
              'direct': true,
              'streams': [
                {
                  'url': 'https://watch21.com/karuppu-480.mp4',
                  'resolution': 480,
                },
              ],
            };
          }
          fail('Unexpected NetMirror request: ${options.uri}');
        });

      final result = await NetMirrorStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'movie:1367220',
          title: 'Karuppu',
          mediaType: PlaybackMediaType.movie,
        ),
      );

      expect(result, isNotNull);
      expect(result!.url, 'https://net27-r2-cache.example/v1/movie/480.mp4');
      expect(result.headers['Referer'], 'https://net27.cc');
      expect(result.headers['User-Agent'], contains('Mozilla/5.0'));
      expect(result.sources.single.url, result.url);
    });

    test('passes Android headers for raw CDN URLs marked direct', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/api/variants-tmdb/movie/1367220') {
            return {
              'ok': true,
              'defaultSubjectId': 'default-subject',
              'defaultDetailPath': 'karuppu-default',
              'variants': [
                {
                  'dubSubjectId': 'default-subject',
                  'language': 'Default',
                  'detailPath': 'karuppu-default',
                },
              ],
            };
          }
          if (options.uri.path == '/api/embed-tmdb/1367220') {
            return {
              'ok': true,
              'mode': 'proxy',
              'mp4': 'https://bcdnw.hakunaymatata.com/bt/blast.mp4',
              'resolution': 480,
              'direct': true,
              'exp': 1785675681,
              'sig': 'signed',
              'streams': [
                {
                  'url': 'https://bcdnw.hakunaymatata.com/bt/blast.mp4',
                  'resolution': 480,
                },
              ],
            };
          }
          fail('Unexpected NetMirror request: ${options.uri}');
        });

      final result = await NetMirrorStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'movie:1367220',
          title: 'Blast',
          mediaType: PlaybackMediaType.movie,
        ),
      );

      expect(result, isNotNull);
      expect(result!.url, 'https://bcdnw.hakunaymatata.com/bt/blast.mp4');
      expect(result.headers['Referer'], 'https://net27.cc/');
      expect(result.headers['Origin'], 'https://net27.cc');
      expect(result.headers['User-Agent'], contains('Android 13'));
      expect(result.sources.single.url, result.url);
    });
  });

  group('CastleTV desktop parity', () {
    test(
      'resolves current rows search response with audio and subtitles',
      () async {
        final requestedUrls = <Uri>[];
        final dio = Dio()
          ..httpClientAdapter = _CastleAdapter((options) {
            requestedUrls.add(options.uri);
            if (options.uri.path == '/v0.1/system/getSecurityKey/1') {
              return {'code': 200, 'msg': 'OK', 'data': 'ZkpBVG0qa2dmSg=='};
            }
            if (options.uri.path == '/film-api/v1.1.0/movie/searchByKeyword') {
              return _castleEncrypt({
                'code': 200,
                'msg': 'OK',
                'data': {
                  'rows': [
                    {'id': 7139045478244352, 'title': 'Animal', 'movieType': 2},
                  ],
                },
              });
            }
            if (options.uri.path == '/film-api/v1.9.9/movie') {
              return _castleEncrypt({
                'code': 200,
                'msg': 'OK',
                'data': {
                  'id': 7139045478244352,
                  'title': 'Animal',
                  'movieType': 2,
                  'episodes': [
                    {
                      'id': 7250599824559104,
                      'title': '1',
                      'number': 1,
                      'playResolution': 2,
                      'tracks': [
                        {
                          'languageId': 1018,
                          'languageName': 'Hindi',
                          'isDefault': true,
                          'order': 2,
                        },
                        {
                          'languageId': 1033,
                          'languageName': 'Tamil',
                          'isDefault': false,
                          'order': 3,
                        },
                      ],
                      'subtitles': [
                        {
                          'title': 'English',
                          'url': 'https://cdn.example/animal-en.vtt',
                        },
                      ],
                      'videos': [
                        {
                          'resolution': 1,
                          'resolutionDescription': 'SD 480P',
                          'premiumProPermission': false,
                        },
                        {
                          'resolution': 2,
                          'resolutionDescription': 'HD 720P',
                          'premiumProPermission': false,
                        },
                        {
                          'resolution': 3,
                          'resolutionDescription': 'FHD 1080P',
                          'premiumProPermission': true,
                        },
                      ],
                    },
                  ],
                },
              });
            }
            if (options.uri.path == '/film-api/v2.0.1/movie/getVideo2') {
              expect(options.data['movieId'], '7139045478244352');
              expect(options.data['episodeId'], '7250599824559104');
              expect(options.data['languageId'], '1033');
              expect(options.data['resolution'], '2');
              return _castleEncrypt({
                'code': 200,
                'msg': 'OK',
                'data': {
                  'videoUrl': 'https://cdn.example/animal-tamil.m3u8',
                  'videos': [
                    {
                      'resolution': 2,
                      'resolutionDescription': 'HD 720P',
                      'premiumProPermission': false,
                    },
                  ],
                  'subtitles': [
                    {
                      'title': 'English',
                      'url': 'https://cdn.example/animal-en.vtt',
                    },
                  ],
                },
              });
            }
            fail('Unexpected CastleTV request: ${options.uri}');
          });

        final result = await CastleTvStreamProvider(dio: dio).resolve(
          const PlaybackRequest(
            mediaId: 'movie:781732',
            title: 'Animal',
            mediaType: PlaybackMediaType.movie,
            preferredAudioTrack: 'Tamil',
            preferredQuality: '1080p',
          ),
        );

        expect(result, isNotNull);
        expect(result!.provider, 'CastleTV');
        expect(result.url, 'https://cdn.example/animal-tamil.m3u8');
        expect(result.selectedAudio, 'Tamil');
        expect(result.availableAudios, ['Hindi', 'Tamil']);
        expect(result.availableQualities, ['HD 720P']);
        expect(
          result.subtitles.single.url,
          'https://cdn.example/animal-en.vtt',
        );
        expect(
          requestedUrls.map((uri) => uri.path),
          contains('/film-api/v2.0.1/movie/getVideo2'),
        );
      },
    );
  });

  group('MovieBox desktop parity', () {
    test(
      'selects matching language subject and direct detector resources',
      () async {
        final requestedUrls = <Uri>[];
        final dio = Dio()
          ..httpClientAdapter = _MovieBoxAdapter((options) {
            requestedUrls.add(options.uri);
            if (options.uri.path == '/wefeed-mobile-bff/tab/ranking-list') {
              return _MovieBoxResponse(
                body: {'code': 200, 'data': {}},
                headers: {
                  'x-user': ['{"token":"moviebox-token"}'],
                },
              );
            }
            if (options.uri.path ==
                '/wefeed-mobile-bff/subject-api/search/v2') {
              expect(options.headers['authorization'], 'Bearer moviebox-token');
              expect(options.data.toString(), contains('"keyword":"Animal"'));
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'subjects': [
                      {
                        'subjectId': 'animal-hindi',
                        'title': 'Animal [Hindi]',
                        'language': 'Hindi',
                        'releaseDate': '2023-12-01',
                        'subjectType': 1,
                      },
                      {
                        'subjectId': 'animal-tamil',
                        'title': 'Animal [Tamil]',
                        'language': 'Tamil',
                        'releaseDate': '2023-12-01',
                        'subjectType': 1,
                      },
                    ],
                  },
                },
              );
            }
            if (options.uri.path == '/wefeed-mobile-bff/subject-api/get') {
              expect(options.uri.queryParameters['subjectId'], 'animal-tamil');
              expect(options.headers['authorization'], 'Bearer moviebox-token');
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'title': 'Animal [Tamil]',
                    'language': 'Tamil',
                    'resourceDetectors': [
                      {
                        'resolutionList': [
                          {
                            'resolution': '480p',
                            'resourceLink':
                                'https://cdn.example/animal-480.mp4',
                          },
                          {
                            'resolution': '1080p',
                            'resourceLink':
                                'https://cdn.example/animal-1080.mp4',
                          },
                        ],
                      },
                    ],
                    'extCaptions': [
                      {
                        'lang': 'English',
                        'url': 'https://cdn.example/animal-en.vtt',
                      },
                    ],
                  },
                },
              );
            }
            fail('Unexpected MovieBox request: ${options.uri}');
          });

        final result =
            await MovieBoxStreamProvider(
              dio: dio,
              deviceId: '00112233445566778899aabbccddeeff',
            ).resolve(
              const PlaybackRequest(
                mediaId: 'movie:781732',
                title: 'Animal',
                mediaType: PlaybackMediaType.movie,
                preferredAudioTrack: 'Tamil',
                preferredQuality: '1080p',
              ),
            );

        expect(result, isNotNull);
        expect(result!.provider, 'MovieBox');
        expect(result.url, 'https://cdn.example/animal-1080.mp4');
        expect(result.quality, '1080p');
        expect(result.headers['Referer'], 'https://api3.aoneroom.com');
        expect(result.headers['User-Agent'], contains('com.community.oneroom'));
        expect(result.selectedAudio, 'Tamil');
        expect(result.availableAudios, ['Hindi', 'Tamil']);
        expect(result.availableQualities, ['1080p', '480p']);
        expect(result.subtitles.single.lang, 'English');
        expect(
          requestedUrls.map((uri) => uri.path),
          contains('/wefeed-mobile-bff/subject-api/get'),
        );
      },
    );

    test(
      'does not expose broad metadata languages as switchable audio',
      () async {
        final dio = Dio()
          ..httpClientAdapter = _MovieBoxAdapter((options) {
            if (options.uri.path == '/wefeed-mobile-bff/tab/ranking-list') {
              return _MovieBoxResponse(
                body: {'code': 200, 'data': {}},
                headers: {
                  'x-user': ['{"token":"moviebox-token"}'],
                },
              );
            }
            if (options.uri.path ==
                '/wefeed-mobile-bff/subject-api/search/v2') {
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'results': [
                      {
                        'subjects': [
                          {
                            'subjectId': 'animal-hindi',
                            'subjectType': 1,
                            'title': 'Animal [Hindi]',
                            'releaseDate': '2023-12-01',
                            'language':
                                'Hindi, Tamil, Telugu, Malayalam, Kannada',
                          },
                          {
                            'subjectId': 'animal-plain',
                            'subjectType': 1,
                            'title': 'Animal',
                            'releaseDate': '2023-12-01',
                            'language': 'Hindi',
                          },
                        ],
                      },
                    ],
                  },
                },
              );
            }
            if (options.uri.path == '/wefeed-mobile-bff/subject-api/get') {
              expect(options.uri.queryParameters['subjectId'], 'animal-hindi');
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'title': 'Animal [Hindi]',
                    'language': 'Hindi, Tamil, Telugu, Malayalam, Kannada',
                    'resourceDetectors': [
                      {
                        'resolutionList': [
                          {
                            'resolution': '1080p',
                            'resourceLink': 'https://cdn.example/animal-hi.mp4',
                          },
                        ],
                      },
                    ],
                  },
                },
              );
            }
            fail('Unexpected MovieBox request: ${options.uri}');
          });

        final result =
            await MovieBoxStreamProvider(
              dio: dio,
              deviceId: '00112233445566778899aabbccddeeff',
            ).resolve(
              const PlaybackRequest(
                mediaId: 'movie:781732',
                title: 'Animal',
                mediaType: PlaybackMediaType.movie,
                preferredAudioTrack: 'Tamil',
              ),
            );

        expect(result, isNotNull);
        expect(result!.selectedAudio, 'Hindi');
        expect(result.availableAudios, ['Hindi']);
      },
    );

    test(
      'falls back to play-info streams when details have no detectors',
      () async {
        final requestedUrls = <Uri>[];
        final dio = Dio()
          ..httpClientAdapter = _MovieBoxAdapter((options) {
            requestedUrls.add(options.uri);
            if (options.uri.path == '/wefeed-mobile-bff/tab/ranking-list') {
              return _MovieBoxResponse(
                body: {'code': 200, 'data': {}},
                headers: {
                  'x-user': ['{"token":"moviebox-token"}'],
                },
              );
            }
            if (options.uri.path ==
                '/wefeed-mobile-bff/subject-api/search/v2') {
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'subjects': [
                      {
                        'subjectId': 'fallback-movie',
                        'title': 'Fallback Movie',
                        'language': 'English',
                        'releaseDate': '2026-01-01',
                        'subjectType': 1,
                      },
                    ],
                  },
                },
              );
            }
            if (options.uri.path == '/wefeed-mobile-bff/subject-api/get') {
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {'title': 'Fallback Movie', 'resourceDetectors': []},
                },
              );
            }
            if (options.uri.path ==
                '/wefeed-mobile-bff/subject-api/play-info') {
              expect(options.headers['authorization'], 'Bearer moviebox-token');
              expect(options.headers['x-client-info'], contains('X-Play-Mode'));
              return _MovieBoxResponse(
                body: {
                  'code': 200,
                  'data': {
                    'streams': [
                      {
                        'format': 'MP4',
                        'resolutionList': [
                          {
                            'resolution': '720p',
                            'resourceLink':
                                'https://cdn.example/fallback-720.mp4',
                          },
                        ],
                      },
                    ],
                  },
                },
              );
            }
            fail('Unexpected MovieBox request: ${options.uri}');
          });

        final result =
            await MovieBoxStreamProvider(
              dio: dio,
              deviceId: '00112233445566778899aabbccddeeff',
            ).resolve(
              const PlaybackRequest(
                mediaId: 'movie:fallback',
                title: 'Fallback Movie',
                mediaType: PlaybackMediaType.movie,
              ),
            );

        expect(result, isNotNull);
        expect(result!.url, 'https://cdn.example/fallback-720.mp4');
        expect(result.quality, '720p');
        expect(result.headers['Referer'], 'https://api3.aoneroom.com');
        expect(
          requestedUrls.map((uri) => uri.path),
          contains('/wefeed-mobile-bff/subject-api/play-info'),
        );
      },
    );
  });

  group('StreamFlix desktop parity', () {
    test('resolves movie catalog link through download CDN', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/config/config-streamflixapp.json') {
            return {
              'download': ['https://cf.example/'],
            };
          }
          if (options.uri.path == '/data.json') {
            return {
              'data': [
                {
                  'isTV': false,
                  'moviename': 'Animal',
                  'movieyear': '2023',
                  'movietype': 'Hindi',
                  'movieinfo': 'Action/Crime/Drama',
                  'moviekey': 'chilflix-animal',
                  'movielink': 'movies/2023/animal.mkv',
                  'tmdb': '781732',
                },
              ],
            };
          }
          fail('Unexpected StreamFlix request: ${options.uri}');
        });

      final result = await StreamFlixStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'movie:781732',
          title: 'Animal',
          mediaType: PlaybackMediaType.movie,
        ),
      );

      expect(result, isNotNull);
      expect(result!.provider, 'StreamFlix');
      expect(result.url, 'https://cf.example/movies/2023/animal.mkv');
      expect(result.quality, 'Auto');
      expect(result.availableAudios, isEmpty);
      expect(result.headers['Referer'], 'https://api.streamflix.app/');
    });

    test('resolves TV episode metadata through Firebase REST', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/config/config-streamflixapp.json') {
            return {
              'download': ['https://cf.example'],
            };
          }
          if (options.uri.path == '/data.json') {
            return {
              'data': [
                {
                  'isTV': true,
                  'moviename': '1899',
                  'movieyear': '2022',
                  'movietype': 'Hindi',
                  'movieinfo': 'Mystery/Drama',
                  'moviekey': 'chilflix-1899',
                  'newseason': '1660000000',
                  'tmdb': '12345',
                },
                {
                  'isTV': true,
                  'moviename': 'Farzi',
                  'movieyear': '2023',
                  'movietype': 'Hindi',
                  'movieinfo': 'Drama/Crime',
                  'moviekey': 'chilflix-farzi',
                  'newseason': '1679427538',
                  'tmdb': '99999',
                },
              ],
            };
          }
          if (options.uri.host.contains('firebasedatabase.app') &&
              options.uri.path ==
                  '/Data/chilflix-farzi/seasons/1/episodes.json') {
            expect(
              options.uri.queryParameters['ns'],
              'chilflix-410be-default-rtdb',
            );
            return [
              {
                'key': 0,
                'name': '1. Artist',
                'link': 'tv/farzi/s1/Farzi.S01.E01.720p.HEVC.Hindi.WEB-DL.mkv',
              },
            ];
          }
          fail('Unexpected StreamFlix request: ${options.uri}');
        });

      final result = await StreamFlixStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'tv:12345',
          title: 'Farzi',
          mediaType: PlaybackMediaType.tv,
          season: 1,
          episode: 1,
        ),
      );

      expect(result, isNotNull);
      expect(
        result!.url,
        'https://cf.example/tv/farzi/s1/'
        'Farzi.S01.E01.720p.HEVC.Hindi.WEB-DL.mkv',
      );
      expect(result.quality, '720p');
      expect(result.sources.single.isM3U8, isFalse);
    });
  });

  group('Animex desktop parity', () {
    test(
      'enumerates and resolves default dub provider with audio and subtitles',
      () async {
        final requestedUrls = <Uri>[];
        final client = MockClient((request) async {
          requestedUrls.add(request.url);
          if (request.url.host == 'animex.one' &&
              request.url.path == '/anime/21') {
            return http.Response('window.__DATA__={slug:"test-slug"};', 200);
          }
          if (request.url.path == '/rest/api/servers') {
            return http.Response(
              jsonEncode({
                'subProviders': [
                  {'id': 'sub1', 'serverName': 'Sub Server'},
                ],
                'dubProviders': [
                  {'id': 'dub1', 'serverName': 'Dub Server'},
                  {'id': 'dub2', 'serverName': 'Default Dub', 'default': true},
                ],
              }),
              200,
            );
          }
          if (request.url.path == '/rest/api/sources') {
            expect(request.url.queryParameters['type'], 'dub');
            expect(request.url.queryParameters['providerId'], 'dub2');
            return http.Response(
              jsonEncode({
                'sources': [
                  {
                    'url': 'https://cdn.example/anime-dub.mp4',
                    'quality': '1080p',
                    'type': 'mp4',
                  },
                ],
                'tracks': [
                  {
                    'url': 'https://cdn.example/subtitle.vtt',
                    'lang': 'English',
                    'kind': 'captions',
                  },
                ],
                'intro': {'start': 10, 'end': 80},
              }),
              200,
            );
          }
          return http.Response('not found', 404);
        });

        final provider = AnimexStreamProvider(client: client);
        const request = PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          episode: 1,
          preferredAudioTrack: 'English (Dub)',
        );

        final servers = await provider.availableServers(request);
        final result = await provider.resolve(request, server: 'auto');

        expect(servers, ['Dub Server', 'Default Dub']);
        expect(result, isNotNull);
        expect(result!.availableAudios, ['Japanese (Sub)', 'English (Dub)']);
        expect(result.selectedAudio, 'English (Dub)');
        expect(result.url, 'https://cdn.example/anime-dub.mp4');
        expect(result.subtitles.single.lang, 'English');
        expect(result.skipTimes.single.type, 'intro');
        expect(
          requestedUrls.any(
            (uri) =>
                uri.path == '/rest/api/sources' &&
                uri.queryParameters['type'] == 'dub',
          ),
          isTrue,
        );
      },
    );
  });

  group('Xon desktop parity', () {
    test(
      'resolves cartoon/anime language variants with direct quality links',
      () async {
        final requestedUrls = <Uri>[];
        final dio = Dio()
          ..httpClientAdapter = _JsonAdapter((options) {
            requestedUrls.add(options.uri);
            if (options.uri.path == '/apis/nzgetshows.php') {
              return {
                'status': true,
                'last_updated': '2026-07-28 08:22:57',
                'movies': [
                  {
                    'id': 520,
                    'name': "Doraemon: Nobita's New Dinosaur",
                    'show_name': 'Doraemon',
                    'language_name': 'Tamil (Tamil)',
                    'basic': 'https://cdn.example/doraemon-tamil-360.mkv',
                    'sd': 'https://cdn.example/doraemon-tamil-480.mkv',
                    'hd': 'https://cdn.example/doraemon-tamil-720.mkv',
                    'fhd': 'https://cdn.example/doraemon-tamil-1080.mkv',
                  },
                  {
                    'id': 219,
                    'name': "Doraemon: Nobita's New Dinosaur",
                    'show_name': 'Doraemon',
                    'language_name': 'Hindi (Hindi)',
                    'basic': 'https://cdn.example/doraemon-hindi-360.mkv',
                    'sd': 'https://cdn.example/doraemon-hindi-480.mkv',
                    'hd': 'https://cdn.example/doraemon-hindi-720.mkv',
                    'fhd': 'https://cdn.example/doraemon-hindi-1080.mkv',
                  },
                ],
              };
            }
            if (options.uri.path == '/apis/nzgetepisodes_v2.php') {
              return {'episodes': []};
            }
            fail('Unexpected Xon request: ${options.uri}');
          });

        final provider = XonStreamProvider(dio: dio);
        const request = PlaybackRequest(
          mediaId: 'anime:999',
          title: "Doraemon: Nobita's New Dinosaur",
          mediaType: PlaybackMediaType.anime,
          preferredAudioTrack: 'Tamil',
          preferredQuality: '720p',
        );

        final servers = await provider.availableServers(request);
        final result = await provider.resolve(request, server: 'Tamil');

        expect(servers, ['Tamil', 'Hindi']);
        expect(result, isNotNull);
        expect(result!.url, 'https://cdn.example/doraemon-tamil-720.mkv');
        expect(result.quality, '720p');
        expect(result.availableAudios, ['Tamil', 'Hindi']);
        expect(result.selectedAudio, 'Tamil');
        expect(result.headers['Referer'], 'https://xon-avens.xyz/apis');
        expect(
          requestedUrls.any((uri) => uri.path == '/apis/nzgetshows.php'),
          isTrue,
        );
      },
    );

    test('keeps episode matches on the requested season', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/apis/nzgetshows.php') {
            return {'movies': []};
          }
          if (options.uri.path == '/apis/nzgetepisodes_v2.php') {
            return {
              'episodes': [
                {
                  'id': 301,
                  'season_id': 30,
                  'no': 1,
                  'name': 'Cruelty',
                  'showName': 'Demon Slayer',
                  'season_name': 'Season 03: Swordsmith Village Arc',
                  'languageName': 'தமிழ் (Tamil)',
                  'hd': 'https://cdn.example/demon-slayer-s3e1-tamil.mkv',
                },
                {
                  'id': 101,
                  'season_id': 10,
                  'no': 1,
                  'name': 'Cruelty',
                  'showName': 'Demon Slayer',
                  'season_name': 'Season 01',
                  'languageName': 'தமிழ் (Tamil)',
                  'hd': 'https://cdn.example/demon-slayer-s1e1-tamil.mkv',
                },
                {
                  'id': 102,
                  'season_id': 10,
                  'no': 1,
                  'name': 'Cruelty',
                  'showName': 'Demon Slayer',
                  'season_name': 'Season 01',
                  'languageName': 'English',
                  'hd': 'https://cdn.example/demon-slayer-s1e1-english.mkv',
                },
              ],
            };
          }
          fail('Unexpected Xon request: ${options.uri}');
        });

      final provider = XonStreamProvider(dio: dio);
      const request = PlaybackRequest(
        mediaId: 'anime:999',
        title: 'Demon Slayer: Kimetsu no Yaiba',
        mediaType: PlaybackMediaType.anime,
        season: 1,
        episode: 1,
        preferredAudioTrack: 'Tamil',
        preferredQuality: '720p',
      );

      final servers = await provider.availableServers(request);
      final result = await provider.resolve(request, server: 'Tamil');

      expect(servers, ['Tamil', 'English']);
      expect(result, isNotNull);
      expect(result!.url, 'https://cdn.example/demon-slayer-s1e1-tamil.mkv');
      expect(result.selectedAudio, 'Tamil');
      expect(result.availableAudios, ['Tamil', 'English']);
    });

    test('does not expose a fake server when catalog has no match', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/apis/nzgetshows.php') {
            return {'movies': []};
          }
          if (options.uri.path == '/apis/nzgetepisodes_v2.php') {
            return {'episodes': []};
          }
          fail('Unexpected Xon request: ${options.uri}');
        });
      final adapter = AnimeProviderAdapter(
        priority: 100,
        provider: XonStreamProvider(dio: dio),
      );

      final sources = await adapter.enumerateServers(
        const PlaybackRequest(
          mediaId: 'anime:21',
          title: 'One Piece',
          mediaType: PlaybackMediaType.anime,
          season: 1,
          episode: 1,
        ),
      );

      expect(sources, isEmpty);
    });
  });

  group('Animetsu desktop parity', () {
    test('returns audio labels, subtitles, and Android skip markers', () async {
      final dio = Dio()
        ..httpClientAdapter = _JsonAdapter((options) {
          if (options.uri.path == '/v2/api/anime/search') {
            return {
              'results': [
                {
                  'id': 'internal-21',
                  'cover_image': {'large': 'https://img.example/bx21.jpg'},
                },
              ],
            };
          }
          if (options.uri.path == '/v2/api/anime/oppai/internal-21/1') {
            expect(options.uri.queryParameters['source_type'], 'dub');
            return {
              'sources': [
                {
                  'url': 'https://cdn.example/animetsu.m3u8',
                  'quality': '1080p',
                  'type': 'hls',
                },
              ],
              'subs': [
                {'url': 'https://cdn.example/en.vtt', 'lang': 'English'},
              ],
              'skips': {
                'intro': {'start': 12, 'end': 90},
                'outro': {'start': 1300, 'end': 1380},
              },
            };
          }
          fail('Unexpected Animetsu request: ${options.uri}');
        });

      final result = await AnimetsuStreamProvider(dio: dio).resolve(
        const PlaybackRequest(
          mediaId: 'anime:21',
          title: 'Anime',
          mediaType: PlaybackMediaType.anime,
          episode: 1,
          preferredAudioTrack: 'English',
        ),
        server: 'kite',
      );

      expect(result, isNotNull);
      expect(result!.availableAudios, ['Default', 'English']);
      expect(result.selectedAudio, 'English');
      expect(result.subtitles.single.lang, 'English');
      expect(result.skipTimes.map((skip) => skip.type), ['op', 'ed']);
      expect(result.skipTimes.first.startTime, const Duration(seconds: 12));
      expect(result.isM3U8, isTrue);
    });
  });
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.handler);

  final Object? Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(handler(options)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MovieBoxResponse {
  const _MovieBoxResponse({required this.body, this.headers = const {}});

  final Object? body;
  final Map<String, List<String>> headers;
}

class _MovieBoxAdapter implements HttpClientAdapter {
  _MovieBoxAdapter(this.handler);

  final _MovieBoxResponse Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final response = handler(options);
    return ResponseBody.fromString(
      response.body is String
          ? response.body! as String
          : jsonEncode(response.body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
        ...response.headers,
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _CastleAdapter implements HttpClientAdapter {
  _CastleAdapter(this.handler);

  final Object? Function(RequestOptions options) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final body = handler(options);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [
          body is String
              ? Headers.textPlainContentType
              : Headers.jsonContentType,
        ],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

String _castleEncrypt(Map<String, Object?> json) {
  final key = Uint8List.fromList([
    ...base64Decode('ZkpBVG0qa2dmSg=='),
    ...utf8.encode('T!BgJB'),
  ]);
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), key),
          null,
        ),
      );
  final encrypted = cipher.process(
    Uint8List.fromList(utf8.encode(jsonEncode(json))),
  );
  return base64Encode(encrypted);
}
