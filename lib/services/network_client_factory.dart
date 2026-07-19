import 'package:http/http.dart' as http;

/// Abstract factory for creating platform-specific HTTP clients.
class NetworkClientFactory {
  NetworkClientFactory._();

  static http.Client Function()? _customClientBuilder;

  /// Registers a custom [http.Client] builder (e.g. CronetClient or RhttpCompatibleClient).
  static void registerClientBuilder(http.Client Function() builder) {
    _customClientBuilder = builder;
  }

  /// Creates a platform-configured or default [http.Client].
  static http.Client createClient() {
    if (_customClientBuilder != null) {
      return _customClientBuilder!();
    }
    return http.Client();
  }
}
