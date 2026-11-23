import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'profile_screen.dart';
import 'stream_selection_screen.dart';

String _completionKey(String userId) => 'onboarding_completed_$userId';

Future<bool> hasCompletedOnboarding(String userId) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_completionKey(userId)) ?? false;
}

String onboardingDestination(String? raw) {
  final uri = raw == null ? null : Uri.tryParse(raw);
  if (uri == null ||
      uri.hasScheme ||
      uri.hasAuthority ||
      !uri.path.startsWith('/') ||
      uri.path.startsWith('//') ||
      const {'/', '/auth', '/onboarding', '/splash'}.contains(uri.path)) {
    return '/home';
  }
  return uri.toString();
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.userId,
    required this.destination,
  });

  final String userId;
  final String destination;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _steps = [
    (
      'Sources',
      'Choose your sources',
      'Use Nivio’s built-in sources or add your own extensions.',
    ),
    (
      'Playback',
      'Set your playback preferences',
      'Choose how Play works and which qualities Nivio should look for.',
    ),
    (
      'Connections',
      'Connect your accounts',
      'Share your activity on Discord or sync watch progress with a tracking service.',
    ),
    (
      'Watch Party',
      'Watch together',
      'Start a Watch Party with friends and keep playback in sync.',
    ),
  ];

  var _step = 0;
  var _finishing = false;

  Future<void> _finish() async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(_completionKey(widget.userId), true)) {
        throw StateError('Couldn’t save setup completion.');
      }
      if (mounted) context.go(widget.destination);
    } catch (_) {
      if (!mounted) return;
      setState(() => _finishing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couldn’t finish setup. Try again.')),
      );
    }
  }

  void _next() {
    if (_step == _steps.length - 1) {
      _finish();
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final (label, title, description) = _steps[_step];
    final isLast = _step == _steps.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up Nivio'),
        automaticallyImplyLeading: false,
        leading: _step == 0
            ? null
            : IconButton(
                tooltip: 'Previous step',
                icon: const Icon(Icons.arrow_back),
                onPressed: _finishing ? null : () => setState(() => _step--),
              ),
        actions: [
          TextButton(
            onPressed: _finishing ? null : _finish,
            child: const Text('Skip setup'),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    key: ValueKey(_step),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [
                      Text(
                        '$label · ${_step + 1} of ${_steps.length}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(
                        value: (_step + 1) / _steps.length,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        title,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        description,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 16),
                      switch (_step) {
                        0 => const StreamSourceSettings(),
                        1 => const StreamPlaybackSettings(),
                        2 => const ProfileScreen(connectionsOnly: true),
                        _ => const _WatchPartyIntro(),
                      },
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _finishing ? null : _next,
                        child: const Text('Skip this step'),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: FilledButton(
                          onPressed: _finishing ? null : _next,
                          child: Text(isLast ? 'Finish setup' : 'Continue'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WatchPartyIntro extends StatelessWidget {
  const _WatchPartyIntro();

  @override
  Widget build(BuildContext context) => Column(
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.asset(
          'assets/images/watch-party.jpg',
          fit: BoxFit.contain,
          semanticLabel: 'Nivio Watch Party screen',
        ),
      ),
      const SizedBox(height: 12),
      const ListTile(
        leading: Icon(Icons.group_outlined),
        title: Text('Start or join from Watch Party'),
        subtitle: Text(
          'Create a room and share its invite link, or enter a room code from a friend.',
        ),
      ),
      const ListTile(
        leading: Icon(Icons.sync),
        title: Text('Stay in sync'),
        subtitle: Text(
          'The host controls playback. Use chat and reactions while you watch.',
        ),
      ),
    ],
  );
}
