library google_sign_in;

import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class GoogleSignIn {
  static final GoogleSignIn instance = GoogleSignIn._();
  GoogleSignIn._();

  GoogleSignInAccount? _currentUser;
  GoogleSignInAccount? get currentUser => _currentUser;

  Future<void> initialize() async {}

  Future<GoogleSignInAccount> authenticate() async {
    // Start local server to capture the code
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;

    final clientId = dotenv.env['DESKTOP_GOOGLE_CLIENT_ID'];
    if (clientId == null || clientId.isEmpty) {
      throw GoogleSignInException(
        code: 'missing-client-id',
        message: 'DESKTOP_GOOGLE_CLIENT_ID is missing from your .env file. '
            'Please create a "Desktop app" client ID in Google Cloud Console '
            'and add it to your .env file.',
      );
    }
    final redirectUri = "http://localhost:$port";
    
    // Scopes required for Google Sign-In
    final authUrl = "https://accounts.google.com/o/oauth2/v2/auth"
        "?client_id=$clientId"
        "&redirect_uri=${Uri.encodeComponent(redirectUri)}"
        "&response_type=code"
        "&scope=openid%20profile%20email";

    await launchUrl(Uri.parse(authUrl), mode: LaunchMode.externalApplication);

    // Wait for redirect request
    final request = await server.first;
    final code = request.uri.queryParameters['code'];

    // Send visual confirmation to browser
    request.response.statusCode = 200;
    request.response.headers.contentType = ContentType.html;
    request.response.write('''
      <html>
        <head>
          <title>Nivio Sign-In</title>
          <style>
            body { font-family: sans-serif; display: flex; flex-direction: column; align-items: center; justify-content: center; height: 100vh; background-color: #121212; color: #ffffff; margin: 0; }
            .card { background-color: #1e1e1e; padding: 40px; border-radius: 12px; box-shadow: 0 4px 20px rgba(0,0,0,0.5); text-align: center; }
            h1 { color: #4CAF50; margin-top: 0; }
            p { color: #b3b3b3; line-height: 1.6; }
          </style>
        </head>
        <body>
          <div class="card">
            <h1>Sign in Successful!</h1>
            <p>You can close this tab now and return to the Nivio app.</p>
          </div>
        </body>
      </html>
    ''');
    await request.response.close();
    await server.close();

    if (code == null) {
      throw GoogleSignInException(
        code: GoogleSignInExceptionCode.canceled,
        message: 'OAuth authorization code was not returned.',
      );
    }

    // Exchange authorization code for ID token
    final tokenUrl = Uri.parse('https://oauth2.googleapis.com/token');
    final clientSecret = dotenv.env['DESKTOP_GOOGLE_CLIENT_SECRET'];
    final body = {
      'client_id': clientId,
      'code': code,
      'grant_type': 'authorization_code',
      'redirect_uri': redirectUri,
    };
    if (clientSecret != null && clientSecret.isNotEmpty) {
      body['client_secret'] = clientSecret;
    }

    final response = await http.post(
      tokenUrl,
      headers: {'content-type': 'application/x-www-form-urlencoded'},
      body: body,
    );

    if (response.statusCode != 200) {
      throw GoogleSignInException(
        code: 'token-exchange-failed',
        message: 'Failed to exchange OAuth code: ${response.body}',
      );
    }

    final data = jsonDecode(response.body);
    final idToken = data['id_token'] as String;

    // Decode JWT payload to get user details
    final payload = _decodeJwt(idToken);
    final email = payload['email'] as String? ?? 'guest@nivio.com';
    final displayName = payload['name'] as String? ?? 'Nivio User';
    final photoUrl = payload['picture'] as String?;

    final auth = GoogleSignInAuthentication(idToken: idToken);
    final account = GoogleSignInAccount(
      email: email,
      displayName: displayName,
      photoUrl: photoUrl,
      authentication: auth,
    );

    _currentUser = account;
    return account;
  }

  Future<void> signOut() async {
    _currentUser = null;
  }
}

class GoogleSignInAccount {
  final String email;
  final String? displayName;
  final String? photoUrl;
  final GoogleSignInAuthentication authentication;

  GoogleSignInAccount({
    required this.email,
    this.displayName,
    this.photoUrl,
    required this.authentication,
  });
}

class GoogleSignInAuthentication {
  final String? idToken;
  GoogleSignInAuthentication({this.idToken});
}

class GoogleSignInException implements Exception {
  final String code;
  final String message;

  GoogleSignInException({required this.code, required this.message});

  @override
  String toString() => 'GoogleSignInException: [$code] $message';
}

class GoogleSignInExceptionCode {
  static const String canceled = 'canceled';
}

Map<String, dynamic> _decodeJwt(String token) {
  try {
    final parts = token.split('.');
    if (parts.length != 3) return {};
    final payload = parts[1];
    final normalized = base64Url.normalize(payload);
    final decoded = utf8.decode(base64Url.decode(normalized));
    return jsonDecode(decoded) as Map<String, dynamic>;
  } catch (_) {
    return {};
  }
}
