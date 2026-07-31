import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivio_desktop/features/live_tv/services/builtin_live_tv_providers.dart';
import 'package:nivio_desktop/features/player/models/playback_request.dart';
import 'package:nivio_desktop/features/player/services/desktop_streaming_service.dart';
import 'package:pointycastle/export.dart';

class _FakeHealthChecker implements StreamHealthChecker {
  final checkedSources = <String>[];

  @override
  Future<StreamValidationResult> validate(
    String source,
    Map<String, String> headers, {
    bool isHls = false,
  }) async {
    checkedSources.add(source);
    return StreamValidationResult(
      playable: true,
      kind: isHls ? StreamContentKind.hls : StreamContentKind.unknown,
      statusCode: 200,
      contentType: 'application/vnd.apple.mpegurl',
      finalUrl: source,
    );
  }
}

void main() {
  group('BuiltInLiveTvProviders', () {
    test('loads TamilUltra cards and resolves channel page m3u8', () async {
      final client = MockClient((request) async {
        if (request.url.toString() == 'https://tamilultra.co.uk') {
          return http.Response('''
            <article class="result-item genre_tamil-news">
              <div class="poster"><img src="https://img.example/sun.png"></div>
              <div class="data">
                <h3><a href="https://tamilultra.co.uk/sun-news-tamil/">SUN NEWS - TAMIL</a></h3>
              </div>
            </article>
          ''', 200);
        }
        if (request.url.toString() ==
            'https://tamilultra.co.uk/sun-news-tamil/') {
          return http.Response(
            r'''<script>var file="https:\/\/cdn.example\/sun-news.m3u8";</script>''',
            200,
          );
        }
        if (request.url.toString() == 'https://fifabd.site/OPLLX7/LIVE2.m3u') {
          return http.Response('#EXTM3U', 200);
        }
        return http.Response('', 404);
      });

      final providers = BuiltInLiveTvProviders(client: client);
      final channels = await providers.loadChannels(const []);

      expect(channels, hasLength(1));
      expect(channels.single.name, 'SUN NEWS - TAMIL');
      expect(channels.single.group, 'TamilUltra - Tamil News');
      expect(
        BuiltInLiveTvProviders.isBuiltInSource(channels.single.url),
        isTrue,
      );

      final result = await providers.resolve(channels.single.url);

      expect(result?.provider, 'TamilUltra');
      expect(result?.url, 'https://cdn.example/sun-news.m3u8');
      expect(result?.isM3U8, isTrue);
    });

    test(
      'loads SportzX direct playlist entries and skips DRM entries',
      () async {
        final client = MockClient((request) async {
          if (request.url.toString() == 'https://tamilultra.co.uk') {
            return http.Response('', 200);
          }
          if (request.url.toString() ==
              'https://fifabd.site/OPLLX7/LIVE2.m3u') {
            return http.Response('''
#EXTM3U
#EXTINF:-1 tvg-logo="https://img.example/fta.png" group-title="Cricket", Free Match
https://cdn.example/free-match.m3u8
#KODIPROP:inputstream.adaptive.license_key=deadbeef:feedface
#EXTINF:-1 group-title="Premium", DRM Match
https://cdn.example/drm-match.mpd
''', 200);
          }
          return http.Response('', 404);
        });

        final providers = BuiltInLiveTvProviders(client: client);
        final channels = await providers.loadChannels(const []);

        expect(channels, hasLength(1));
        expect(channels.single.name, 'Free Match');
        expect(channels.single.group, 'SportzX - Cricket');

        final result = await providers.resolve(channels.single.url);

        expect(result?.provider, 'SportzX');
        expect(result?.url, 'https://cdn.example/free-match.m3u8');
      },
    );

    test('loads SportzX encrypted static fallback event entries', () async {
      final encryptedEvents = _encryptSportzxPrimary(
        jsonEncode({
          'data': [
            {
              'title': 'India vs Australia',
              'image': 'https://img.example/cricket.png',
              'cat': 'Cricket',
              'formats': [
                {'title': 'HD', 'link': 'https://cdn.example/india-aus.m3u8'},
              ],
            },
          ],
        }),
      );
      final client = MockClient((request) async {
        if (request.url.toString() == 'https://tamilultra.co.uk') {
          return http.Response('', 200);
        }
        if (request.url.toString() == 'https://modi-home.top/events.json') {
          return http.Response(jsonEncode({'data': encryptedEvents}), 200);
        }
        if (request.url.toString() == 'https://fifabd.site/OPLLX7/LIVE2.m3u') {
          return http.Response('#EXTM3U', 200);
        }
        return http.Response('', 404);
      });

      final providers = BuiltInLiveTvProviders(client: client);
      final channels = await providers.loadChannels(const []);

      expect(channels, hasLength(1));
      expect(channels.single.name, 'India vs Australia · HD');
      expect(channels.single.group, 'SportzX - Cricket');

      final result = await providers.resolve(channels.single.url);

      expect(result?.provider, 'SportzX');
      expect(result?.url, 'https://cdn.example/india-aus.m3u8');
    });
  });

  test(
    'DesktopStreamingService resolves built-in live source before health check',
    () async {
      final source = BuiltInLiveTvProviders.encodeSource({
        'provider': 'sportzx',
        'streamUrl': 'https://cdn.example/live-sport.m3u8',
        'name': 'Live Sport',
      });
      final healthChecker = _FakeHealthChecker();
      final service = DesktopStreamingService(
        healthChecker: healthChecker,
        builtInLiveTvProviders: BuiltInLiveTvProviders(
          client: MockClient((_) {
            return Future.value(http.Response('', 404));
          }),
        ),
      );

      final result = await service.resolve(
        PlaybackRequest(
          mediaId: 'live:sportzx',
          title: 'Live Sport',
          mediaType: PlaybackMediaType.liveTv,
          source: source,
          isLive: true,
        ),
      );

      expect(result.url, 'https://cdn.example/live-sport.m3u8');
      expect(result.provider, 'SportzX');
      expect(healthChecker.checkedSources, [
        'https://cdn.example/live-sport.m3u8',
      ]);
    },
  );
}

