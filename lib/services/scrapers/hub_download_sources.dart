import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:nivio/models/search_result.dart';
import 'package:nivio/models/stream_size.dart';
import 'package:nivio/services/public_web_client.dart';
import 'package:nivio/services/tmdb_service.dart';

typedef _Page = ({Uri uri, String body, Map<String, String> headers});
typedef _Release = ({String title, int? bytes, int? height});

/// HTML and catalog lookup for the 4KHDHub and MoviesDrive built-ins.
class HubDownloadSources {
  HubDownloadSources({TmdbService? tmdb, http.Client? client})
    : _tmdb = tmdb,
      _client = client ?? IOClient(publicWebHttpClient()),
      _ownsClient = client == null;

  final TmdbService? _tmdb;
  final http.Client _client;
  final bool _ownsClient;

  static final _domains = Uri.https(
    'raw.githubusercontent.com',
    '/phisher98/TVVVV/refs/heads/main/domains.json',
  );
  static final _hubDefault = Uri.https('4khdhub.click');
  static final _driveDefault = Uri.https('new4.moviesdrive.christmas');
  static final _video = RegExp(
    r'\.(?:m3u8|mpd|mp4|mkv)$',
    caseSensitive: false,
  );
  static final _height = RegExp(r'(\d{3,4})p\b', caseSensitive: false);
  static final _uhd = RegExp(r'\b(?:4k|uhd)\b', caseSensitive: false);
  static final _size = RegExp(
    r'\b\d+(?:[.,]\d+)?\s*[GM]I?B\b',
    caseSensitive: false,
  );
  static final _cloudRedirect = RegExp(r'''var\s+url\s*=\s*['"]([^'"]+)['"]''');
  static final _driveMirror = RegExp(
    'hubcloud|gdflix|gdlink',
    caseSensitive: false,
  );

  void dispose() {
    if (_ownsClient) _client.close();
  }

  Future<List<Map<String, dynamic>>> fetch4KHDHub(
    SearchResult media, {
    required int season,
    required int episode,
  }) async {
    if (media.mediaType != 'movie' && media.mediaType != 'tv') return [];
    final movie = media.mediaType == 'movie';
    final details = await _details(media);
    final title = details.title ?? details.name ?? '';
    final year = int.tryParse(
      (details.releaseDate ?? details.firstAirDate ?? '').split('-').first,
    );
    if (title.isEmpty || year == null) return [];
    final domain = await _domain('4khdhub', _hubDefault);
    final search = await _get(
      domain.replace(queryParameters: {'s': '$title $year'}),
    );
    if (search == null) return [];

    Uri? content;
    for (final card
        in html.parse(search.body).querySelectorAll('.movie-card')) {
      final format = movie ? 'Movies' : 'Series';
      final matchesFormat = card
          .querySelectorAll('.movie-card-format')
          .any((badge) => badge.text.contains(format));
      final date = card.querySelector('.movie-card-meta')?.text.trim() ?? '';
      final candidateYear = int.tryParse(
        RegExp(r'^\d{4}').stringMatch(date) ?? '',
      );
      final caption = card
          .querySelector('.movie-card-title')
          ?.text
          .replaceAll(RegExp(r'\[.*?\]'), '')
          .trim();
      if (matchesFormat &&
          candidateYear != null &&
          (candidateYear - year).abs() <= 1 &&
          caption != null &&
          _sameHubTitle(title, caption)) {
        content = _url(search.uri, card.attributes['href']);
        if (content != null) break;
      }
    }
    if (content == null) return [];
    final page = await _get(content);
    if (page == null) return [];
    final doc = html.parse(page.body);
    final seasonTag = 'S${season.toString().padLeft(2, '0')}';
    final episodeTag = 'Episode-${episode.toString().padLeft(2, '0')}';
    final releases = movie
        ? doc.querySelectorAll('.download-item')
        : [
            for (final item in doc.querySelectorAll('.episode-item'))
              if (item
                      .querySelector('.episode-title')
                      ?.text
                      .contains(seasonTag) ==
                  true)
                ...item
                    .querySelectorAll('.episode-download-item')
                    .where((element) => element.text.contains(episodeTag)),
          ];
    final result = await Future.wait(
      releases.take(32).map((element) => _hubRelease(page.uri, element, title)),
    );
    return result.expand((group) => group).take(100).toList();
  }

