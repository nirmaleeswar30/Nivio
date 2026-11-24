import 'extension_repository.dart';

/// Nuvio JavaScript providers offered by default for movies and TV shows.
abstract final class NuvioDirectSources {
  static final _repository = ExtensionRepo(
    url: Uri.parse(
      'https://raw.githubusercontent.com/NuvioPlugin/All-in-One-Nuvio/'
      '3f09a6ff4360498895e622877af7a32212f75038/manifest.json',
    ),
    name: 'Built-in source',
    format: ExtensionFormat.javascript,
    entries: const [],
    enabledIds: const {},
  );

  static final _byId = {
    '4khdhub': _provider(
      '4khdhub',
      '4KHDHub',
      '1.0.3',
      'b15a2919b7d776febed7c9ad254f96a6216c977be351b8133835ca4f9a1ec215',
    ),
    'desiflix': _provider(
      'desiflix',
      'DesiFlix',
      '1.0.0',
      '89d80b0ac5aac7e946680f35f3fa7ba4859e2a9e9ab42ef8a811b51518e63cac',
    ),
    'moviesdrive': _provider(
      'moviesdrive',
      'MoviesDrive',
      '3.0.1',
      'd0e4e1b65490f2f3111d0f57253a746bcd4d4b0fd21ca5f1531463381518fdb4',
    ),
  };

  static Iterable<String> get names =>
      _byId.values.map((source) => source.name);

  static ExtensionProvider? forName(String name) =>
      _byId.values.where((source) => source.name == name).firstOrNull;

  /// Identifies the same source installed from one of the two tested repos.
  static String? replacementId(String sourceId) {
    final separator = sourceId.lastIndexOf('#');
    if (separator < 0) return null;
    final provider = _byId[sourceId.substring(separator + 1).toLowerCase()];
    if (provider == null) return null;
    final url = Uri.tryParse(sourceId.substring(0, separator));
    if (url == null || url.host != 'raw.githubusercontent.com') return null;
    final path = url.path.toLowerCase();
    if (!path.endsWith('/manifest.json')) return null;
    final isKnownRepository =
        path.startsWith('/yoruix/nuvio-providers/') ||
        path.startsWith('/d3adlyrocket/all-in-one-nuvio/') ||
        path.startsWith('/nuvioplugin/all-in-one-nuvio/');
    return isKnownRepository ? provider.sourceId : null;
  }

  static ExtensionProvider _provider(
    String id,
    String name,
    String version,
    String sha256,
  ) => ExtensionProvider(_repository, {
    'id': id,
    'name': name,
    'version': version,
    'filename': 'providers/$id.js',
    'fileHash': 'sha256-$sha256',
    'supportedTypes': const ['movie', 'tv'],
  }, builtIn: true);
}
