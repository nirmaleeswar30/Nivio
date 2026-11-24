import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path_provider/path_provider.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_anime_mapping.dart';

enum ExtensionFormat { javascript, cloudstream }

enum ExtensionAnimeId { aniList, tmdb }

final extensionRepositoryProvider = Provider(
  (ref) => ExtensionRepository(
    animeMappings: ExtensionAnimeMappings(
      cache: ref.watch(cacheServiceProvider),
      tmdb: ref.watch(tmdbServiceProvider),
    ),
  ),
);

class ExtensionProvider {
  const ExtensionProvider(
    this.repository,
    this.entry, {
    this.builtIn = false,
    this.nativeProviderName,
  });

  final ExtensionRepo repository;
  final Map<String, dynamic> entry;
  final bool builtIn;
  final String? nativeProviderName;

  String get id => '${repository.url}#${entry['id'] ?? entry['internalName']}';
  String get sourceId => builtIn ? 'builtin:$name' : id;
  String get name => entry['name'] as String;
  String get description => entry['description']?.toString() ?? '';
  String get version => entry['version']?.toString() ?? '';
  bool get enabled => builtIn || repository.enabledIds.contains(id);
  String get filename => (entry['filename'] ?? entry['url']) as String;
  String? get contentHash {
    final value = entry['fileHash'];
    return value is String ? value : null;
  }

  String get packageKey => sha256
      .convert(
        utf8.encode(
          [
            id,
            version,
            filename,
            if (contentHash != null) contentHash!,
          ].join('\n'),
        ),
      )
      .toString();

  Set<String> get nuvioTypes {
    final types = entry['supportedTypes'];
    return types is List
        ? types.map((type) => '$type'.toLowerCase()).toSet()
        : {'movie', 'tv'};
  }

  bool supports(String type) {
    if (repository.format == ExtensionFormat.cloudstream) {
      final types = (entry['tvTypes'] as List? ?? []).map(
        (t) => '$t'.toLowerCase(),
      );
      if (types.isEmpty || types.contains('all')) return true;
      const movieTypes = {'movie', 'animemovie', 'documentary', 'torrent'};
      const showTypes = {
        'tvseries',
        'anime',
        'ova',
        'cartoon',
        'asiandrama',
        'others',
      };
      return types.any(
        type == 'movie'
            ? movieTypes.contains
            : (value) =>
                  showTypes.contains(value) ||
                  (type == 'anime' && value == 'animemovie'),
      );
    }
    final platform = Platform.operatingSystem;
    final platforms = switch (entry['supportedPlatforms']) {
      final List values => values.map((p) => '$p'.toLowerCase()),
      _ => const <String>[],
    };
    final excluded = switch (entry['disabledPlatforms']) {
      final List values => values.map((p) => '$p'.toLowerCase()),
      _ => const <String>[],
    };
    if (excluded.contains(platform) ||
        (platforms.isNotEmpty && !platforms.contains(platform))) {
      return false;
    }
    final types = nuvioTypes;
    const tvTypes = {'tv', 'series', 'show', 'other'};
    if (type == 'anime')
      return types.contains('anime') ||
          types.contains('movie') ||
          types.any(tvTypes.contains);
    return type == 'tv' ? types.any(tvTypes.contains) : types.contains(type);
  }
}

class ExtensionRepo {
  ExtensionRepo({
    required this.url,
    required this.name,
    required this.format,
    required this.entries,
    required this.enabledIds,
  });

  factory ExtensionRepo.fromJson(Map<String, dynamic> json) => ExtensionRepo(
    url: Uri.parse(json['url'] as String),
    name: json['name'] as String,
    format: ExtensionFormat.values.byName(json['format'] as String),
    entries: (json['entries'] as List).cast<Map<String, dynamic>>(),
    enabledIds: (json['enabled'] as List).cast<String>().toSet(),
  );

  final Uri url;
  final String name;
  final ExtensionFormat format;
  final List<Map<String, dynamic>> entries;
  final Set<String> enabledIds;

  Iterable<ExtensionProvider> get providers =>
      entries.map((entry) => ExtensionProvider(this, entry));