  Future<List<Map<String, dynamic>>> fetchMoviesDrive(
    SearchResult media, {
    required int season,
    required int episode,
  }) async {
    if (media.mediaType != 'movie' && media.mediaType != 'tv') return [];
    final movie = media.mediaType == 'movie';
    final details = await _details(media);
    final title = details.title ?? details.name ?? '';
    final titleKey = _normalize(title);
    if (titleKey.isEmpty) return [];
    final imdb = await _imdb(media);
    final domain = await _domain('moviesdrive', _driveDefault);
    final seasonTag = RegExp(
      r'\b(?:season\s*|s)0?' + '$season' + r'\b',
      caseSensitive: false,
    );
    Uri? content;
    for (final query in {if (imdb != null) imdb, title}) {
      final search = await _get(
        domain
            .resolve('/search.php')
            .replace(queryParameters: {'q': query, 'page': '1'}),
      );
      final hits = search == null ? null : _json(search.body)['hits'];
      if (hits is! List) continue;
      Uri? titleMatch;
      for (final hit in hits.whereType<Map>()) {
        final doc = hit['document'];
        if (doc is! Map) continue;
        final uri = _url(domain, doc['permalink']?.toString());
        if (uri == null) continue;
        final name = doc['post_title']?.toString() ?? '';
        if (movie && imdb != null && doc['imdb_id'] == imdb) {
          content = uri;
          break;
        }
        final matches =
            _normalize(name).contains(titleKey) ||
            _normalize(uri.path).contains(titleKey);
        if (matches && (movie || seasonTag.hasMatch('$name ${uri.path}'))) {
          titleMatch ??= uri;
        }
      }
      content ??= titleMatch;
      if (content != null) break;
    }
    if (content == null) return [];
    final page = await _get(content);
    if (page == null) return [];
    final doc = html.parse(page.body);
    final pages = <Uri, Uri>{};
    if (movie) {
      for (final link in _anchors(
        page.uri,
        doc.querySelectorAll('h5 a[href]'),
      )) {
        pages[link] = page.uri;
      }
    } else {
      for (final heading in doc.querySelectorAll('h5')) {
        if (!seasonTag.hasMatch(heading.text)) continue;
        final a =
            heading.nextElementSibling?.querySelector('a[href]') ??
            heading.querySelector('a[href]');
        final seasonPage = _url(page.uri, a?.attributes['href']);
        if (seasonPage == null) continue;
        final episodes = await _get(seasonPage);
        if (episodes == null) continue;
        for (final link in _episodeLinks(episodes, season, episode)) {
          pages[link] = episodes.uri;
        }
      }
    }
    final label = movie
        ? title
        : '$title S${season.toString().padLeft(2, '0')}E${episode.toString().padLeft(2, '0')}';
    final output = <Map<String, dynamic>>[];
    final seen = <Uri>{};
    for (final entry in pages.entries) {
      for (final mirror in await _driveMirrors(entry.key)) {
        if (!seen.add(mirror)) continue;
        if (mirror.host.contains('hubcloud')) {
          output.addAll(
            await _cloud(
              mirror,
              referer: entry.value,
              release: (title: label, bytes: null, height: null),
              moviesDrive: true,
            ),
          );
        } else {
          for (final file in await _gdflixFiles(mirror)) {
            output.add(
              _stream(file, 'GDFlix', '$label - GDFlix [1080p]', 1080, null),
            );
          }
        }
        if (output.length >= 100) return output.take(100).toList();
      }
    }
    return output;
  }

  Future<SearchResult> _details(SearchResult media) async {
    final tmdb = _tmdb;
    if (tmdb == null) return media;
    try {
      return media.mediaType == 'movie'
          ? await tmdb.getMovieDetails(media.id)
          : await tmdb.getTVShowDetails(media.id);
    } catch (_) {
      return media;
    }
  }

  Future<String?> _imdb(SearchResult media) async {
    try {
      return await _tmdb?.getImdbId(
        tmdbId: media.id,
        isMovie: media.mediaType == 'movie',
      );
    } catch (_) {
      return null;
    }
  }

