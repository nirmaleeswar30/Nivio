import 'dart:io';

import 'package:flutter/foundation.dart';

class AppEnvironment {
  static const String fileName = '.env';
  static const String _configDirName = 'nivio';
  static const String _defaultAuthExchangePath = '/auth/google/firebase';
  static Map<String, String>? _fileValues;

  static const List<String> _requiredKeys = [
    'TMDB_API_KEY',
    'ANILIST_API_URL',
    'IMAGE_PROXY_URL',
    'IPTV_PLAYLIST_URL',
    'LOG_LEVEL',
  ];

  static Future<void> load() async {
    debugPrint('[env] load start');
    _fileValues = null;
    final fileValues = _readFileValues();
    debugPrint('[env] load end fileKeys=${fileValues.length}');
    validate();
    debugPrint('[env] validation ok');
  }

  static void validate() {
    final missing = _requiredKeys
        .where((key) => _value(key).trim().isEmpty)
        .toList(growable: false);
    if (missing.isEmpty) return;

    debugPrint('[env] validation failed missing=${missing.join(',')}');
    throw StateError(
      'Missing required desktop environment variable(s): ${missing.join(', ')}. '
      'Set them in your OS environment or create .env in the project folder, '
      'next to the executable, or in the Nivio config folder.',
    );
  }

  static String get tmdbApiKey => _require('TMDB_API_KEY');
  static String get tmdbReadAccessToken => _optional('TMDB_READ_ACCESS_TOKEN');
  static String get anilistApiUrl => _require('ANILIST_API_URL');
  static String get supabaseUrl => _optional('SUPABASE_URL');
  static String get supabaseAnonKey => _optional('SUPABASE_ANON_KEY');
  static String get iptvPlaylistUrl => _require('IPTV_PLAYLIST_URL');
  static String get iptvEpgUrl => _optional('IPTV_EPG_URL');
  static String get firebaseWebApiKey => _optional('FIREBASE_WEB_API_KEY');
  static String get firebaseProjectId => _optional('FIREBASE_PROJECT_ID');
  static String get firebaseGoogleClientId =>
      _optional('FIREBASE_GOOGLE_CLIENT_ID');
  static String get firebaseAppId => _optional('FIREBASE_APP_ID');
  static String get firebaseMessagingSenderId =>
      _optional('FIREBASE_MESSAGING_SENDER_ID');
  static String get firebaseStorageBucket =>
      _optional('FIREBASE_STORAGE_BUCKET');
  static String get apiBaseUrl => _optional('API_BASE_URL');
  static String get authExchangeUrl {
    final explicit = _optional('AUTH_EXCHANGE_URL');
    if (explicit.isNotEmpty) return explicit;
    final baseUrl = _trimTrailingSlash(apiBaseUrl);
    if (baseUrl.isEmpty) return '';
    return '$baseUrl$_defaultAuthExchangePath';
  }

  static String get imageProxyUrl =>
      _trimTrailingSlash(_require('IMAGE_PROXY_URL'));
  static String get logLevel => _require('LOG_LEVEL');
  static String get desktopUpdateRepoOwner =>
      _optional('DESKTOP_UPDATE_REPO_OWNER');
  static String get desktopUpdateRepoName =>
      _optional('DESKTOP_UPDATE_REPO_NAME');
  static String get desktopUpdateAssetPattern =>
      _optional('DESKTOP_UPDATE_ASSET_PATTERN');

  static String _require(String key) {
    final value = _value(key).trim();
    if (value.isNotEmpty) return value;
    throw StateError(
      'Missing required desktop environment variable: $key. '
      'Set it in your OS environment or runtime .env file.',
    );
  }

  static String _optional(String key) => _value(key).trim();

  static String _value(String key) {
    final environmentValue = Platform.environment[key];
    if (environmentValue != null) return environmentValue;

    final fileValue = _readFileValues()[key];
    if (fileValue != null) return fileValue;

    return _defineValue(key);
  }

