import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_environment.dart';

enum DesktopFullUpdateStatus { upToDate, updateAvailable, unavailable, failed }

enum DesktopPatchUpdateAction {
  unavailable,
  upToDate,
  downloaded,
  restartRequired,
  failed,
}

class DesktopVersionInfo {
  const DesktopVersionInfo({required this.version, required this.buildNumber});

  final String version;
  final String buildNumber;

  String get label =>
      buildNumber.trim().isEmpty ? version : '$version+$buildNumber';
}

class DesktopFullUpdateResult {
  const DesktopFullUpdateResult({
    required this.status,
    required this.installedVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.installUrl,
    required this.message,
    this.releaseNotes,
    this.assetName,
  });

  final DesktopFullUpdateStatus status;
  final String installedVersion;
  final String latestVersion;
  final String releaseUrl;
  final String installUrl;
  final String message;
  final String? releaseNotes;
  final String? assetName;

  bool get hasUpdate => status == DesktopFullUpdateStatus.updateAvailable;
}

class DesktopPatchUpdateResult {
  const DesktopPatchUpdateResult({
    required this.action,
    required this.message,
    this.currentPatch,
  });

  final DesktopPatchUpdateAction action;
  final String message;
  final int? currentPatch;

  bool get needsRestart => action == DesktopPatchUpdateAction.restartRequired;
}

class DesktopUpdateCheckResult {
  const DesktopUpdateCheckResult({
    required this.fullRelease,
    required this.patch,
  });

  final DesktopFullUpdateResult fullRelease;
  final DesktopPatchUpdateResult patch;

  String get message {
    if (fullRelease.hasUpdate) return fullRelease.message;
    if (patch.action == DesktopPatchUpdateAction.downloaded ||
        patch.action == DesktopPatchUpdateAction.restartRequired) {
      return patch.message;
    }
    if (fullRelease.status == DesktopFullUpdateStatus.upToDate &&
        patch.action == DesktopPatchUpdateAction.upToDate) {
      return 'You are up to date.';
    }
    if (fullRelease.status == DesktopFullUpdateStatus.upToDate &&
        patch.action == DesktopPatchUpdateAction.unavailable) {
      return 'You are on the latest full release.';
    }
    if (fullRelease.status == DesktopFullUpdateStatus.failed) {
      return fullRelease.message;
    }
    return patch.message;
  }
}

class DesktopUpdateService {
  DesktopUpdateService._();

  static final ShorebirdUpdater _shorebirdUpdater = ShorebirdUpdater();
  static final http.Client _client = http.Client();

  static const String _defaultOwner = 'NithishSaravananRss';
  static const String _defaultRepo = 'Nivio';
  static const Duration _cacheTtl = Duration(minutes: 15);

  static DesktopFullUpdateResult? _cachedFullRelease;
  static DateTime? _cachedFullReleaseAt;
  static Future<DesktopUpdateCheckResult>? _activeCheck;

  static bool get isShorebirdAvailable => _shorebirdUpdater.isAvailable;