  Map<String, dynamic> toJson() => {
    'url': url.toString(),
    'name': name,
    'format': format.name,
    'entries': entries,
    'enabled': enabledIds.toList(),
  };
}

class ExtensionRepository {
  ExtensionRepository({ExtensionAnimeMappings? animeMappings})
    : animeMappings = animeMappings ?? ExtensionAnimeMappings();

  final ExtensionAnimeMappings animeMappings;
  static const _repoKey = 'stream_extension_repositories';
  static const _limit = 8 * 1024 * 1024;
  final _packages = <String, Future<File>>{};

  String _animeRouteKey(
    ExtensionProvider provider,
    bool movie,
    ExtensionAnimeId idType,
  ) =>
      'extension_anime_route_${provider.packageKey}_${movie ? 'movie' : 'series'}_${idType.name}';

  Future<({String? aniList, String? tmdb})> animeRoutes(
    ExtensionProvider provider, {
    required bool movie,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return (
      aniList: prefs.getString(
        _animeRouteKey(provider, movie, ExtensionAnimeId.aniList),
      ),
      tmdb: prefs.getString(
        _animeRouteKey(provider, movie, ExtensionAnimeId.tmdb),
      ),
    );
  }

  Future<void> rememberAnimeRoute(
    ExtensionProvider provider,
    ExtensionAnimeId idType,
    String requestType, {
    required bool movie,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _animeRouteKey(provider, movie, idType);
    if (prefs.getString(key) != requestType)
      await prefs.setString(key, requestType);
  }

  Future<List<ExtensionRepo>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final decoded = jsonDecode(prefs.getString(_repoKey) ?? '[]') as List;
    return decoded
        .cast<Map<String, dynamic>>()
        .map(ExtensionRepo.fromJson)
        .toList();
  }

  Future<void> _save(List<ExtensionRepo> repositories) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(_repoKey, jsonEncode(repositories))) {
      throw const FileSystemException('Could not save extension settings.');
    }
  }

  Future<ExtensionRepo> add(String input) async {
    final uri = Uri.tryParse(
      input.trim().replaceFirst(
        RegExp('^cloudstreamrepo://', caseSensitive: false),
        'https://',
      ),
    );
    if (uri == null || !isExtensionWebUrl(uri)) {
      throw const FormatException(
        'Enter a repository URL beginning with https://.',
      );
    }
    final url = uri.path.toLowerCase().endsWith('.json')
        ? uri.removeFragment()
        : uri
              .replace(
                path:
                    '${uri.path.replaceFirst(RegExp(r'/$'), '')}/manifest.json',
              )
              .removeFragment();
    if ((await list()).any((repo) => repo.url == url)) {
      throw const FormatException('This repository is already installed.');
    }
    final repo = await _readManifest(url);
    final repositories = await list();
    final existing = repositories.where((item) => item.url == url).firstOrNull;
    if (existing != null) return existing;
    await _save([...repositories, repo]);
    return repo;
  }

  Future<void> refresh(ExtensionRepo repo) async {
    final updated = await _readManifest(repo.url);
    final repositories = await list();
    for (var index = 0; index < repositories.length; index++) {
      final existing = repositories[index];
      if (existing.url != repo.url) continue;
      if (existing.format == updated.format) {
        updated.enabledIds.addAll(
          updated.providers
              .where(
                (provider) =>
                    existing.enabledIds.contains(provider.id) &&
                    provider.entry['enabled'] != false &&
                    (updated.format != ExtensionFormat.cloudstream ||
                        provider.entry['status'] != 0),
              )
              .map((provider) => provider.id)
              .toList(),
        );
      }
      repositories[index] = updated;
      await _save(repositories);
      return;
    }
  }

  Future<void> setEnabled(ExtensionProvider provider, bool enabled) async {
    final repositories = await list();
    for (final repo in repositories) {
      if (repo.url != provider.repository.url) continue;
      if (enabled) {
        repo.enabledIds.add(provider.id);
      } else {
        repo.enabledIds.remove(provider.id);
      }
      await _save(repositories);
      return;
    }
  }

  Future<void> remove(ExtensionRepo repo) async {
    final repositories = await list();
    await _save(repositories.where((item) => item.url != repo.url).toList());
    for (final provider in repo.providers) {
      final file = await _packageFile(provider);
      if (await file.exists()) await file.delete();
    }
  }

  Future<ExtensionRepo> _readManifest(Uri url) async {
    final manifest = await _readJson(url);
    late final ExtensionFormat format;
    late final String name;
    late final List<dynamic> entries;
    if (manifest is Map && manifest['scrapers'] is List) {
      format = ExtensionFormat.javascript;
      entries = manifest['scrapers'] as List;
      name = manifest['name']?.toString() ?? url.host;
    } else if (manifest is List ||
        manifest is Map && manifest['pluginLists'] is List) {
      format = ExtensionFormat.cloudstream;
      name = manifest is Map
          ? manifest['name']?.toString() ?? url.host
          : url.host;
      if (manifest is List) {
        entries = manifest;
      } else {
        entries = [];
        for (final link
            in (manifest['pluginLists'] as List).whereType<String>().take(16)) {
          final listUrl = url.resolve(link);
          final list = await _readJson(listUrl);
          if (list is! List)
            throw const FormatException('Invalid Cloudstream extension list.');
          entries.addAll(
            list.whereType<Map<String, dynamic>>().map(
              (entry) => {
                ...entry,
                if (entry['url'] is String)
                  'url': listUrl.resolve(entry['url'] as String).toString(),
              },
            ),
          );
        }
      }
    } else {
      throw const FormatException(
        'This URL does not contain a Nuvio or Cloudstream repository.',
      );
    }
    final ids = <String>{};
    final valid = entries
        .whereType<Map<String, dynamic>>()
        .where((entry) {
          final id = format == ExtensionFormat.javascript
              ? entry['id']
              : entry['internalName'];
          final path = format == ExtensionFormat.javascript
              ? entry['filename']
              : entry['url'];
          return entry['name'] is String &&
              path is String &&
              path.isNotEmpty &&
              id is String &&
              id.isNotEmpty &&
              ids.add(id);
        })
        .take(500)
        .toList();
    if (valid.isEmpty)
      throw const FormatException(
        'This repository contains no compatible provider entries.',
      );
    return ExtensionRepo(
      url: url,
      name: name,
      format: format,
      entries: valid,
      enabledIds: {},
    );
  }

  Future<dynamic> _readJson(Uri url) async =>
      jsonDecode(utf8.decode(await _download(url)));

  Future<File> _packageFile(ExtensionProvider provider) async {
    final directory = await getApplicationSupportDirectory();
    final extension = provider.repository.format == ExtensionFormat.javascript
        ? 'js'
        : 'cs3';
    return File(
      '${directory.path}/extensions/${provider.packageKey}.$extension',
    );
  }

  Future<File> package(ExtensionProvider provider) {
    final key = provider.packageKey;
    return _packages.putIfAbsent(
      key,
      () => _install(provider).whenComplete(() {
        _packages.remove(key);
      }),
    );
  }

  Future<File> _install(ExtensionProvider provider) async {
    final file = await _packageFile(provider);
    if (await file.exists()) return file;
    final bytes = await _download(
      provider.repository.url.resolve(provider.filename),
    );
    final expected = provider.contentHash;
    if (expected != null &&
        expected.startsWith('sha256-') &&
        expected.toLowerCase() != 'sha256-${sha256.convert(bytes)}') {
      throw const FormatException(
        'The package does not match its repository checksum.',
      );
    }
    await file.parent.create(recursive: true);
    final staging = await file.parent.createTemp('install-');
    try {
      final pending = File('${staging.path}/package');
      await pending.writeAsBytes(bytes);
      return await pending.rename(file.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  Future<List<int>> _download(Uri initial) async {
    final client = IOClient(extensionHttpClient());
    var uri = initial;
    try {
      for (var redirects = 0; redirects <= 5; redirects++) {
        if (!isExtensionWebUrl(uri))
          throw const FormatException('Invalid extension URL.');
        final response = await client
            .send(http.Request('GET', uri)..followRedirects = false)
            .timeout(const Duration(seconds: 12));
        final redirect = response.headers['location'];
        if (redirect != null &&
            const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
          await response.stream.listen(null).cancel();
          uri = uri.resolve(redirect);
          continue;
        }
        if (response.statusCode != 200)
          throw HttpException(
            'Repository returned HTTP ${response.statusCode}.',
          );
        final bytes = <int>[];
        await for (final chunk in response.stream.timeout(
          const Duration(seconds: 12),
        )) {
          if (bytes.length + chunk.length > _limit)
            throw const FormatException('Extension file is too large.');
          bytes.addAll(chunk);
        }
        return bytes;
      }
      throw const FormatException('The repository redirected too many times.');
    } finally {
      client.close();
    }
  }
}

bool isExtensionWebUrl(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase().replaceFirst(RegExp(r'\.$'), '');
  if (uri.userInfo.isNotEmpty ||
      !host.contains('.') ||
      host.endsWith('.local') ||
      host.endsWith('.localhost') ||
      host.endsWith('.internal'))
    return false;
  final ip = InternetAddress.tryParse(host);
  return ip == null;
}

HttpClient extensionHttpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 8)
  ..findProxy = ((_) => 'DIRECT')
  ..connectionFactory = (uri, _, _) => _connectToProvider(uri);

Future<ConnectionTask<Socket>> _connectToProvider(Uri uri) async {
  if (!isExtensionWebUrl(uri)) {
    throw const SocketException('Invalid provider host.');
  }
  final addresses = await InternetAddress.lookup(
    uri.host,
  ).timeout(const Duration(seconds: 6));
  final eligible = addresses.where(_isPublicAddress).toList();
  if (eligible.isEmpty) {
    throw const SocketException('Provider must use a public Internet address.');
  }

  // Try both address families when available before trying another address
  // from the same family.
  final alternate = eligible.indexWhere((ip) => ip.type != eligible.first.type);
  if (alternate > 1) eligible.insert(1, eligible.removeAt(alternate));
  var cancelled = false;
  ConnectionTask<Socket>? pending;
  Socket? connected;

  Future<Socket> connect() async {
    for (final ip in eligible) {
      if (cancelled) break;
      try {
        pending = await Socket.startConnect(ip, uri.port);
        if (cancelled) {
          pending!.cancel();
          break;
        }
        final socket = connected = await pending!.socket.timeout(
          const Duration(seconds: 2),
        );
        if (cancelled) {
          socket.destroy();
          break;
        }
        if (uri.scheme != 'https') return socket;
        // HttpClient requires an already secured socket from a custom
        // factory. Keep the original hostname for certificate checks and SNI.
        return await SecureSocket.secure(
          socket,
          host: uri.host,
        ).timeout(const Duration(seconds: 3));
      } on IOException {
        pending?.cancel();
        connected?.destroy();
      } on TimeoutException {
        pending?.cancel();
      }
    }
    throw SocketException('Could not connect to ${uri.host}.');
  }

  return ConnectionTask.fromSocket(connect(), () {
    cancelled = true;
    pending?.cancel();
    connected?.destroy();
  });
}

bool _isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (bytes.length == 16) {
    // Global unicast. This also excludes IPv4-mapped private addresses.
    return bytes[0] & 0xe0 == 0x20 &&
        !(bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8);
  }
  final a = bytes[0], b = bytes[1], c = bytes[2];
  return a > 0 &&
      a < 224 &&
      a != 10 &&
      a != 127 &&
      !(a == 100 && b >= 64 && b < 128) &&
      !(a == 169 && b == 254) &&
      !(a == 172 && b >= 16 && b < 32) &&
      !(a == 192 && (b == 168 || b == 0 && (c == 0 || c == 2))) &&
      !(a == 198 && (b == 18 || b == 19 || b == 51 && c == 100)) &&
      !(a == 203 && b == 0 && c == 113);
}
