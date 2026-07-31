import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';

import '../../../shared/models/iptv_channel.dart';
import '../../../shared/models/stream_result.dart';

class BuiltInLiveTvProviders {
  BuiltInLiveTvProviders({http.Client? client}) : this._(client);

  const BuiltInLiveTvProviders._(this._client);

  static const sourceScheme = 'nivio-live';
  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36';
  static const _providerLoadTimeout = Duration(seconds: 8);

  final http.Client? _client;

  Future<List<IptvChannel>> loadChannels(List<String> favorites) async {
    final providers = <_BuiltInLiveTvProvider>[
      _TamilUltraLiveTvProvider(client: _client),
      _SportzxLiveTvProvider(client: _client),
    ];
    final channels = <IptvChannel>[];
    final seenUrls = <String>{};

    final loadedProviders = await Future.wait(
      providers.map((provider) async {
        try {
          return await provider
              .loadChannels(favorites)
              .timeout(_providerLoadTimeout);
        } catch (error) {
          debugPrint('[iptv:${provider.id}] unavailable: $error');
          return const <IptvChannel>[];
        }
      }),
    );

    for (final loaded in loadedProviders) {
      for (final channel in loaded) {
        if (channel.url.trim().isEmpty || !seenUrls.add(channel.url)) {
          continue;
        }
        channels.add(channel);
      }
    }

    return channels;
  }

  Future<List<IptvChannel>> loadProviderChannels(
    String providerId,
    List<String> favorites,
  ) async {
    final provider = switch (providerId) {
      _TamilUltraLiveTvProvider.providerId => _TamilUltraLiveTvProvider(
        client: _client,
      ),
      _SportzxLiveTvProvider.providerId => _SportzxLiveTvProvider(
        client: _client,
      ),
      _ => null,
    };
    if (provider == null) return const [];

    try {
      final loaded = await provider
          .loadChannels(favorites)
          .timeout(_providerLoadTimeout);
      final channels = <IptvChannel>[];
      final seenUrls = <String>{};
      for (final channel in loaded) {
        if (channel.url.trim().isEmpty || !seenUrls.add(channel.url)) {
          continue;
        }
        channels.add(channel);
      }
      return channels;
    } catch (error) {
      debugPrint('[iptv:${provider.id}] unavailable: $error');
      return const [];
    }
  }

  Future<StreamResult?> resolve(String source) async {
    final payload = decodeSource(source);
    if (payload == null) return null;
    final providerId = payload['provider']?.toString();
    final provider = switch (providerId) {
      _TamilUltraLiveTvProvider.providerId => _TamilUltraLiveTvProvider(
        client: _client,
      ),
      _SportzxLiveTvProvider.providerId => _SportzxLiveTvProvider(
        client: _client,
      ),
      _ => null,
    };
    if (provider == null) return null;
    return provider.resolve(payload);
  }

  static bool isBuiltInSource(String source) {
    return Uri.tryParse(source)?.scheme == sourceScheme;
  }

  static String encodeSource(Map<String, String> payload) {
    final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
    return '$sourceScheme://channel/$encoded';
  }