String _encryptSportzxPrimary(
  String plaintext, {
  List<int> salt = const [1, 2, 3, 4],
}) {
  final ctxHash = _hex(
    '1676ec7db4771b0d826d70369b579684b182d2c0133be041bdd55f5d6d79a98b',
  );
  final info = Uint8List.fromList([...salt, ...ctxHash]);
  final okm = _hkdfLike(info, info, 48);
  final key = Uint8List.fromList(okm.sublist(0, 32));
  final iv = Uint8List.fromList(okm.sublist(32, 48));
  final transformed = _sportzxEncryptTransform(utf8.encode(plaintext), ctxHash);
  final cipher =
      PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))..init(
        true,
        PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
          ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
          null,
        ),
      );
  final encrypted = cipher.process(transformed);
  final blob = Uint8List.fromList([
    0xde,
    0xad,
    0xbe,
    0xef,
    salt.length,
    ...encrypted,
    ...salt,
  ]);
  return base64Url.encode(blob).replaceAll('=', '');
}

Uint8List _sportzxEncryptTransform(List<int> bytes, Uint8List ctxHash) {
  final output = Uint8List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final xored = (bytes[i] & 0xff) ^ (ctxHash[i % ctxHash.length] & 0xff);
    output[i] = (((xored << 3) & 0xff) | (xored >> 5)) & 0xff;
  }
  return output;
}

Uint8List _hkdfLike(Uint8List key, Uint8List info, int length) {
  final out = BytesBuilder(copy: false);
  var previous = <int>[];
  var counter = 1;
  while (out.length < length) {
    final block = Hmac(
      sha256,
      key,
    ).convert([...previous, ...info, counter]).bytes;
    out.add(block);
    previous = block;
    counter++;
  }
  return Uint8List.fromList(out.takeBytes().sublist(0, length));
}

Uint8List _hex(String hex) {
  final output = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < hex.length; i += 2) {
    output[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
  }
  return output;
}