  static Future<DesktopVersionInfo> currentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return DesktopVersionInfo(
        version: packageInfo.version.trim(),
        buildNumber: packageInfo.buildNumber.trim(),
      );
    } catch (_) {
      return _readPubspecVersion();
    }
  }

  static Future<DesktopUpdateCheckResult> checkForUpdates({
    bool forceRefresh = false,
    bool includeShorebird = true,
    bool downloadShorebirdPatch = false,
  }) {
    if (_activeCheck != null) return _activeCheck!;
    final check = _checkForUpdates(
      forceRefresh: forceRefresh,
      includeShorebird: includeShorebird,
      downloadShorebirdPatch: downloadShorebirdPatch,
    );
    _activeCheck = check.whenComplete(() => _activeCheck = null);
    return _activeCheck!;
  }

  static Future<DesktopFullUpdateResult> checkFullRelease({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cachedFullRelease != null &&
        _cachedFullReleaseAt != null &&
        DateTime.now().difference(_cachedFullReleaseAt!) < _cacheTtl) {
      return _cachedFullRelease!;
    }

    final installed = await currentVersion();
    final releaseApiUrl = _latestReleaseApiUrl;
    final releaseWebUrl = _latestReleaseWebUrl;

    try {
      final response = await _client
          .get(
            Uri.parse(releaseApiUrl),
            headers: const {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'Nivio-Desktop-Update-Checker',
            },
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode != 200) {
        return _cacheFullRelease(
          DesktopFullUpdateResult(
            status: DesktopFullUpdateStatus.unavailable,
            installedVersion: installed.version,
            latestVersion: '',
            releaseUrl: releaseWebUrl,
            installUrl: releaseWebUrl,
            message: 'Could not read latest GitHub release.',
          ),
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        return _cacheFullRelease(
          DesktopFullUpdateResult(
            status: DesktopFullUpdateStatus.unavailable,
            installedVersion: installed.version,
            latestVersion: '',
            releaseUrl: releaseWebUrl,
            installUrl: releaseWebUrl,
            message: 'Latest release response was not valid.',
          ),
        );
      }

      final latestRaw = _releaseVersion(decoded);
      final latest = _normalizeVersion(latestRaw);
      final releaseUrl = _stringValue(
        decoded['html_url'],
        fallback: releaseWebUrl,
      );
      final asset = _resolveLinuxAsset(decoded);
      final installUrl = asset?.downloadUrl ?? releaseUrl;

      if (latest.isEmpty) {
        return _cacheFullRelease(
          DesktopFullUpdateResult(
            status: DesktopFullUpdateStatus.unavailable,
            installedVersion: installed.version,
            latestVersion: '',
            releaseUrl: releaseUrl,
            installUrl: installUrl,
            message: 'Latest release version is unavailable.',
          ),
        );
      }

      final comparison = _compareVersions(
        _normalizeVersion(installed.version),
        latest,
      );
      if (comparison < 0) {
        return _cacheFullRelease(
          DesktopFullUpdateResult(
            status: DesktopFullUpdateStatus.updateAvailable,
            installedVersion: installed.version,
            latestVersion: latest,
            releaseUrl: releaseUrl,
            installUrl: installUrl,
            assetName: asset?.name,
            message: 'Update available: $latest',
            releaseNotes: _stringValue(decoded['body']),
          ),
        );
      }

      return _cacheFullRelease(
        DesktopFullUpdateResult(
          status: DesktopFullUpdateStatus.upToDate,
          installedVersion: installed.version,
          latestVersion: latest,
          releaseUrl: releaseUrl,
          installUrl: installUrl,
          assetName: asset?.name,
          message: 'You are on the latest full release.',
          releaseNotes: _stringValue(decoded['body']),
        ),
      );
    } catch (error) {
      debugPrint('[DesktopUpdate] full release check failed: $error');
      return _cacheFullRelease(
        DesktopFullUpdateResult(
          status: DesktopFullUpdateStatus.failed,
          installedVersion: installed.version,
          latestVersion: '',
          releaseUrl: releaseWebUrl,
          installUrl: releaseWebUrl,
          message: 'Failed to check GitHub releases.',
        ),
      );
    }
  }

  static Future<DesktopPatchUpdateResult> checkShorebirdPatch({
    bool downloadPatch = false,
    UpdateTrack track = UpdateTrack.stable,
  }) async {
    if (!_shorebirdUpdater.isAvailable) {
      return const DesktopPatchUpdateResult(
        action: DesktopPatchUpdateAction.unavailable,
        message: 'Shorebird patches are unavailable in this build.',
      );
    }

    try {
      final currentPatch = await _shorebirdUpdater.readCurrentPatch();
      final status = await _shorebirdUpdater.checkForUpdate(track: track);
      switch (status) {
        case UpdateStatus.unavailable:
          return DesktopPatchUpdateResult(
            action: DesktopPatchUpdateAction.unavailable,
            message: 'Shorebird patch channel is unavailable.',
            currentPatch: currentPatch?.number,
          );
        case UpdateStatus.upToDate:
          return DesktopPatchUpdateResult(
            action: DesktopPatchUpdateAction.upToDate,
            message: 'You already have the latest Shorebird patch.',
            currentPatch: currentPatch?.number,
          );
        case UpdateStatus.outdated:
          if (!downloadPatch) {
            return DesktopPatchUpdateResult(
              action: DesktopPatchUpdateAction.downloaded,
              message: 'A Shorebird patch is available.',
              currentPatch: currentPatch?.number,
            );
          }
          await _shorebirdUpdater.update(track: track);
          return DesktopPatchUpdateResult(
            action: DesktopPatchUpdateAction.downloaded,
            message: 'Shorebird patch downloaded. Restart Nivio to apply it.',
            currentPatch: currentPatch?.number,
          );
        case UpdateStatus.restartRequired:
          return DesktopPatchUpdateResult(
            action: DesktopPatchUpdateAction.restartRequired,
            message: 'A Shorebird patch is ready. Restart Nivio to apply it.',
            currentPatch: currentPatch?.number,
          );
      }
    } on UpdateException catch (error) {
      return DesktopPatchUpdateResult(
        action: DesktopPatchUpdateAction.failed,
        message: 'Shorebird update failed: ${error.message}',
      );
    } catch (error) {
      return DesktopPatchUpdateResult(
        action: DesktopPatchUpdateAction.failed,
        message: 'Shorebird update check failed: $error',
      );
    }
  }

  static Future<bool> openInstallTarget(DesktopFullUpdateResult update) {
    return openUrl(
      update.installUrl.isEmpty ? update.releaseUrl : update.installUrl,
    );
  }

  static Future<bool> openUrl(String target) async {
    final uri = Uri.tryParse(target.trim());
    if (uri == null) return false;
    if (!await canLaunchUrl(uri)) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<DesktopUpdateCheckResult> _checkForUpdates({
    required bool forceRefresh,
    required bool includeShorebird,
    required bool downloadShorebirdPatch,
  }) async {
    final fullRelease = await checkFullRelease(forceRefresh: forceRefresh);
    final patch = includeShorebird
        ? await checkShorebirdPatch(downloadPatch: downloadShorebirdPatch)
        : const DesktopPatchUpdateResult(
            action: DesktopPatchUpdateAction.unavailable,
            message: 'Shorebird patch check skipped.',
          );
    return DesktopUpdateCheckResult(fullRelease: fullRelease, patch: patch);
  }

  static DesktopFullUpdateResult _cacheFullRelease(
    DesktopFullUpdateResult result,
  ) {
    _cachedFullRelease = result;
    _cachedFullReleaseAt = DateTime.now();
    return result;
  }

  static String get _repoOwner {
    final configured = AppEnvironment.desktopUpdateRepoOwner.trim();
    return configured.isEmpty ? _defaultOwner : configured;
  }

  static String get _repoName {
    final configured = AppEnvironment.desktopUpdateRepoName.trim();
    return configured.isEmpty ? _defaultRepo : configured;
  }

  static String get _latestReleaseApiUrl {
    return 'https://api.github.com/repos/$_repoOwner/$_repoName/releases/latest';
  }

  static String get _latestReleaseWebUrl {
    return 'https://github.com/$_repoOwner/$_repoName/releases/latest';
  }

  static String _releaseVersion(Map<String, dynamic> release) {
    final tag = _stringValue(release['tag_name']);
    if (tag.isNotEmpty) return tag;
    return _stringValue(release['name']);
  }

  static _ReleaseAsset? _resolveLinuxAsset(Map<String, dynamic> release) {
    final assets = release['assets'];
    if (assets is! List) return null;
    final patterns = _assetPatterns;
    _ReleaseAsset? first;
    for (final item in assets) {
      if (item is! Map) continue;
      final asset = Map<String, dynamic>.from(item);
      final name = _stringValue(asset['name']);
      final url = _stringValue(asset['browser_download_url']);
      if (name.isEmpty || url.isEmpty) continue;
      first ??= _ReleaseAsset(name: name, downloadUrl: url);
      final lower = name.toLowerCase();
      if (patterns.any(lower.contains)) {
        return _ReleaseAsset(name: name, downloadUrl: url);
      }
    }
    return first;
  }

  static List<String> get _assetPatterns {
    final configured = AppEnvironment.desktopUpdateAssetPattern.trim();
    final raw = configured.isEmpty
        ? 'appimage,.deb,.rpm,.tar.gz,.zip'
        : configured;
    return raw
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  static Future<DesktopVersionInfo> _readPubspecVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final version = packageInfo.version.trim();
      final buildNumber = packageInfo.buildNumber.trim();
      if (version.isNotEmpty) {
        return DesktopVersionInfo(
          version: version,
          buildNumber: buildNumber.isEmpty ? '1' : buildNumber,
        );
      }
    } catch (_) {}

    final file = File('pubspec.yaml');
    if (!file.existsSync()) {
      return const DesktopVersionInfo(version: '1.0.0', buildNumber: '1');
    }
    final content = await file.readAsString();
    final match = RegExp(
      r'^version:\s*([^\s+]+)(?:\+(\S+))?',
      multiLine: true,
    ).firstMatch(content);
    return DesktopVersionInfo(
      version: match?.group(1) ?? '1.0.0',
      buildNumber: match?.group(2) ?? '1',
    );
  }

  static String _normalizeVersion(String raw) {
    var value = raw.trim();
    if (value.isEmpty) return '';
    value = value.replaceFirst(RegExp(r'^[vV]'), '');
    final buildIndex = value.indexOf('+');
    if (buildIndex != -1) value = value.substring(0, buildIndex);
    final preReleaseIndex = value.indexOf('-');
    if (preReleaseIndex != -1) value = value.substring(0, preReleaseIndex);
    return value.trim();
  }

  static int _compareVersions(String a, String b) {
    final aParts = _parseVersionParts(a);
    final bParts = _parseVersionParts(b);
    final maxLength = aParts.length > bParts.length
        ? aParts.length
        : bParts.length;
    for (var i = 0; i < maxLength; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }

  static List<int> _parseVersionParts(String version) {
    if (version.trim().isEmpty) return const [0];
    return version
        .split('.')
        .map(
          (part) => int.tryParse(part.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        )
        .toList(growable: false);
  }

  static String _stringValue(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}

class _ReleaseAsset {
  const _ReleaseAsset({required this.name, required this.downloadUrl});

  final String name;
  final String downloadUrl;
}
