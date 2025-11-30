import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/providers/service_providers.dart';
import 'package:nivio/providers/watch_history_provider.dart';
import 'package:nivio/providers/language_preferences_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings Screen - All settings are functional and persist via SharedPreferences
/// 
/// ✅ INTEGRATED SETTINGS:
/// - Playback Speed: Applied to VideoPlayerController in player_screen.dart
/// - Video Quality: Used when fetching stream URLs from configured providers
/// - Clear Watch History: Deletes Hive watch_history box
/// - Sign Out: Calls Firebase Auth sign out
/// 
/// ⏳ SAVED BUT NOT YET INTEGRATED:
/// - Subtitles: Saved to SharedPreferences, needs subtitle parser integration
/// - Animations: Saved to SharedPreferences, needs conditional checks in widgets
/// 
/// See SETTINGS_INTEGRATION.md for complete integration details

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final playbackSpeed = ref.watch(playbackSpeedProvider);
    final videoQualityNotifier = ref.read(videoQualityProvider.notifier);
    final subtitlesEnabled = ref.watch(subtitlesEnabledProvider);
    final animationsEnabled = ref.watch(animationsEnabledProvider);
    final languagePreferences = ref.watch(languagePreferencesProvider);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: NivioTheme.netflixBlack,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          // Account Section
          _buildSectionHeader('Account'),
          _buildSettingsTile(
            icon: Icons.person_outline,
            title: 'User ID',
            subtitle: user?.uid ?? 'Not signed in',
            trailing: null,
          ),
          _buildSettingsTile(
            icon: Icons.login,
            title: 'Sign In Method',
            subtitle: _getSignInMethod(user),
            trailing: null,
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // Content Preferences
          _buildSectionHeader('Content Preferences'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Text(
              'Choose which regional content appears on your home screen',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 13,
              ),
            ),
          ),
          _buildLanguageToggle(
            context: context,
            ref: ref,
            title: '🎌 Anime',
            subtitle: 'Japanese Animation',
            value: languagePreferences.showAnime,
            onChanged: (value) {
              ref.read(languagePreferencesProvider.notifier).toggleAnime(value);
            },
          ),
          _buildLanguageToggle(
            context: context,
            ref: ref,
            title: '🎬 Tamil',
            subtitle: 'Tamil Movies & Shows',
            value: languagePreferences.showTamil,
            onChanged: (value) {
              ref.read(languagePreferencesProvider.notifier).toggleTamil(value);
            },
          ),
          _buildLanguageToggle(
            context: context,
            ref: ref,
            title: '🎥 Telugu',
            subtitle: 'Telugu Movies & Shows',
            value: languagePreferences.showTelugu,
            onChanged: (value) {
              ref.read(languagePreferencesProvider.notifier).toggleTelugu(value);
            },
          ),
          _buildLanguageToggle(
            context: context,
            ref: ref,
            title: '🎞️ Hindi',
            subtitle: 'Hindi Movies & Shows',
            value: languagePreferences.showHindi,
            onChanged: (value) {
              ref.read(languagePreferencesProvider.notifier).toggleHindi(value);
            },
          ),
          _buildLanguageToggle(
            context: context,
            ref: ref,
            title: '🇰🇷 Korean',
            subtitle: 'Korean Dramas',
            value: languagePreferences.showKorean,
            onChanged: (value) {
              ref.read(languagePreferencesProvider.notifier).toggleKorean(value);
            },
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // Playback Settings
          _buildSectionHeader('Playback'),
          _buildSettingsTile(
            icon: Icons.speed,
            title: 'Default Playback Speed',
            subtitle: '${playbackSpeed}x',
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () {
              _showPlaybackSpeedDialog(context, ref);
            },
          ),
          _buildSettingsTile(
            icon: Icons.high_quality,
            title: 'Preferred Video Quality',
            subtitle: videoQualityNotifier.displayName,
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () {
              _showVideoQualityDialog(context, ref);
            },
          ),
          _buildSettingsTile(
            icon: Icons.subtitles_outlined,
            title: 'Enable Subtitles',
            subtitle: subtitlesEnabled ? 'Enabled' : 'Disabled',
            trailing: Switch(
              value: subtitlesEnabled,
              onChanged: (_) {
                ref.read(subtitlesEnabledProvider.notifier).toggle();
              },
              activeColor: NivioTheme.netflixRed,
            ),
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // Data & Storage
          _buildSectionHeader('Data & Storage'),
          _buildSettingsTile(
            icon: Icons.storage_outlined,
            title: 'Clear Watch History',
            subtitle: 'Remove all watch history data',
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () {
              _showClearHistoryDialog(context, ref);
            },
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // Appearance
          _buildSectionHeader('Appearance'),
          _buildSettingsTile(
            icon: Icons.dark_mode_outlined,
            title: 'Theme',
            subtitle: 'Dark (Netflix Style)',
            trailing: null,
          ),
          _buildSettingsTile(
            icon: Icons.auto_awesome_outlined,
            title: 'Animations',
            subtitle: animationsEnabled ? 'Enabled' : 'Disabled',
            trailing: Switch(
              value: animationsEnabled,
              onChanged: (_) {
                ref.read(animationsEnabledProvider.notifier).toggle();
              },
              activeColor: NivioTheme.netflixRed,
            ),
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // About
          _buildSectionHeader('About'),
          _buildSettingsTile(
            icon: Icons.info_outline,
            title: 'App Version',
            subtitle: '1.0.0',
            trailing: null,
          ),
          _buildSettingsTile(
            icon: Icons.policy_outlined,
            title: 'Privacy Policy',
            subtitle: 'View privacy policy',
            trailing: const Icon(Icons.open_in_new, color: Colors.white70),
            onTap: () async {
              final uri = Uri.parse('https://nivio-app.com/privacy');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
          _buildSettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            subtitle: 'View terms of service',
            trailing: const Icon(Icons.open_in_new, color: Colors.white70),
            onTap: () async {
              final uri = Uri.parse('https://nivio-app.com/terms');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
          ),
          const Divider(color: NivioTheme.netflixDarkGrey, height: 1),

          // Sign Out
          _buildSectionHeader('Account Actions'),
          _buildSettingsTile(
            icon: Icons.logout,
            title: 'Sign Out',
            subtitle: 'Sign out of your account',
            trailing: const Icon(Icons.chevron_right, color: Colors.white70),
            onTap: () {
              _showSignOutDialog(context);
            },
            textColor: NivioTheme.netflixRed,
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  String _getSignInMethod(User? user) {
    if (user == null) return 'Not signed in';
    
    // Check if user is anonymous
    if (user.isAnonymous) return 'Guest Mode';
    
    // Check provider data for actual sign-in method
    if (user.providerData.isEmpty) return 'Anonymous';
    
    // Get the first provider
    final provider = user.providerData.first.providerId;
    switch (provider) {
      case 'google.com':
        return 'Google';
      case 'facebook.com':
        return 'Facebook';
      case 'twitter.com':
        return 'Twitter';
      case 'apple.com':
        return 'Apple';
      case 'password':
        return 'Email/Password';
      default:
        return provider;
    }
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? textColor,
  }) {
    return ListTile(
      leading: Icon(
        icon,
        color: textColor ?? Colors.white,
        size: 28,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ?? Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 13,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  void _showClearHistoryDialog(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        title: const Text(
          'Clear Watch History?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will remove all your watch history data. This action cannot be undone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () async {
              // Use the service to clear history (local + cloud)
              final historyService = ref.read(watchHistoryServiceProvider);
              await historyService.clearAllHistory();
              
              // Invalidate the provider to refresh UI
              ref.invalidate(continueWatchingProvider);
              
              if (dialogContext.mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Watch history cleared successfully'),
                    backgroundColor: NivioTheme.netflixRed,
                  ),
                );
              }
            },
            child: const Text(
              'Clear',
              style: TextStyle(color: NivioTheme.netflixRed),
            ),
          ),
        ],
      ),
    );
  }

  void _showPlaybackSpeedDialog(BuildContext context, WidgetRef ref) {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        title: const Text(
          'Playback Speed',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: speeds.map((speed) {
            final currentSpeed = ref.read(playbackSpeedProvider);
            return RadioListTile<double>(
              value: speed,
              groupValue: currentSpeed,
              activeColor: NivioTheme.netflixRed,
              title: Text(
                '${speed}x',
                style: const TextStyle(color: Colors.white),
              ),
              onChanged: (value) {
                if (value != null) {
                  ref.read(playbackSpeedProvider.notifier).setSpeed(value);
                  Navigator.pop(dialogContext);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showVideoQualityDialog(BuildContext context, WidgetRef ref) {
    final qualities = [
      {'value': 'auto', 'label': 'Auto (Best Available)'},
      {'value': '2160p', 'label': '4K (2160p)'},
      {'value': '1080p', 'label': 'Full HD (1080p)'},
      {'value': '720p', 'label': 'HD (720p)'},
      {'value': '480p', 'label': 'SD (480p)'},
    ];
    
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        title: const Text(
          'Video Quality',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: qualities.map((quality) {
            final currentQuality = ref.read(videoQualityProvider);
            return RadioListTile<String>(
              value: quality['value']!,
              groupValue: currentQuality,
              activeColor: NivioTheme.netflixRed,
              title: Text(
                quality['label']!,
                style: const TextStyle(color: Colors.white),
              ),
              onChanged: (value) {
                if (value != null) {
                  ref.read(videoQualityProvider.notifier).setQuality(value);
                  Navigator.pop(dialogContext);
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showSignOutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        title: const Text(
          'Sign Out?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to sign out?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pop(context);
                context.go('/');
              }
            },
            child: const Text(
              'Sign Out',
              style: TextStyle(color: NivioTheme.netflixRed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageToggle({
    required BuildContext context,
    required WidgetRef ref,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        title: Text(
          title,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.white.withOpacity(0.6),
            fontSize: 13,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFFE50914),
        activeTrackColor: const Color(0xFFE50914).withOpacity(0.5),
      ),
    );
  }
}