  Future<Uri> _domain(String key, Uri fallback) async {
    final page = await _get(_domains);
    final value = page == null ? null : _json(page.body)[key];
    if (value is! String) return fallback;
    final uri = Uri.tryParse(value);
    return uri != null && isPublicWebUrl(uri) ? uri : fallback;
  }

  Future<List<Map<String, dynamic>>> _hubRelease(
    Uri base,
    Element element,
    String title,
  ) async {
    final name = element
        .querySelector('.file-title, .episode-file-title')
        ?.text
        .trim();
    final release = (
      title: name == null || name.isEmpty ? title : name,
      bytes: StreamSize.parse(_size.stringMatch(element.innerHtml)),
      height: _resolution(element.innerHtml),
    );
    final anchors = element.querySelectorAll('a[href]');
    final hb = _anchors(base, anchors).where(_isHb).firstOrNull;
    if (hb != null) return _hubLanding(hb, release, {});
    for (final service in ['hubcloud', 'hubdrive']) {
      final link = _namedAnchor(base, anchors, service);
      if (link != null) {
        return _hubLanding(link, release, {}, hint: service);
      }
    }
    return [];
  }

  Future<List<Map<String, dynamic>>> _hubLanding(
    Uri link,
    _Release release,
    Set<Uri> visited, {
    int depth = 0,
    String? hint,
  }) async {
    if (depth > 3 || !visited.add(link)) return [];
    if (_video.hasMatch(link.path)) {
      return [
        _stream(
          link,
          'Hblinks Direct',
          release.title,
          release.height,
          release.bytes,
          bingeGroup: '4khdhub-Hblinks Direct',
        ),
      ];
    }
    final host = link.host;
    if (host.contains('hubcloud') || hint == 'hubcloud') {
      return _cloud(await _redirectFromPage(link), release: release);
    }
    final page = await _get(link, referer: link);
    if (page == null) return [];
    final jump = _redirectDestination(page);
    if (jump != null && jump != link) {
      return _hubLanding(jump, release, visited, depth: depth + 1, hint: hint);
    }
    final doc = html.parse(page.body);
    if (host.contains('hubdrive') || hint == 'hubdrive') {
      final cloud = _namedAnchor(
        page.uri,
        doc.querySelectorAll('a[href]'),
        'hubcloud',
      );
      return cloud == null
          ? []
          : _hubLanding(cloud, release, visited, depth: depth + 1);
    }
    if (!_isHb(link)) return [];
    final output = <Map<String, dynamic>>[];
    for (final next in _anchors(
      page.uri,
      doc.querySelectorAll('h3 a[href], h5 a[href], div.entry-content a[href]'),
    ).toSet().take(32)) {
      output.addAll(
        await _hubLanding(next, release, visited, depth: depth + 1),
      );
    }
    return output;
  }

  Future<Uri> _redirectFromPage(Uri uri) async {
    if (uri.host.contains('hubcloud') || uri.host.contains('hubdrive'))
      return uri;
    final page = await _get(uri);
    return (page == null ? null : _redirectDestination(page)) ?? uri;
  }

  // Redirect pages publish their destination in an encoded JSON field.
  static Uri? _redirectDestination(_Page page) {
    final data = RegExp(r"'o','([^']+)'").firstMatch(page.body)?.group(1);
    if (data == null) return null;
    try {
      String decode(String value) =>
          utf8.decode(base64.decode(base64.normalize(value)));
      final plain = decode(decode(data));
      final rotated = String.fromCharCodes(
        plain.codeUnits.map((unit) {
          if (unit >= 65 && unit <= 90) return 65 + (unit - 65 + 13) % 26;
          if (unit >= 97 && unit <= 122) return 97 + (unit - 97 + 13) % 26;
          return unit;
        }),
      );
      final target = _json(decode(rotated))['o'];
      return target is String ? _url(page.uri, decode(target)) : null;
    } on FormatException {
      return null;
    }
  }

