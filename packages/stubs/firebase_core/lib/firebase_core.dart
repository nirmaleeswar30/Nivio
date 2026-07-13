library firebase_core;

class Firebase {
  static FirebaseApp? _app;
  static FirebaseOptions? options;

  static FirebaseApp get app {
    if (_app == null) throw StateError('Firebase has not been initialized.');
    return _app!;
  }

  static Future<FirebaseApp> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    Firebase.options = options;
    _app = FirebaseApp(name: name ?? '[DEFAULT]', options: options);
    return _app!;
  }
}

class FirebaseApp {
  final String name;
  final FirebaseOptions? options;

  FirebaseApp({required this.name, this.options});
}

class FirebaseOptions {
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String? storageBucket;

  const FirebaseOptions({
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    this.storageBucket,
  });
}
