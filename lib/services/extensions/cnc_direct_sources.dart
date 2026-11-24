import 'dart:io';

import 'extension_repository.dart';

typedef _CncPackage = ({String name, int version, String sha256});

/// Built-in Android direct sources backed by CNC Verse's published packages.
class CncDirectSource {
  const CncDirectSource._(
    this.name,
    this._package, {
    String? registeredName,
    this.isAnime = false,
  }) : _registeredName = registeredName;

  final String name;
  final _CncPackage _package;
  final String? _registeredName;
  final bool isAnime;

  String get registeredName => _registeredName ?? name;
  String get sha256 => _package.sha256;
  bool get _sharedPackage => _package == _desktop || _package == _mobile;
  List<String> get packageProviderNames => [
    for (final source in _sources)
      if (source._package == _package) source.registeredName,
  ];

  static final _repository = ExtensionRepo(
    url: Uri.parse(
      'https://raw.githubusercontent.com/NivinCNC/CNCVerse-Cloud-Stream-Extension/'
      '586bd5d3c7cc2bd0c5f62ccd167153c767d2dacb/plugins.json',
    ),
    name: 'Built-in source',
    format: ExtensionFormat.cloudstream,
    entries: const [],
    enabledIds: const {},
  );

  static const _desktop = (
    name: 'CNC Verse',
    version: 116,
    sha256: '66278a65fac657e57c11d37121ac448f0276f850d80dd4dabf471eb4e0f330cd',
  );
  static const _mobile = (
    name: 'CNC Verse Mobile',
    version: 14,
    sha256: '92757725aea5ea0c38ff6df7b0122ec407a1cbc7a2d31eee71c6eadadd62b5f5',
  );

  static const _sources = [
    CncDirectSource._('CastleTV', (
      name: 'CastleTvProvider',
      version: 48,
      sha256:
          'c73c67b7443f3264cf9ee4bce79091e25e222362bbe15fe42ec6aed9f388fdf7',
    ), registeredName: 'Castle TV'),
    CncDirectSource._('MovieBox', (
      name: 'MovieBoxProvider',
      version: 55,
      sha256:
          '1c72d18e3d5cb85a5aec422096cc7511ea4767636c3ece1870ac68ae4f13846a',
    )),
    CncDirectSource._('MovieBox IN', (
      name: 'MovieBoxProviderIN',
      version: 57,
      sha256:
          '4e620c234f7df0d2da70629c82dfad9353a374e65f54dd4357e457b8decf9a7e',
    ), registeredName: 'MovieBoxIN'),
    CncDirectSource._('CineTv', (
      name: 'CineTvProvider',
      version: 37,
      sha256:
          '13780c3526a4805a7e28eb8aa219f0baf3d12fca47ddb0d5c2d5e94a5b36e741',
    )),
    CncDirectSource._('Netflix', _desktop),
    CncDirectSource._('NetflixM', _mobile),
    CncDirectSource._('Prime Video', _desktop),
    CncDirectSource._('PrimeVideoM', _mobile),
    CncDirectSource._('Hotstar', _desktop),
    CncDirectSource._('HotstarM', _mobile),
    CncDirectSource._('Disney', _desktop),
    CncDirectSource._('DisneyM', _mobile),
    CncDirectSource._('Marvel', _desktop),
    CncDirectSource._('MarvelM', _mobile),
    CncDirectSource._('Star Wars', _desktop),
    CncDirectSource._('Star WarsM', _mobile),
    CncDirectSource._('Pixar', _desktop),
    CncDirectSource._('PixarM', _mobile),
    CncDirectSource._('AniKoto', (
      name: 'AniKoto',
      version: 12,
      sha256:
          '5ce4df1afde0bff6ebb41926c9ef1b70293117d1b50e9045315ef23d2cfebc03',
    ), isAnime: true),
  ];

  static Iterable<CncDirectSource> forCategory({required bool isAnime}) =>
      Platform.isAndroid
      ? _sources.where((source) => source.isAnime == isAnime)
      : const [];

  static CncDirectSource? forName(String name, {required bool isAnime}) =>
      forCategory(
        isAnime: isAnime,
      ).where((source) => source.name == name).firstOrNull;

  static CncDirectSource? forPackage(ExtensionProvider provider) {
    if (!Platform.isAndroid ||
        provider.repository.format != ExtensionFormat.cloudstream) {
      return null;
    }
    final location = Uri.tryParse(provider.filename);
    final url = location == null
        ? null
        : provider.repository.url.resolveUri(location);
    final path = url?.pathSegments ?? const [];
    final fromCnc =
        url?.host == _repository.url.host &&
        path.length >= 4 &&
        path[0] == _repository.url.pathSegments[0] &&
        path[1] == _repository.url.pathSegments[1];
    return _sources.where((source) {
      return provider.contentHash?.toLowerCase() == 'sha256-${source.sha256}' ||
          (fromCnc && path.last == '${source._package.name}.cs3');
    }).firstOrNull;
  }

  static bool replacesPackage(ExtensionProvider provider) {
    final source = forPackage(provider);
    if (source == null) return false;
    return !source._sharedPackage ||
        provider.contentHash?.toLowerCase() == 'sha256-${source.sha256}';
  }

  ExtensionProvider get provider => ExtensionProvider(
    _repository,
    {
      'internalName': _package.name,
      'name': name,
      'url': Uri.encodeComponent('${_package.name}.cs3'),
      'version': _package.version,
      'fileHash': 'sha256-$sha256',
      'tvTypes': isAnime
          ? const ['Anime', 'AnimeMovie', 'OVA']
          : const ['Movie', 'TvSeries'],
    },
    builtIn: true,
    nativeProviderName: registeredName,
  );
}