  Future<Set<Uri>> _driveMirrors(Uri link) async {
    final recover = link.path.endsWith('/search-recover.php');
    if (!recover &&
        _driveMirror.hasMatch(link.host) &&
        (link.path.startsWith('/drive/') || link.path.startsWith('/file/'))) {
      return {link};
    }
    final page = await _get(link);
    if (page == null) return {};
    if (recover) {
      final query = RegExp(
        r'''const\s+Q_INITIAL\s*=\s*['"]([^'"]+)['"]''',
      ).firstMatch(page.body)?.group(1);
      final ticket = RegExp(
        r'''const\s+FROM_AC_TOKEN\s*=\s*['"]([^'"]+)['"]''',
      ).firstMatch(page.body)?.group(1);
      if (query != null && ticket != null) {
        final response = await _get(
          page.uri.replace(
            queryParameters: {
              'api': 'search',
              'q': query,
              'page': '1',
              'from_ac': ticket,
            },
          ),
          referer: page.uri,
        );
        final hits = response == null ? null : _json(response.body)['hits'];
        if (hits is List) {
          return {
            for (final hit in hits.whereType<Map>())
              if (_url(page.uri, hit['url']?.toString()) case final uri?
                  when _driveMirror.hasMatch(uri.host))
                uri,
          };
        }
      }
    }
    return _anchors(
      page.uri,
      html.parse(page.body).querySelectorAll('a[href]'),
    ).where((uri) => _driveMirror.hasMatch(uri.host)).toSet();
  }

  static Iterable<Uri> _episodeLinks(
    _Page data,
    int season,
    int episode,
  ) sync* {
    final episodeTag = RegExp(
      r'\b(?:(?:ep|episode|e)\s*0?' +
          '$episode' +
          r'|s0?' +
          '$season' +
          r'e0?' +
          '$episode' +
          r')\b',
      caseSensitive: false,
    );
    final anyEpisode = RegExp(
      r'^\s*(?:ep\d+|episode\s*\d+|s\d+e\d+)',
      caseSensitive: false,
    );
    for (final heading in html.parse(data.body).querySelectorAll('h5')) {
      if (!episodeTag.hasMatch(heading.text)) continue;
      for (
        var sibling = heading.nextElementSibling;
        sibling != null && !anyEpisode.hasMatch(sibling.text);
        sibling = sibling.nextElementSibling
      ) {
        yield* _anchors(data.uri, sibling.querySelectorAll('a[href]'));
      }
    }
  }

  Future<List<Map<String, dynamic>>> _cloud(
    Uri uri, {
    Uri? referer,
    required _Release release,
    bool moviesDrive = false,
  }) async {
    final landing = await _get(uri, referer: referer ?? uri);
    if (landing == null) return [];
    final landingDoc = html.parse(landing.body);
    final redirect = _cloudRedirect.firstMatch(landing.body)?.group(1);
    final href = moviesDrive
        ? landingDoc
                  .querySelector('a[href*="hubcloud.php"]')
                  ?.attributes['href'] ??
              landingDoc.querySelector('a#download')?.attributes['href'] ??
              redirect
        : redirect;
    final next = _url(landing.uri, href);
    final page =
        next == null ||
            next == landing.uri ||
            landing.uri.path.contains('hubcloud.php')
        ? landing
        : await _get(next, referer: landing.uri);
    if (page == null) return [];
    final doc = page == landing ? landingDoc : html.parse(page.body);
    final bytes =
        StreamSize.parse(doc.querySelector('#size')?.text.trim()) ??
        release.bytes;
    final height = moviesDrive
        ? _resolution(doc.querySelector('.card-header')?.text ?? '') ?? 1080
        : release.height;
    final fileTitle = doc.querySelector('title')?.text.trim() ?? '';
    final title = fileTitle.isEmpty ? release.title : fileTitle;
    final pixelDestination = moviesDrive
        ? RegExp(
            r'''var\s+pxl\s*=\s*['"]([^'"]+)['"]''',
          ).firstMatch(page.body)?.group(1)
        : null;
    final output = <Map<String, dynamic>>[];
    for (final a in doc.querySelectorAll('a[href]')) {
      final raw = a.attributes['href']!;
      if (const [
        'tinyurl',
        'telegram',
        'hubcloud.cx/tg',
        'hubcloud.foo/tg',
      ].any(raw.contains))
        continue;
      var link = _url(
        page.uri,
        raw.contains('negn6f') && pixelDestination != null
            ? pixelDestination
            : raw,
      );
      if (link == null) continue;
      final text = a.text.toLowerCase();
      final host = link.host;
      String? name;
      if (text.contains('fsl')) {
        name = moviesDrive
            ? (text.contains('v2')
                  ? 'HubCloud - FSLv2'
                  : 'HubCloud - FSL Server')
            : 'FSL';
      } else if (moviesDrive &&
          (text.contains('instant') ||
              text.contains('download file') ||
              text.contains('10gbps'))) {
        name = 'HubCloud - Instant';
        if (!link.queryParameters.containsKey('link')) {
          link =
              (await _get(link, referer: page.uri, readBody: false))?.uri ??
              link;
        }
        link = _url(link, link.queryParameters['link']) ?? link;
      } else if (moviesDrive &&
          (text.contains('pixel') || host.contains('pixeldrain'))) {
        name = 'HubCloud - Pixeldrain';
        if (link.pathSegments.length >= 2 && link.pathSegments.first == 'u') {
          link = Uri.https(
            'pixeldrain.dev',
            '/api/file/${link.pathSegments[1]}',
            {'download': ''},
          );
        }
      } else if (!moviesDrive &&
          (text.contains('10gbps') ||
              text.contains('pixelserver') ||
              host.contains('hubcloud.cx'))) {
        name = 'HubCloud 10Gbps';
        // These answer with a redirect chain ending on a page whose `link`
        // parameter is the file; the button URL itself is an HTML page.
        link = await _linkParameter(link, referer: page.uri);
      } else if (text.contains('download file') || host.endsWith('.r2.dev')) {
        name = 'Direct R2';
      } else if (text.contains('zipdisk')) {
        // A ZIP archive of the video: it can't be played or saved as one.
        continue;
      } else if (host.endsWith('.workers.dev')) {
        name = 'ZipDisk Server';
      } else if (moviesDrive && text.contains('s3 server')) {
        name = 'HubCloud - S3';
      } else if (moviesDrive && text.contains('mega server')) {
        name = 'HubCloud - Mega';
      } else if (moviesDrive &&
          (text.contains('buzz') || text.contains('fuckingfast'))) {
        name = 'HubCloud - BuzzServer';
        link = await _buzz(link);
      }
      if (name == null || link == null) continue;
      final label = moviesDrive
          ? '${release.title} - $name [${height}p]'
          : title;
      output.add(
        _stream(
          link,
          name,
          label,
          height,
          bytes,
          bingeGroup: moviesDrive ? null : '4khdhub-$name',
        ),
      );
    }
    return output;
  }

