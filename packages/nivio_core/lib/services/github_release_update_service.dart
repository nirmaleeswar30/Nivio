import 'dart:io';
import 'dart:ffi';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

enum GitHubReleaseUpdateStatus {
  upToDate,
  updateAvailable,
  unavailable,
  failed,
}

class GitHubReleaseUpdateResult {
  const GitHubReleaseUpdateResult({
    required this.status,
    required this.installedVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.message,
    this.releaseNotes,
  });

  final GitHubReleaseUpdateStatus status;
  final String installedVersion;
  final String latestVersion;
  final String releaseUrl;
  final String message;
  final String? releaseNotes;

  bool get hasUpdate => status == GitHubReleaseUpdateStatus.updateAvailable;
}

class GitHubReleaseUpdateService {
  GitHubReleaseUpdateService._();

  static const String repoOwner = 'nirmaleeswar30';
  static const String repoName = 'Nivio';
  static const String latestReleaseWebUrl =
      'https://github.com/$repoOwner/$repoName/releases/latest';
  static const String _latestReleaseApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 12),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'Nivio-App-Update-Checker',
      },
      validateStatus: (status) => status != null && status < 600,
    ),
  );

  static const Duration _cacheTtl = Duration(minutes: 15);
  static GitHubReleaseUpdateResult? _cachedResult;
  static DateTime? _cachedAt;

  static Future<GitHubReleaseUpdateResult> checkForUpdate({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedResult != null &&
        _cachedAt != null &&
        DateTime.now().difference(_cachedAt!) < _cacheTtl) {
      return _cachedResult!;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final installed = packageInfo.version.trim();

    try {
      final response = await _dio.get(_latestReleaseApiUrl);
      if (response.statusCode != 200 || response.data is! Map) {
        return _cache(
          GitHubReleaseUpdateResult(
            status: GitHubReleaseUpdateStatus.unavailable,
            installedVersion: installed,
            latestVersion: '',
            releaseUrl: latestReleaseWebUrl,
            message: 'Could not read latest release right now.',
          ),
        );
      }

      final data = Map<String, dynamic>.from(response.data as Map);
      final latestRaw =
          (data['tag_name']?.toString().trim().isNotEmpty ?? false)
          ? data['tag_name'].toString().trim()
          : (data['name']?.toString().trim() ?? '');
      final latest = _normalizeVersion(latestRaw);
      final releaseUrl = await _resolveInstallUrl(data);

      if (latest.isEmpty) {
        return _cache(
          GitHubReleaseUpdateResult(
            status: GitHubReleaseUpdateStatus.unavailable,
            installedVersion: installed,
            latestVersion: '',
            releaseUrl: releaseUrl,
            message: 'Latest release version is unavailable.',
          ),
        );
      }

      final compare = _compareVersions(
        _normalizeVersion(installed),
        _normalizeVersion(latest),
      );
      if (compare < 0) {
        return _cache(
          GitHubReleaseUpdateResult(
            status: GitHubReleaseUpdateStatus.updateAvailable,
            installedVersion: installed,
            latestVersion: latest,
            releaseUrl: releaseUrl,
            message: 'Update available: $latest',
            releaseNotes: data['body']?.toString(),
          ),
        );
      }

      return _cache(
        GitHubReleaseUpdateResult(
          status: GitHubReleaseUpdateStatus.upToDate,
          installedVersion: installed,
          latestVersion: latest,
          releaseUrl: releaseUrl,
          message: 'You are on the latest version.',
        ),
      );
    } catch (error) {
      debugPrint('[GitHubUpdate] check failed: $error');
      return _cache(
        GitHubReleaseUpdateResult(
          status: GitHubReleaseUpdateStatus.failed,
          installedVersion: installed,
          latestVersion: '',
          releaseUrl: latestReleaseWebUrl,
          message: 'Failed to check GitHub releases.',
        ),
      );
    }
  }

  static Future<String?> getReleaseNotesForVersion(String version) async {
    try {
      var response = await _dio.get('https://api.github.com/repos/$repoOwner/$repoName/releases/tags/v$version');
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['body']?.toString();
      }
    } catch (_) {}

    try {
      var response = await _dio.get('https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$version');
      if (response.statusCode == 200 && response.data is Map) {
        return response.data['body']?.toString();
      }
    } catch (_) {}

    return null;
  }

  static Future<bool> openReleasePage([String? releaseUrl]) async {
    final target = (releaseUrl ?? latestReleaseWebUrl).trim();
    if (target.isEmpty) return false;
    final uri = Uri.tryParse(target);
    if (uri == null) return false;
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static GitHubReleaseUpdateResult _cache(GitHubReleaseUpdateResult result) {
    _cachedResult = result;
    _cachedAt = DateTime.now();
    return result;
  }

  static Future<String> _resolveInstallUrl(Map<String, dynamic> releaseData) async {
    final fallbackWebUrl =
        (releaseData['html_url']?.toString().trim().isNotEmpty ?? false)
        ? releaseData['html_url'].toString().trim()
        : latestReleaseWebUrl;

    final rawAssets = releaseData['assets'];
    if (rawAssets is! List || rawAssets.isEmpty) {
      return fallbackWebUrl;
    }

    final assets = rawAssets
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();

    // 1. WINDOWS DESKTOP:
    if (!kIsWeb && Platform.isWindows) {
      final setupExe = assets.firstWhere(
        (a) {
          final name = a['name']?.toString().trim().toLowerCase() ?? '';
          return (name.startsWith('nivio-setup') || name.contains('setup')) && name.endsWith('.exe');
        },
        orElse: () => assets.firstWhere(
          (a) {
            final name = a['name']?.toString().trim().toLowerCase() ?? '';
            return name.endsWith('.exe');
          },
          orElse: () => <String, dynamic>{},
        ),
      );
      final url = setupExe['browser_download_url']?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
      return fallbackWebUrl;
    }

    // 2. LINUX DESKTOP:
    if (!kIsWeb && Platform.isLinux) {
      final appImage = assets.firstWhere(
        (a) {
          final name = a['name']?.toString().trim().toLowerCase() ?? '';
          return name.startsWith('nivio-linux') && name.endsWith('.appimage');
        },
        orElse: () => assets.firstWhere(
          (a) {
            final name = a['name']?.toString().trim().toLowerCase() ?? '';
            return name.endsWith('.appimage');
          },
          orElse: () => <String, dynamic>{},
        ),
      );
      final url = appImage['browser_download_url']?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
      return fallbackWebUrl;
    }

    // 3. MACOS DESKTOP:
    if (!kIsWeb && Platform.isMacOS) {
      final macAsset = assets.firstWhere(
        (a) {
          final name = a['name']?.toString().trim().toLowerCase() ?? '';
          return name.endsWith('.dmg') || name.endsWith('.pkg');
        },
        orElse: () => <String, dynamic>{},
      );
      final url = macAsset['browser_download_url']?.toString().trim() ?? '';
      if (url.isNotEmpty) return url;
      return fallbackWebUrl;
    }

    // 4. ANDROID (MOBILE):
    if (!kIsWeb && Platform.isAndroid) {
      final flavor = await detectAndroidApkFlavor();

      if (flavor == 'universal') {
        // User has universal.apk installed -> prioritize universal.apk assets
        final universalApk = assets.firstWhere(
          (a) {
            final name = a['name']?.toString().trim().toLowerCase() ?? '';
            return name.endsWith('.apk') && name.contains('universal');
          },
          orElse: () => <String, dynamic>{},
        );
        final url = universalApk['browser_download_url']?.toString().trim() ?? '';
        if (url.isNotEmpty) return url;
      } else {
        // User has standard / nivio.apk installed -> prioritize nivio.apk assets
        final standardApk = assets.firstWhere(
          (a) {
            final name = a['name']?.toString().trim().toLowerCase() ?? '';
            return (name == 'nivio.apk' || (name.startsWith('nivio') && name.endsWith('.apk'))) &&
                !name.contains('universal') &&
                !name.contains('armeabi') &&
                !name.contains('x86');
          },
          orElse: () => <String, dynamic>{},
        );
        final url = standardApk['browser_download_url']?.toString().trim() ?? '';
        if (url.isNotEmpty) return url;
      }

      // Android Fallback: if preferred flavor wasn't found, try any non-universal then universal
      final anyApk = assets.firstWhere(
        (a) {
          final name = a['name']?.toString().trim().toLowerCase() ?? '';
          return name.endsWith('.apk') && !name.contains('universal');
        },
        orElse: () => assets.firstWhere(
          (a) {
            final name = a['name']?.toString().trim().toLowerCase() ?? '';
            return name.endsWith('.apk');
          },
          orElse: () => <String, dynamic>{},
        ),
      );
      final fallbackApkUrl = anyApk['browser_download_url']?.toString().trim() ?? '';
      if (fallbackApkUrl.isNotEmpty) return fallbackApkUrl;
    }

    return fallbackWebUrl;
  }

  /// Detects whether the user is running universal.apk or standard nivio.apk
  static Future<String> detectAndroidApkFlavor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('preferred_apk_flavor');
      if (saved == 'universal' || saved == 'standard') {
        return saved!;
      }

      if (!kIsWeb && Platform.isAndroid) {
        // On 32-bit ARM (armeabi-v7a) or x86 Android, arm64-only nivio.apk cannot run.
        // Therefore this device must run universal APK.
        try {
          final abi = Abi.current();
          if (abi != Abi.androidArm64) {
            await prefs.setString('preferred_apk_flavor', 'universal');
            return 'universal';
          }
        } catch (_) {}

        // Inspect running APK's central directory via /proc/self/maps
        final apkFlavor = await _inspectInstalledApkCentralDirectory();
        if (apkFlavor != null) {
          await prefs.setString('preferred_apk_flavor', apkFlavor);
          return apkFlavor;
        }
      }
    } catch (e) {
      debugPrint('[GitHubUpdate] Flavor detection error: $e');
    }
    return 'standard';
  }

  /// Allows user to manually switch/set their preferred APK flavor
  static Future<void> setAndroidApkFlavorPreference(String flavor) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('preferred_apk_flavor', flavor);
    } catch (_) {}
  }

  /// Lightweight inspection of installed base.apk on Android:
  /// Reads only the trailing Central Directory (last 128KB) to see if both
  /// lib/armeabi-v7a and lib/arm64-v8a folders exist (universal), or only arm64-v8a (standard).
  static Future<String?> _inspectInstalledApkCentralDirectory() async {
    try {
      final mapsFile = File('/proc/self/maps');
      if (!mapsFile.existsSync()) return null;
      final lines = await mapsFile.readAsLines();
      for (final line in lines) {
        if (!line.contains('.apk')) continue;
        final match = RegExp(r'(/data/app/[^\s]+\.apk)').firstMatch(line);
        if (match != null) {
          final apkPath = match.group(1);
          if (apkPath != null) {
            final apkFile = File(apkPath);
            if (apkFile.existsSync()) {
              final raf = await apkFile.open();
              final len = await raf.length();
              final readSize = len < 131072 ? len : 131072;
              await raf.setPosition(len - readSize);
              final tailBytes = await raf.read(readSize);
              await raf.close();
              final tailStr = String.fromCharCodes(tailBytes);
              final hasArmeabi = tailStr.contains('lib/armeabi-v7a');
              final hasArm64 = tailStr.contains('lib/arm64-v8a');
              if (hasArmeabi && hasArm64) {
                return 'universal';
              } else if (hasArm64) {
                return 'standard';
              }
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static String _normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = value.replaceFirst(RegExp(r'^[vV]'), '');
    final buildIndex = value.indexOf('+');
    if (buildIndex != -1) {
      value = value.substring(0, buildIndex);
    }
    final preReleaseIndex = value.indexOf('-');
    if (preReleaseIndex != -1) {
      value = value.substring(0, preReleaseIndex);
    }
    return value.trim();
  }

  static int _compareVersions(String a, String b) {
    final aParts = _parseParts(a);
    final bParts = _parseParts(b);
    final maxLen = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < maxLen; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) {
        return av.compareTo(bv);
      }
    }
    return 0;
  }

  static List<int> _parseParts(String version) {
    if (version.trim().isEmpty) return const [0];
    return version
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList();
  }
}
