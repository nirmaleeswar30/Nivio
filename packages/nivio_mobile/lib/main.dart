import 'dart:io';
import 'package:cronet_http/cronet_http.dart';
import 'package:nivio/services/network_client_factory.dart';
import 'package:nivio/main.dart' as core_main;

void main() async {
  NetworkClientFactory.registerClientBuilder(() {
    if (Platform.isAndroid || Platform.isIOS) {
      final engine = CronetEngine.build(
        cacheMode: CacheMode.disabled,
        userAgent: 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/114.0.0.0 Mobile Safari/537.36',
      );
      return CronetClient.fromCronetEngine(engine);
    }
    return CronetClient.defaultCronetEngine();
  });

  core_main.main();
}
