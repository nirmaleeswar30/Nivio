import 'dart:async';
import 'dart:io';

bool isPublicWebUrl(Uri uri) {
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

HttpClient publicWebHttpClient() => HttpClient()
  ..connectionTimeout = const Duration(seconds: 8)
  ..findProxy = ((_) => 'DIRECT')
  ..connectionFactory = (uri, _, _) => _connectToProvider(uri);

Future<ConnectionTask<Socket>> _connectToProvider(Uri uri) async {
  if (!isPublicWebUrl(uri)) {
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
