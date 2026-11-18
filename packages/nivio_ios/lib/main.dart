import 'package:cupertino_http/cupertino_http.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/main.dart' as core_main;
import 'package:nivio/services/network_client_factory.dart';

void main() async {
  NetworkClientFactory.registerClientBuilder(() => _client);
  core_main.main();
}

/// Apple's own network stack (NSURLSession), the iOS counterpart of Cronet on
/// Android: a real browser's TLS/HTTP2 fingerprint (Safari's), which
/// Cloudflare-fronted sources check, unlike dart:io's HttpClient. One session
/// is shared by every caller.
final http.Client _client = _SharedClient(() {
  final config = URLSessionConfiguration.ephemeralSessionConfiguration()
    // Callers send their own Cookie headers (as with Cronet, which keeps no
    // cookie jar); don't let NSURLSession add stored ones on top.
    ..httpShouldSetCookies = false
    ..httpAdditionalHeaders = const {
      'User-Agent':
          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
    };
  return CupertinoClient.fromSessionConfiguration(config);
});

/// A long-lived client handed out to many callers: closing it is a no-op, so
/// one caller's `close()` can't end the session the others are using.
class _SharedClient extends http.BaseClient {
  _SharedClient(this._create);

  final http.Client Function() _create;
  late final http.Client _inner = _create();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) => _inner.send(request);

  @override
  void close() {}
}