  /// Follows [link]'s redirects to the URL carrying a `link` parameter and
  /// returns that parameter, or null when there is none.
  Future<Uri?> _linkParameter(Uri link, {Uri? referer}) async {
    var current = link;
    if (!current.queryParameters.containsKey('link')) {
      final landed = await _get(current, referer: referer, readBody: false);
      if (landed == null) return null;
      current = landed.uri;
    }
    final target = _url(current, current.queryParameters['link']);
    return target != null && isPublicWebUrl(target) ? target : null;
  }

  /// File links on a GDFlix page. Its own buttons only generate links in the
  /// browser, so a mirror without a plain file link is skipped.
  Future<List<Uri>> _gdflixFiles(Uri mirror) async {
    final page = await _get(mirror);
    if (page == null) return const [];
    return _anchors(page.uri, html.parse(page.body).querySelectorAll('a[href]'))
        .where(
          (uri) =>
              uri.host.endsWith('.r2.dev') ||
              (uri.host.contains('pixeldrain') &&
                  uri.path.startsWith('/api/file/')) ||
              _video.hasMatch(uri.path),
        )
        .toSet()
        .toList();
  }

  Future<Uri?> _buzz(Uri uri) async {
    final page = await _get(uri);
    if (page == null) return null;
    final href = RegExp(
      r'''copyDownloadLink\(['"]([^'"]+)['"]\)''',
    ).firstMatch(page.body)?.group(1)?.replaceAll(r'\/', '/');
    final target =
        _url(page.uri, href) ??
        page.uri.replace(
          path: page.uri.path.endsWith('/download')
              ? page.uri.path
              : '${page.uri.path}/download',
        );
    final response = await _get(
      target,
      referer: page.uri,
      readBody: false,
      followRedirects: false,
      extraHeaders: const {'HX-Request': 'true'},
    );
    return _url(
      target,
      response?.headers['hx-redirect'] ?? response?.headers['location'],
    );
  }

