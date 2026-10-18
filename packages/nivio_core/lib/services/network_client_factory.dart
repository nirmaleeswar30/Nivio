import 'dart:io';
import 'package:cronet_http/cronet_http.dart';
import 'package:http/http.dart' as http;
import 'package:nivio/core/debug_log.dart';

/// Abstract factory for creating platform-specific HTTP clients.
class NetworkClientFactory {
  NetworkClientFactory._();

  static http.Client Function()? _customClientBuilder;
  static CronetEngine? _cronetEngine;

  /// Registers a custom [http.Client] builder (e.g. CronetClient or custom client).
  static void registerClientBuilder(http.Client Function() builder) {
    _customClientBuilder = builder;
  }

  /// Creates a platform-configured or default [http.Client].
  /// On Android, uses [CronetClient] via [CronetEngine] to leverage Chromium's
  /// network stack (BoringSSL/HTTP2/QUIC) and bypass Cloudflare TLS fingerprinting.
  static http.Client createClient({String? userAgent}) {
    if (_customClientBuilder != null) {
      return _customClientBuilder!();
    }

    if (Platform.isAndroid) {
      try {
        _cronetEngine ??= CronetEngine.build(
          cacheMode: CacheMode.disabled,
          enableBrotli: true,
          enableHttp2: true,
          enableQuic: true,
          userAgent: userAgent ??
              'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
        );
        return CronetClient.fromCronetEngine(_cronetEngine!, closeEngine: false);
      } catch (e) {
        appDebugLog('⚠️ Failed to initialize CronetClient: $e. Falling back to default http.Client');
        return http.Client();
      }
    }

    return http.Client();
  }
}
