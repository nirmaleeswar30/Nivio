import 'package:rhttp/rhttp.dart';
import 'package:nivio/services/network_client_factory.dart';
import 'package:nivio/main.dart' as core_main;

void main() async {
  await Rhttp.init();
  NetworkClientFactory.registerClientBuilder(() {
    return RhttpCompatibleClient.createSync();
  });

  core_main.main();
}