  static String _defineValue(String key) {
    switch (key) {
      case 'TMDB_API_KEY':
        return const String.fromEnvironment('TMDB_API_KEY');
      case 'TMDB_READ_ACCESS_TOKEN':
        return const String.fromEnvironment('TMDB_READ_ACCESS_TOKEN');
      case 'ANILIST_API_URL':
        return const String.fromEnvironment('ANILIST_API_URL');
      case 'SUPABASE_URL':
        return const String.fromEnvironment('SUPABASE_URL');
      case 'SUPABASE_ANON_KEY':
        return const String.fromEnvironment('SUPABASE_ANON_KEY');
      case 'IPTV_PLAYLIST_URL':
        return const String.fromEnvironment('IPTV_PLAYLIST_URL');
      case 'IPTV_EPG_URL':
        return const String.fromEnvironment('IPTV_EPG_URL');
      case 'FIREBASE_WEB_API_KEY':
        return const String.fromEnvironment('FIREBASE_WEB_API_KEY');
      case 'FIREBASE_PROJECT_ID':
        return const String.fromEnvironment('FIREBASE_PROJECT_ID');
      case 'FIREBASE_GOOGLE_CLIENT_ID':
        return const String.fromEnvironment('FIREBASE_GOOGLE_CLIENT_ID');
      case 'AUTH_EXCHANGE_URL':
        return const String.fromEnvironment('AUTH_EXCHANGE_URL');
      case 'FIREBASE_APP_ID':
        return const String.fromEnvironment('FIREBASE_APP_ID');
      case 'FIREBASE_MESSAGING_SENDER_ID':
        return const String.fromEnvironment('FIREBASE_MESSAGING_SENDER_ID');
      case 'FIREBASE_STORAGE_BUCKET':
        return const String.fromEnvironment('FIREBASE_STORAGE_BUCKET');
      case 'API_BASE_URL':
        return const String.fromEnvironment('API_BASE_URL');
      case 'IMAGE_PROXY_URL':
        return const String.fromEnvironment('IMAGE_PROXY_URL');
      case 'LOG_LEVEL':
        return const String.fromEnvironment('LOG_LEVEL');
      case 'DESKTOP_UPDATE_REPO_OWNER':
        return const String.fromEnvironment('DESKTOP_UPDATE_REPO_OWNER');
      case 'DESKTOP_UPDATE_REPO_NAME':
        return const String.fromEnvironment('DESKTOP_UPDATE_REPO_NAME');
      case 'DESKTOP_UPDATE_ASSET_PATTERN':
        return const String.fromEnvironment('DESKTOP_UPDATE_ASSET_PATTERN');
    }
    return '';
  }

  static String _trimTrailingSlash(String value) {
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  static Map<String, String> _readFileValues() {
    final cached = _fileValues;
    if (cached != null) return cached;

    final values = <String, String>{};
    for (final file in _candidateConfigFiles()) {
      if (!file.existsSync()) continue;
      for (final rawLine in file.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        final key = line.substring(0, separator).trim();
        final value = line.substring(separator + 1).trim();
        values.putIfAbsent(key, () => value);
      }
    }
    _fileValues = values;
    return values;
  }

  static List<File> _candidateConfigFiles() {
    final files = <String, File>{};
    void add(File file) => files[file.absolute.path] = file;

    add(File(fileName));
    final executable = Platform.resolvedExecutable;
    if (executable.isNotEmpty) {
      add(File('${File(executable).parent.path}/$fileName'));
    }

    final xdgConfigHome = Platform.environment['XDG_CONFIG_HOME']?.trim();
    if (xdgConfigHome != null && xdgConfigHome.isNotEmpty) {
      add(File('$xdgConfigHome/$_configDirName/$fileName'));
    }
    final home = Platform.environment['HOME']?.trim();
    if (home != null && home.isNotEmpty) {
      add(File('$home/.config/$_configDirName/$fileName'));
    }
    final appData = Platform.environment['APPDATA']?.trim();
    if (appData != null && appData.isNotEmpty) {
      add(File('$appData/$_configDirName/$fileName'));
    }
    final userProfile = Platform.environment['USERPROFILE']?.trim();
    if (userProfile != null && userProfile.isNotEmpty) {
      add(File('$userProfile/AppData/Roaming/$_configDirName/$fileName'));
    }

    return files.values.toList(growable: false);
  }
}
