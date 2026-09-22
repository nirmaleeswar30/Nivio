import 'package:http/http.dart' as http;
import 'stremio_base_source.dart';

/// Torrentio Stremio Addon Source.
/// Aggregates YTS, EZTV, 1337x, ThePirateBay, TorrentGalaxy, RARBG, and MagnetDL.
class TorrentioSource extends StremioBaseSource {
  TorrentioSource({
    http.Client? client,
    String? customBaseUrl,
  })  : _baseUrl = customBaseUrl ?? 'https://torrentio.strem.fun',
        super(client: client);

  final String _baseUrl;

  @override
  String get name => 'torrentio';

  @override
  String get displayName => 'Torrentio';

  @override
  String get baseUrl => _baseUrl;
}
