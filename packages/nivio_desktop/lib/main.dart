import 'package:rhttp/rhttp.dart';
import 'package:nivio/services/network_client_factory.dart';
import 'package:nivio/main.dart' as core_main;

// Launch args must reach core main: a second instance started by the browser
// with `nivio://auth/...` forwards that link to the running instance.
void main(List<String> args) async {
  await Rhttp.init();
  NetworkClientFactory.registerClientBuilder(() {
    return RhttpCompatibleClient.createSync();
  });

  core_main.main(args);
}
