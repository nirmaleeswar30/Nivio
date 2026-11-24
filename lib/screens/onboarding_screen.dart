import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/settings_providers.dart';
import 'package:nivio/widgets/stream_surfaces.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
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

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.userId,
    required this.destination,
    this.preview = false,
  });

  final String userId;
  final String destination;
  final bool preview;

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  static const _steps = [
    (
      'Sources',
      'Choose your sources',
      'Set your source priority for movies, shows, and anime.',
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

  static const _icons = [
    PhosphorIconsRegular.stack,
    PhosphorIconsRegular.playCircle,
    PhosphorIconsRegular.link,
    PhosphorIconsRegular.usersThree,
  ];

  late final _light = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 15),
    value: .14,
  );
  final _pages = PageController();
  var _step = 0;
  var _finishing = false;

  @override
  void dispose() {
    _light.dispose();
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_finishing) return;
    if (widget.preview) {
      if (context.canPop()) {
        context.pop();
      } else {
        context.go(widget.destination);
      }
      return;
    }
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
      _goToStep(_step + 1);
    }
  }

  void _goToStep(int step) {
    if (!_pages.hasClients || _finishing) return;
    HapticFeedback.selectionClick();
    if (!ref.read(animationsEnabledProvider) ||
        MediaQuery.disableAnimationsOf(context)) {
      _pages.jumpToPage(step);
      return;
    }
    _pages.animateToPage(
      step,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = NivioTheme.themeColorsOf(context);
    final animate =
        ref.watch(animationsEnabledProvider) &&
        !MediaQuery.disableAnimationsOf(context);
    if (animate && !_light.isAnimating) _light.repeat();
    if (!animate && _light.isAnimating) _light.stop();

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _OnboardingLights(_light, palette)),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 820;
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 32 : 16,
                        8,
                        wide ? 32 : 16,
                        12,
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Image.asset(
                                'assets/images/nivio-wordmark.png',
                                width: 88,
                                height: 36,
                                fit: BoxFit.contain,
                                semanticLabel: 'Nivio',
                              ),
                              const Spacer(),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: palette.textSecondary,
                                ),
                                onPressed: _finishing ? null : _finish,
                                child: const Text('Skip setup'),
                              ),
                            ],
                          ),
                          if (!wide) _mobileProgress(palette),
                          const SizedBox(height: 12),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (wide) ...[
                                  SizedBox(
                                    width: 220,
                                    child: _stepRail(palette),
                                  ),
                                  const SizedBox(width: 24),
                                ],
                                Expanded(
                                  child: Column(
                                    children: [
                                      Expanded(
                                        child: PageView.builder(
                                          controller: _pages,
                                          physics: _finishing
                                              ? const NeverScrollableScrollPhysics()
                                              : null,
                                          onPageChanged: (step) =>
                                              setState(() => _step = step),
                                          itemCount: _steps.length,
                                          itemBuilder: (context, step) =>
                                              _stepContent(step, wide, palette),
                                        ),
                                      ),
                                      Divider(height: 1, color: palette.border),
                                      _controls(palette),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileProgress(NivioThemeColors palette) => Padding(
    padding: const EdgeInsets.only(top: 9, left: 2, right: 2),
    child: Semantics(
      label: '${_steps[_step].$1}, step ${_step + 1} of ${_steps.length}',
      child: Row(
        children: [
          for (var i = 0; i < _steps.length; i++)
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i == _steps.length - 1 ? 0 : 5),
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    color: i <= _step
                        ? palette.primary
                        : palette.textPrimary.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Widget _stepRail(NivioThemeColors palette) => StreamPanel(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StreamSectionLabel('SET UP NIVIO'),
        const SizedBox(height: 12),
        for (var i = 0; i < _steps.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                StreamGlyph(
                  i < _step ? PhosphorIconsRegular.check : _icons[i],
                  active: i == _step,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _steps[i].$1,
                    style: TextStyle(
                      color: i == _step
                          ? palette.textPrimary
                          : palette.textSecondary,
                      fontWeight: i == _step
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );

  Widget _stepContent(int step, bool wide, NivioThemeColors palette) {
    final (label, title, description) = _steps[step];
    return ListView(
      key: PageStorageKey(step),
      primary: false,
      padding: EdgeInsets.fromLTRB(
        wide ? 24 : 15,
        wide ? 24 : 16,
        wide ? 24 : 15,
        18,
      ),
      children: [
        Row(
          children: [
            StreamGlyph(_icons[step], active: true, size: 38),
            const SizedBox(width: 10),
            StreamSectionLabel(label.toUpperCase()),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: palette.textPrimary,
            fontWeight: FontWeight.w800,
            height: 1.12,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          description,
          style: TextStyle(color: palette.textSecondary, height: 1.4),
        ),
        const SizedBox(height: 20),
        switch (step) {
          0 => const StreamSourceSettings(),
          1 => const StreamPlaybackSettings(),
          2 => const ProfileScreen(connectionsOnly: true),
          _ => const _WatchPartyIntro(),
        },
      ],
    );
  }

  Widget _controls(NivioThemeColors palette) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: Row(
      children: [
        if (_step > 0)
          IconButton(
            tooltip: 'Previous step',
            icon: const Icon(PhosphorIconsRegular.caretLeft),
            onPressed: _finishing ? null : () => _goToStep(_step - 1),
          ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: palette.textSecondary,
                  ),
                  onPressed: _finishing ? null : _next,
                  child: const Text(
                    'Skip this step',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    foregroundColor: palette.primary.computeLuminance() >= .18
                        ? const Color(0xFF111318)
                        : Colors.white,
                  ),
                  onPressed: _finishing ? null : _next,
                  child: Text(
                    _step == _steps.length - 1 ? 'Finish setup' : 'Continue',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _OnboardingLights extends CustomPainter {
  _OnboardingLights(this.motion, this.palette) : super(repaint: motion);

  final Animation<double> motion;
  final NivioThemeColors palette;

  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.value * math.pi * 2;
    final bounds = Offset.zero & size;
    final secondary = Color.lerp(
      palette.surfaceContainer,
      palette.secondary,
      .60,
    )!;
    final lights = [
      (palette.primary, .12 + .25 * math.sin(t), .23 + .25 * math.cos(t), .34),
      (
        secondary,
        .88 + .17 * math.cos(t + 1.1),
        .47 + .31 * math.sin(t + 1.1),
        .46,
      ),
      (
        palette.primary,
        .62 + .29 * math.cos(t + 2.7),
        .94 + .15 * math.sin(t + 2.7),
        .22,
      ),
    ];
    for (final (color, x, y, opacity) in lights) {
      final shader = RadialGradient(
        center: Alignment(x * 2 - 1, y * 2 - 1),
        radius: .85,
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: 0),
        ],
      ).createShader(bounds);
      canvas.drawRect(bounds, Paint()..shader = shader);
    }
  }

  @override
  bool shouldRepaint(_OnboardingLights oldDelegate) =>
      oldDelegate.palette != palette || oldDelegate.motion != motion;
}

class _WatchPartyIntro extends StatelessWidget {
  const _WatchPartyIntro();

  @override
  Widget build(BuildContext context) => Column(
    children: [
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