  static Map<String, dynamic> _stream(
    Uri link,
    String name,
    String title,
    int? height,
    int? bytes, {
    String? bingeGroup,
  }) => {
    'url': link.toString(),
    'name': name,
    'title': title,
    if (height != null) 'quality': '${height}p',
    if (bytes != null) 'sizeBytes': bytes,
    if (bingeGroup != null) 'bingeGroup': bingeGroup,
  };

  Future<_Page?> _get(
    Uri url, {
    Uri? referer,
    bool readBody = true,
    bool followRedirects = true,
    Map<String, String> extraHeaders = const {},
  }) async {
    try {
      var current = url;
      for (var hop = 0; hop <= 5; hop++) {
        if (!isPublicWebUrl(current)) return null;
        final request = http.Request('GET', current)..followRedirects = false;
        request.headers.addAll({
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/144.0.0.0 Safari/537.36',
          'Accept': 'text/html,application/json;q=0.9,*/*;q=0.8',
          if (referer != null) 'Referer': referer.toString(),
          ...extraHeaders,
        });
        const limit = Duration(seconds: 8);
        final response = await _client.send(request).timeout(limit);
        final redirect = const {
          301,
          302,
          303,
          307,
          308,
        }.contains(response.statusCode);
        if (redirect && followRedirects) {
          final next = _url(current, response.headers['location']);
          await response.stream.listen(null).cancel();
          if (next == null) return null;
          current = next;
          continue;
        }
        if (!readBody || response.statusCode != 200) {
          await response.stream.listen(null).cancel();
          final successful =
              response.statusCode >= 200 && response.statusCode < 300;
          return (!readBody && successful) || (redirect && !followRedirects)
              ? (uri: current, body: '', headers: response.headers)
              : null;
        }
        final body = BytesBuilder(copy: false);
        await for (final chunk in response.stream.timeout(limit)) {
          if (body.length + chunk.length > 5 * 1024 * 1024) return null;
          body.add(chunk);
        }
        return (
          uri: current,
          body: utf8.decode(body.takeBytes(), allowMalformed: true),
          headers: response.headers,
        );
      }
    } on TimeoutException {
      return null;
    } on IOException {
      return null;
    } on http.ClientException {
      return null;
    }
    return null;
  }

  static Uri? _url(Uri base, String? href) {
    if (href == null || href.trim().isEmpty) return null;
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return null;
    final resolved = base.resolveUri(uri);
    return isPublicWebUrl(resolved) ? resolved : null;
  }

  static Iterable<Uri> _anchors(Uri base, Iterable<Element> anchors) sync* {
    for (final a in anchors) {
      if (_url(base, a.attributes['href']) case final link?) yield link;
    }
  }

  static Uri? _namedAnchor(Uri base, Iterable<Element> anchors, String name) {
    for (final a in anchors) {
      final href = a.attributes['href'] ?? '';
      if (href.toLowerCase().contains(name) ||
          a.text.toLowerCase().contains(name)) {
        if (_url(base, href) case final link?) return link;
      }
    }
    return null;
  }

  static bool _isHb(Uri link) =>
      link.host.contains('hblinks') || link.host == 'hubstream.dad';

  static Map<String, dynamic> _json(String source) {
    try {
      final json = jsonDecode(source);
      return json is Map<String, dynamic> ? json : {};
    } on FormatException {
      return {};
    }
  }

  static int? _resolution(String value) =>
      int.tryParse(_height.firstMatch(value)?.group(1) ?? '') ??
      (_uhd.hasMatch(value) ? 2160 : null);

  static String _normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static bool _sameHubTitle(String expected, String candidate) {
    final left = expected.toLowerCase();
    final right = candidate.toLowerCase();
    if (left == right) return true;
    if ((left.length - right.length).abs() >= 5) return false;
    var row = List<int>.generate(right.length + 1, (index) => index);
    for (var i = 0; i < left.length; i++) {
      final next = [i + 1];
      for (var j = 0; j < right.length; j++) {
        final insertion = next[j] + 1;
        final deletion = row[j + 1] + 1;
        final substitution =
            row[j] + (left.codeUnitAt(i) == right.codeUnitAt(j) ? 0 : 1);
        next.add(
          [insertion, deletion, substitution].reduce((a, b) => a < b ? a : b),
        );
      }
      row = next;
    }
    return row.last < 5;
  }
}
