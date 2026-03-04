import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  });

  final GitHubReleaseUpdateStatus status;
  final String installedVersion;
  final String latestVersion;
  final String releaseUrl;
  final String message;

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
  static const String _apkAssetFileName = 'nivio.apk';

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
      final releaseUrl = _resolveInstallUrl(data);

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

  static String _resolveInstallUrl(Map<String, dynamic> releaseData) {
    final fallbackWebUrl =
        (releaseData['html_url']?.toString().trim().isNotEmpty ?? false)
        ? releaseData['html_url'].toString().trim()
        : latestReleaseWebUrl;

    final assets = releaseData['assets'];
    if (assets is List) {
      for (final item in assets) {
        if (item is! Map) continue;
        final asset = Map<String, dynamic>.from(item);
        final name = asset['name']?.toString().trim().toLowerCase() ?? '';
        if (name != _apkAssetFileName) continue;
        final downloadUrl =
            asset['browser_download_url']?.toString().trim() ?? '';
        if (downloadUrl.isNotEmpty) {
          return downloadUrl;
        }
      }
    }

    return fallbackWebUrl;
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