  static Map<String, dynamic>? decodeSource(String source) {
    final uri = Uri.tryParse(source);
    if (uri == null || uri.scheme != sourceScheme) return null;
    final encoded = uri.pathSegments.isNotEmpty
        ? uri.pathSegments.last
        : uri.host;
    if (encoded.isEmpty) return null;
    try {
      final normalized = base64Url.normalize(encoded);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final json = jsonDecode(decoded);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> get defaultHeaders => const {
    'User-Agent': _userAgent,
    'Accept': '*/*',
  };
}

abstract class _BuiltInLiveTvProvider {
  String get id;

  Future<List<IptvChannel>> loadChannels(List<String> favorites);

  Future<StreamResult?> resolve(Map<String, dynamic> payload);
}

class _TamilUltraLiveTvProvider implements _BuiltInLiveTvProvider {
  _TamilUltraLiveTvProvider({http.Client? client})
    : _client = client ?? http.Client();

  static const providerId = 'tamilultra';
  static const _mainUrl = 'https://tamilultra.co.uk';

  final http.Client _client;

  @override
  String get id => _TamilUltraLiveTvProvider.providerId;

  @override
  Future<List<IptvChannel>> loadChannels(List<String> favorites) async {
    final html = await _getText(Uri.parse(_mainUrl));
    final cards = _extractTamilUltraCards(html);
    return cards
        .map(
          (card) => IptvChannel(
            name: card.name,
            url: BuiltInLiveTvProviders.encodeSource({
              'provider': id,
              'pageUrl': card.pageUrl,
              'name': card.name,
            }),
            group: 'TamilUltra - ${card.group}',
            logo: card.logo,
            tvgId: 'tamilultra:${_stableId(card.pageUrl)}',
            isFavorite: favorites.contains(
              BuiltInLiveTvProviders.encodeSource({
                'provider': id,
                'pageUrl': card.pageUrl,
                'name': card.name,
              }),
            ),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<StreamResult?> resolve(Map<String, dynamic> payload) async {
    final pageUrl = payload['pageUrl']?.toString();
    if (pageUrl == null || pageUrl.isEmpty) return null;
    final pageUri = Uri.tryParse(pageUrl);
    if (pageUri == null) return null;

    final pageHtml = await _getText(pageUri);
    final pageHeaders = {
      ...BuiltInLiveTvProviders.defaultHeaders,
      'Referer': pageUrl,
    };

    final directFromPage = _firstPlayableUrl(pageHtml);
    if (directFromPage != null) {
      return _result(payload, directFromPage, headers: pageHeaders);
    }

    final iframe = _firstIframeUrl(pageHtml, pageUri);
    if (iframe != null) {
      final iframeResult = await _resolveEmbed(payload, iframe, pageUrl);
      if (iframeResult != null) return iframeResult;
    }

    final postId = _extractPostId(pageHtml);
    if (postId == null) return null;

    for (final type in const ['movie', 'tv']) {
      for (var nume = 1; nume <= 5; nume++) {
        final ajax = await _postAjax(pageUri, postId, nume, type);
        final url = _extractEmbedUrl(ajax, pageUri);
        if (url == null) continue;
        if (_isPlayableUrl(url)) {
          return _result(payload, url, headers: pageHeaders);
        }
        final embedResult = await _resolveEmbed(payload, url, pageUrl);
        if (embedResult != null) return embedResult;
      }
    }

    return null;
  }

  Future<StreamResult?> _resolveEmbed(
    Map<String, dynamic> payload,
    String embedUrl,
    String pageUrl,
  ) async {
    final uri = Uri.tryParse(embedUrl);
    if (uri == null) return null;
    final html = await _getText(
      uri,
      headers: {'Referer': pageUrl, ...BuiltInLiveTvProviders.defaultHeaders},
    );
    final direct = _firstPlayableUrl(html);
    if (direct == null) return null;
    return _result(
      payload,
      direct,
      headers: {
        ...BuiltInLiveTvProviders.defaultHeaders,
        'Referer': uri.origin,
      },
    );
  }

  Future<String> _postAjax(
    Uri pageUri,
    String postId,
    int nume,
    String type,
  ) async {
    final response = await _client
        .post(
          pageUri.resolve('/wp-admin/admin-ajax.php'),
          headers: {
            ...BuiltInLiveTvProviders.defaultHeaders,
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': pageUri.toString(),
          },
          body: {
            'action': 'doo_player_ajax',
            'post': postId,
            'nume': '$nume',
            'type': type,
          },
        )
        .timeout(const Duration(seconds: 8));
    if (response.statusCode < 200 || response.statusCode >= 400) return '';
    return response.body;
  }

  Future<String> _getText(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client
        .get(
          uri,
          headers: {...BuiltInLiveTvProviders.defaultHeaders, ...headers},
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw BuiltInLiveTvProviderException(
        'TamilUltra HTTP ${response.statusCode}',
      );
    }
    return response.body;
  }
}

class _SportzxLiveTvProvider implements _BuiltInLiveTvProvider {
  _SportzxLiveTvProvider({http.Client? client})
    : _client = client ?? http.Client();

  static const providerId = 'sportzx';
  static const _defaultBaseUrl = 'https://modi-home.top/';
  static const _playlistUrl = 'https://fifabd.site/OPLLX7/LIVE2.m3u';
  static const _apiCandidates = [
    _defaultBaseUrl,
    'https://sportzx.live/',
    'https://streamtvapp.top/',
  ];

  final http.Client _client;

  @override
  String get id => _SportzxLiveTvProvider.providerId;

  @override
  Future<List<IptvChannel>> loadChannels(List<String> favorites) async {
    final channels = <IptvChannel>[];
    final errors = <String>[];
    final bases = await _sportzxApiBases();
    for (final baseUrl in bases) {
      try {
        channels.addAll(await _loadEventApi(baseUrl, favorites));
      } catch (error) {
        errors.add('$baseUrl: $error');
        // SportzX rotates its API host. Keep trying the known public fallbacks.
      }
    }

    try {
      channels.addAll(await _loadPlaylist(favorites));
    } catch (error) {
      if (channels.isEmpty) {
        errors.add('playlist: $error');
        throw BuiltInLiveTvProviderException(
          'SportzX failed: ${errors.join(' | ')}',
        );
      }
    }

    final seen = <String>{};
    return channels.where((channel) => seen.add(channel.url)).toList();
  }

  @override
  Future<StreamResult?> resolve(Map<String, dynamic> payload) async {
    final resolvedUrl = await _resolvePayloadUrl(payload);
    if (resolvedUrl == null || !_isPlayableUrl(resolvedUrl)) {
      return null;
    }
    return _result(
      payload,
      resolvedUrl,
      provider: 'SportzX',
      headers: {
        ...BuiltInLiveTvProviders.defaultHeaders,
        'Referer': payload['referer']?.toString().isNotEmpty == true
            ? payload['referer'].toString()
            : 'https://sportzx.live/',
        'Origin': payload['origin']?.toString().isNotEmpty == true
            ? payload['origin'].toString()
            : 'https://sportzx.live',
      },
    );
  }

  Future<List<String>> _sportzxApiBases() async {
    final bases = <String>{};
    bases.addAll(_apiCandidates.map(_withTrailingSlash));
    return bases.toList(growable: false);
  }

  Future<String?> _resolvePayloadUrl(Map<String, dynamic> payload) async {
    final direct = payload['streamUrl']?.toString();
    if (direct != null && direct.isNotEmpty && _isPlayableUrl(direct)) {
      return direct;
    }

    final apiUrl = payload['apiUrl']?.toString();
    if (apiUrl == null || apiUrl.isEmpty) return null;

    final response = await _client
        .get(Uri.parse(apiUrl), headers: BuiltInLiveTvProviders.defaultHeaders)
        .timeout(const Duration(seconds: 7));
    if (response.statusCode < 200 || response.statusCode >= 400) return null;
    final decoded = _decodeSportzxJson(response.body);
    final maps = _flattenJsonMaps(decoded);
    for (final map in maps) {
      if (_hasDrm(map)) continue;
      final streamUrl = _firstString(map, const [
        'url',
        'streamUrl',
        'channel',
        'link',
        'playUrl',
        'file',
      ]);
      if (streamUrl != null && _isPlayableUrl(streamUrl)) {
        return streamUrl;
      }
    }
    return null;
  }

  Future<List<IptvChannel>> _loadPlaylist(List<String> favorites) async {
    final response = await _client
        .get(
          Uri.parse(_playlistUrl),
          headers: BuiltInLiveTvProviders.defaultHeaders,
        )
        .timeout(const Duration(seconds: 6));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      throw BuiltInLiveTvProviderException(
        'SportzX playlist HTTP ${response.statusCode}',
      );
    }
    return _parseSportzxM3u(response.body, favorites);
  }

  Future<List<IptvChannel>> _loadEventApi(
    String baseUrl,
    List<String> favorites,
  ) async {
    final apiUrl = Uri.parse(
      _withTrailingSlash(baseUrl),
    ).resolve('events.json');
    final response = await _client
        .get(apiUrl, headers: BuiltInLiveTvProviders.defaultHeaders)
        .timeout(const Duration(seconds: 5));
    if (response.statusCode < 200 || response.statusCode >= 400) {
      return const [];
    }
    final body = response.body.trim();
    if (body.isEmpty || body.startsWith('<')) return const [];
    final decoded = _decodeSportzxJson(body);
    final events = _flattenJsonMaps(decoded);
    final channels = <IptvChannel>[];
    for (final event in events) {
      if (!_isSportzxEventMap(event)) continue;
      final streamEntries = _sportzxStreamEntries(event, apiUrl);
      if (streamEntries.isEmpty) continue;
      final streamUrl = _firstString(event, const [
        'url',
        'streamUrl',
        'channel',
        'link',
        'playUrl',
        'file',
      ]);
      if (_hasDrm(event)) continue;
      final title =
          _firstString(event, const ['eventName', 'name', 'title']) ??
          'SportzX Event';
      final group =
          _firstString(event, const [
            'eventCat',
            'category',
            'eventType',
            'cat',
          ]) ??
          'Live Sports';
      final logo =
          _firstString(event, const ['eventLogo', 'logo', 'image']) ?? '';
      for (final entry in streamEntries) {
        final direct = entry.link ?? streamUrl;
        final api = entry.api;
        if ((direct == null || !_isPlayableUrl(direct)) && api == null) {
          continue;
        }
        final sourcePayload = <String, String>{
          'provider': id,
          'name': title,
          'referer': 'https://sportzx.live/',
          'origin': 'https://sportzx.live',
        };
        if (direct != null && _isPlayableUrl(direct)) {
          sourcePayload['streamUrl'] = direct;
        }
        if (api != null) {
          sourcePayload['apiUrl'] = api;
        }
        final source = BuiltInLiveTvProviders.encodeSource(sourcePayload);
        final suffix = entry.title;
        channels.add(
          IptvChannel(
            name: suffix == null || suffix == title
                ? title
                : '$title · $suffix',
            url: source,
            group: 'SportzX - $group',
            logo: logo,
            tvgId: 'sportzx:${_stableId(direct ?? api ?? title)}',
            isFavorite: favorites.contains(source),
          ),
        );
      }
    }
    return channels;
  }
}

class BuiltInLiveTvProviderException implements Exception {
  const BuiltInLiveTvProviderException(this.message);

  final String message;

  @override
  String toString() => message;
}

class _TamilUltraCard {
  const _TamilUltraCard({
    required this.name,
    required this.pageUrl,
    required this.group,
    required this.logo,
  });

  final String name;
  final String pageUrl;
  final String group;
  final String logo;
}

List<_TamilUltraCard> _extractTamilUltraCards(String html) {
  final cards = <_TamilUltraCard>[];
  final seen = <String>{};
  final blocks = [
    ..._blocks(html, 'article'),
    ...RegExp(
      r'''<div\b[^>]*class=["'][^"']*result-item[^"']*["'][^>]*>[\s\S]*?</div>\s*</div>''',
      caseSensitive: false,
    ).allMatches(html).map((match) => match.group(0) ?? ''),
  ];

  for (final block in blocks) {
    if (!block.contains('genre_') && !block.contains('result-item')) continue;
    final link = _firstAnchor(block);
    if (link == null || !link.url.contains('tamilultra.co.uk')) continue;
    final name = _cleanText(link.text);
    if (name.isEmpty ||
        name.length > 80 ||
        name.toLowerCase() == 'see all' ||
        !seen.add(link.url)) {
      continue;
    }
    cards.add(
      _TamilUltraCard(
        name: name,
        pageUrl: link.url,
        group: _inferTamilUltraGroup(name, block),
        logo: _firstImage(block),
      ),
    );
  }

  return cards;
}

List<String> _blocks(String html, String tag) {
  return RegExp(
    '<$tag\\b[^>]*>[\\s\\S]*?</$tag>',
    caseSensitive: false,
  ).allMatches(html).map((match) => match.group(0) ?? '').toList();
}

_Anchor? _firstAnchor(String html) {
  final match = RegExp(
    r'''<a\b[^>]*href=["']([^"']+)["'][^>]*>([\s\S]*?)</a>''',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) return null;
  return _Anchor(
    url: _htmlDecode(match.group(1) ?? ''),
    text: match.group(2) ?? '',
  );
}

String _firstImage(String html) {
  final match = RegExp(
    r'''<img\b[^>]*(?:data-src|src)=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  return _htmlDecode(match?.group(1) ?? '');
}

String? _extractPostId(String html) {
  return RegExp(
        r'''data-post=["'](\d+)["']''',
        caseSensitive: false,
      ).firstMatch(html)?.group(1) ??
      RegExp(
        r'''id=["']post-(\d+)["']''',
        caseSensitive: false,
      ).firstMatch(html)?.group(1);
}

String? _firstIframeUrl(String html, Uri baseUri) {
  final match = RegExp(
    r'''<iframe\b[^>]*src=["']([^"']+)["']''',
    caseSensitive: false,
  ).firstMatch(html);
  final raw = _htmlDecode(match?.group(1) ?? '').trim();
  if (raw.isEmpty) return null;
  return baseUri.resolve(raw).toString();
}

String? _extractEmbedUrl(String response, Uri baseUri) {
  final decoded = _htmlDecode(response);
  try {
    final json = jsonDecode(decoded);
    if (json is Map<String, dynamic>) {
      final value = json['embed_url'] ?? json['embedUrl'] ?? json['url'];
      if (value != null) {
        return baseUri.resolve(_htmlDecode(value.toString())).toString();
      }
    }
  } catch (_) {
    // Some hosts return a raw HTML/player snippet instead of JSON.
  }
  final direct = _firstPlayableUrl(decoded);
  if (direct != null) return direct;
  return _firstIframeUrl(decoded, baseUri);
}

String? _firstPlayableUrl(String html) {
  final decoded = _htmlDecode(html).replaceAll(r'\/', '/');
  final match = RegExp(
    r'''https?:\/\/[^\s"'<>\\]+?\.(?:m3u8|mpd)(?:\?[^\s"'<>\\]*)?''',
    caseSensitive: false,
  ).firstMatch(decoded);
  return match?.group(0);
}

bool _isPlayableUrl(String url) {
  final lower = url.toLowerCase();
  return lower.contains('.m3u8') || lower.contains('.mpd');
}

List<IptvChannel> _parseSportzxM3u(String rawM3u, List<String> favorites) {
  final channels = <IptvChannel>[];
  final lines = const LineSplitter().convert(rawM3u);
  String? currentName;
  var currentGroup = 'Live Sports';
  var currentLogo = '';
  var currentHasDrm = false;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lower = line.toLowerCase();
    if (lower.contains('drm-key') || lower.contains('license_key')) {
      currentHasDrm = true;
      continue;
    }
    if (line.startsWith('#EXTINF:')) {
      currentName = _cleanText(
        line.contains(',') ? line.substring(line.lastIndexOf(',') + 1) : '',
      );
      currentGroup = _extractM3uAttribute(line, 'group-title') ?? 'Live Sports';
      currentLogo = _extractM3uAttribute(line, 'tvg-logo') ?? '';
      continue;
    }
    if (line.startsWith('#')) continue;
    final name = currentName;
    if (name == null || name.isEmpty) continue;
    if (!_isPlayableUrl(line) || currentHasDrm) {
      currentName = null;
      currentLogo = '';
      currentGroup = 'Live Sports';
      currentHasDrm = false;
      continue;
    }

    final source = BuiltInLiveTvProviders.encodeSource({
      'provider': _SportzxLiveTvProvider.providerId,
      'streamUrl': line,
      'name': name,
    });
    channels.add(
      IptvChannel(
        name: name,
        url: source,
        group: 'SportzX - $currentGroup',
        logo: currentLogo,
        tvgId: 'sportzx:${_stableId(line)}',
        isFavorite: favorites.contains(source),
      ),
    );
    currentName = null;
    currentLogo = '';
    currentGroup = 'Live Sports';
    currentHasDrm = false;
  }

  return channels;
}

String? _extractM3uAttribute(String line, String attributeName) {
  final regex = RegExp('$attributeName="([^"]*)"');
  return regex.firstMatch(line)?.group(1);
}

List<Map<String, dynamic>> _flattenJsonMaps(Object? value) {
  final maps = <Map<String, dynamic>>[];
  void visit(Object? item) {
    if (item is Map<String, dynamic>) {
      maps.add(item);
      item.values.forEach(visit);
    } else if (item is List) {
      item.forEach(visit);
    }
  }

  visit(value);
  return maps;
}

bool _hasDrm(Map<String, dynamic> json) {
  return _firstString(json, const [
        'drmKeys',
        'drmKey',
        'drm-key',
        'drm-keyid',
        'licenseUrl',
      ]) !=
      null;
}

bool _isSportzxEventMap(Map<String, dynamic> json) {
  return json.containsKey('formats') ||
      json.containsKey('formatsNew') ||
      json.containsKey('streams') ||
      json.containsKey('links') ||
      json.containsKey('eventId') ||
      json.containsKey('eventInfo') ||
      json.containsKey('eventName') ||
      json.containsKey('eventCat') ||
      json.containsKey('cat') ||
      json.containsKey('image');
}

Object? _decodeSportzxJson(String body) {
  final decoded = jsonDecode(body);
  final data = _asStringMap(decoded)?['data']?.toString();
  if (data == null || data.trim().isEmpty) return decoded;
  final decrypted = _SportzxCrypto.decrypt(data);
  if (decrypted == null || decrypted.trim().isEmpty) {
    final version = _SportzxCrypto.encryptedVersion(data);
    if (version != null) {
      throw const FormatException(
        'SportzX encrypted API payload uses unsupported v2 native format',
      );
    }
    return decoded;
  }
  return jsonDecode(decrypted);
}

List<_SportzxStreamEntry> _sportzxStreamEntries(
  Map<String, dynamic> event,
  Uri baseUri,
) {
  final direct = _firstString(event, const [
    'url',
    'streamUrl',
    'channel',
    'link',
    'playUrl',
    'file',
  ]);
  final api = _firstString(event, const ['api', 'apiUrl', 'dataUrl']);
  final entries = <_SportzxStreamEntry>[
    if (direct != null || api != null)
      _SportzxStreamEntry(
        title: _firstString(event, const ['format', 'quality', 'title']),
        link: direct,
        api: api == null ? null : baseUri.resolve(api).toString(),
      ),
  ];

  for (final key in const ['formats', 'formatsNew', 'streams', 'links']) {
    final list = event[key];
    if (list is! List) continue;
    for (final item in list) {
      final map = _asStringMap(item);
      if (map == null || _hasDrm(map)) continue;
      final link = _firstString(map, const [
        'url',
        'streamUrl',
        'channel',
        'link',
        'playUrl',
        'file',
      ]);
      final itemApi = _firstString(map, const ['api', 'apiUrl', 'dataUrl']);
      entries.add(
        _SportzxStreamEntry(
          title: _firstString(map, const [
            'format',
            'quality',
            'title',
            'name',
          ]),
          link: link,
          api: itemApi == null ? null : baseUri.resolve(itemApi).toString(),
        ),
      );
    }
  }

  return entries;
}

Map<String, dynamic>? _asStringMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return null;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

String _withTrailingSlash(String value) =>
    value.endsWith('/') ? value : '$value/';

class _SportzxStreamEntry {
  const _SportzxStreamEntry({this.title, this.link, this.api});

  final String? title;
  final String? link;
  final String? api;
}

class _SportzxCrypto {
  static final Uint8List _charset = Uint8List.fromList(
    utf8.encode(
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+!@#\$%&=',
    ),
  );
  static final Uint8List _magic = Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]);
  static final Uint8List _prk = _hex(
    'd1a7ebbaed93b2f68ac092ade2b0075d917634447a3519b41e817ad631020053',
  );
  static final Uint8List _ctxHash = _hex(
    '1676ec7db4771b0d826d70369b579684b182d2c0133be041bdd55f5d6d79a98b',
  );
  static final ({Uint8List key, Uint8List iv}) _legacyAes = _generateAesKeyIv(
    'oAR80SGuX3EEjUGFRwLFKBTiris=',
  );

  static String? decrypt(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return _decryptPrimary(trimmed) ??
        _decryptFallback(trimmed) ??
        _decryptFallback2(trimmed);
  }

  static int? encryptedVersion(String value) {
    try {
      final data = _decodeBase64Url(value.trim());
      if (data.isEmpty) return null;
      if (data.length > _magic.length &&
          Iterable<int>.generate(
            _magic.length,
          ).every((index) => data[index] == _magic[index])) {
        return 1;
      }
      return data.first == 0x02 ? 2 : null;
    } catch (_) {
      return null;
    }
  }

  static String? _decryptPrimary(String value) {
    try {
      final data = _decodeBase64Url(value);
      if (data.length < 5) throw const FormatException('Blob too short');
      for (var i = 0; i < _magic.length; i++) {
        if (data[i] != _magic[i]) throw const FormatException('Bad magic');
      }
      final saltLength = data[4] & 0xff;
      final total = data.length;
      if (total < saltLength + 5) {
        throw const FormatException('Blob too short');
      }

      final payloadEnd = saltLength > 0 ? total - saltLength : total;
      final payload = Uint8List.fromList(data.sublist(5, payloadEnd));
      final tail = saltLength > 0
          ? Uint8List.fromList(data.sublist(payloadEnd, total))
          : Uint8List(0);
      if (payload.isEmpty) return '';
      if (payload.length % 16 != 0) {
        throw const FormatException('Payload length not AES-block-aligned');
      }

      final info = Uint8List.fromList([...tail, ..._ctxHash]);
      final okm = _hkdfLike(info, info, 48);
      final key = Uint8List.fromList(okm.sublist(0, 32));
      final iv = Uint8List.fromList(okm.sublist(32, 48));
      final decrypted = _aesCbcDecrypt(payload, key, iv);
      return utf8.decode(_unrotateAndXor(decrypted, rotateRight: true));
    } catch (_) {
      return null;
    }
  }

  static String? _decryptFallback(String value) {
    try {
      final data = _decodeBase64Url(value);
      if (data.length < 5) return null;
      final saltLength = data[4] & 0xff;
      if (data.length < saltLength + 5) return null;
      final ciphertextEnd = data.length - saltLength;
      final salt = Uint8List.fromList(data.sublist(ciphertextEnd));
      final ciphertext = Uint8List.fromList(data.sublist(5, ciphertextEnd));
      if (ciphertext.isEmpty || ciphertext.length % 16 != 0) return null;

      final info = Uint8List.fromList([...salt, ..._ctxHash]);
      final t1 = Hmac(sha256, _prk).convert([...info, 1]).bytes;
      final t2 = Hmac(sha256, _prk).convert([...t1, ...info, 2]).bytes;
      final decrypted = _aesCbcDecrypt(
        ciphertext,
        Uint8List.fromList(t1),
        Uint8List.fromList(t2.sublist(0, 16)),
      );
      return utf8.decode(_unrotateAndXor(decrypted, rotateRight: false));
    } catch (_) {
      return null;
    }
  }

  static String? _decryptFallback2(String value) {
    try {
      final decrypted = _aesCbcDecrypt(
        base64Decode(value),
        _legacyAes.key,
        _legacyAes.iv,
      );
      return utf8.decode(decrypted);
    } catch (_) {
      return null;
    }
  }

  static Uint8List _hkdfLike(Uint8List key, Uint8List info, int length) {
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

  static Uint8List _unrotateAndXor(
    Uint8List data, {
    required bool rotateRight,
  }) {
    final output = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      final byte = data[i] & 0xff;
      final rotated = rotateRight
          ? (((byte >> 3) | (byte << 5)) & 0xff)
          : (((byte << 5) & 0xff) | (byte >> 3));
      output[i] = rotated ^ (_ctxHash[i % _ctxHash.length] & 0xff);
    }
    return output;
  }

  static Uint8List _aesCbcDecrypt(
    Uint8List ciphertext,
    Uint8List key,
    Uint8List iv,
  ) {
    final cipher =
        PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
          ..init(
            false,
            PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(
              ParametersWithIV<KeyParameter>(KeyParameter(key), iv),
              null,
            ),
          );
    return cipher.process(ciphertext);
  }

  static Uint8List _decodeBase64Url(String value) {
    final standard = value.replaceAll('-', '+').replaceAll('_', '/');
    return base64Decode(base64.normalize(standard));
  }

  static ({Uint8List key, Uint8List iv}) _generateAesKeyIv(String value) {
    final data = utf8.encode(value);
    final n = data.length;
    var u = _u32(0x811c9dc5);
    for (final byte in data) {
      u = _u32(((u ^ (byte & 0xff)) * 0x01000193));
    }

    final key = Uint8List(16);
    for (var i = 0; i < key.length; i++) {
      final byte = data[i % n] & 0xff;
      u = _u32((31 * u) + (i ^ byte));
      key[i] = _charset[u % _charset.length];
    }

    u = _u32(0x811c832a);
    for (final byte in data) {
      u = _u32(((u ^ (byte & 0xff)) * 0x01000193));
    }

    final iv = Uint8List(16);
    var acc = 0;
    for (var idx = 0; idx != 48; idx += 3) {
      final byte = data[idx % n] & 0xff;
      u = _u32((29 * u) + (acc ^ byte));
      iv[idx ~/ 3] = _charset[u % _charset.length];
      acc = _u32(acc + 7);
    }

    return (key: key, iv: iv);
  }

  static int _u32(int value) => value & 0xffffffff;

  static Uint8List _hex(String hex) {
    final output = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      output[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return output;
  }
}

StreamResult _result(
  Map<String, dynamic> payload,
  String url, {
  String provider = 'TamilUltra',
  Map<String, String> headers = const {},
}) {
  final name = payload['name']?.toString();
  return StreamResult(
    url: url,
    quality: 'auto',
    provider: provider,
    serverName: name,
    isM3U8: url.toLowerCase().contains('.m3u8'),
    headers: headers,
  );
}

String _inferTamilUltraGroup(String name, String block) {
  final lower = '$name $block'.toLowerCase();
  if (lower.contains('sports') || lower.contains('genre_sports')) {
    return 'Sports';
  }
  if (lower.contains('kids')) return 'Tamil Kids';
  if (lower.contains('music')) return 'Tamil Music';
  if (lower.contains('news')) return 'Tamil News';
  if (lower.contains('movies')) return 'Tamil Movies';
  if (lower.contains('infotainment')) return 'Tamil Infotainment';
  return 'Tamil Entertainment';
}

String _cleanText(String value) {
  return _htmlDecode(
    value,
  ).replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _htmlDecode(String value) {
  return value
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#039;', "'")
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>');
}

String _stableId(String value) {
  final encoded = base64Url.encode(utf8.encode(value)).replaceAll('=', '');
  return encoded.length <= 16 ? encoded : encoded.substring(0, 16);
}

class _Anchor {
  const _Anchor({required this.url, required this.text});

  final String url;
  final String text;
}
