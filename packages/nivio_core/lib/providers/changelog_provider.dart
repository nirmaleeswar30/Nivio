import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nivio/services/github_release_update_service.dart';

class ChangelogState {
  final bool hasSeenCurrentVersion;
  final String currentVersion;
  final String? releaseNotes;
  final bool isLoading;

  ChangelogState({
    required this.hasSeenCurrentVersion,
    required this.currentVersion,
    this.releaseNotes,
    this.isLoading = true,
  });
}

class ChangelogNotifier extends StateNotifier<ChangelogState> {
  ChangelogNotifier()
      : super(ChangelogState(hasSeenCurrentVersion: true, currentVersion: '')) {
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();

    final lastSeenVersion = prefs.getString('last_seen_changelog_version');
    final hasSeen = lastSeenVersion == currentVersion;

    if (hasSeen) {
      state = ChangelogState(
        hasSeenCurrentVersion: true,
        currentVersion: currentVersion,
        isLoading: false,
      );
      return;
    }

    // Fetch release notes if they haven't seen this version
    final notes = await GitHubReleaseUpdateService.getReleaseNotesForVersion(currentVersion);

    state = ChangelogState(
      hasSeenCurrentVersion: false,
      currentVersion: currentVersion,
      releaseNotes: notes,
      isLoading: false,
    );
  }

  Future<void> markAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_seen_changelog_version', state.currentVersion);
    state = ChangelogState(
      hasSeenCurrentVersion: true,
      currentVersion: state.currentVersion,
      releaseNotes: state.releaseNotes,
      isLoading: false,
    );
  }

  Future<String?> forceFetchNotes() async {
    if (state.releaseNotes != null) return state.releaseNotes;
    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version.trim();
    return await GitHubReleaseUpdateService.getReleaseNotesForVersion(currentVersion);
  }
}

final changelogProvider = StateNotifierProvider<ChangelogNotifier, ChangelogState>((ref) {
  return ChangelogNotifier();
});
