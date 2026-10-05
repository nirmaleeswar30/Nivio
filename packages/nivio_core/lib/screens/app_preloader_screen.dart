import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';

/// Kinetic Brand Preloader for Nivio
/// 
/// Features:
/// - Amber & Crimson ribbons gliding in from diagonal corners (Curves.easeOutBack)
/// - Exact contact-point snap with tactile HapticFeedback
/// - Staggered dual brand echo waves (Amber #F98F05 + Crimson #F80201) with zero white aura
/// - 360° omnidirectional radial ember sparks
/// - Smooth official Nivio wordmark elevation reveal
/// - Seamless camera zoom-through transition into app shell
/// - High-fidelity MPEG brand audio stinger playback via media_kit
class AppPreloaderScreen extends StatefulWidget {
  final VoidCallback? onComplete;

  const AppPreloaderScreen({super.key, this.onComplete});

  @override
  State<AppPreloaderScreen> createState() => _AppPreloaderScreenState();
}

class _AppPreloaderScreenState extends State<AppPreloaderScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Player? _audioPlayer;
  bool _audioDisposed = false;

  // Ribbon slide & intro fade
  late final Animation<Offset> _orangeSlide;
  late final Animation<Offset> _redSlide;
  late final Animation<double> _ribbonFade;

  // Echo waves & sparks
  late final Animation<double> _waveProgress;
  late final Animation<double> _sparkProgress;

  // Wordmark reveal
  late final Animation<Offset> _wordmarkSlide;
  late final Animation<double> _wordmarkFade;

  // Exit transition
  late final Animation<double> _exitScale;
  late final Animation<double> _exitFade;

  bool _hasTriggeredImpact = false;
  late final List<_SparkParticle> _particles;

  @override
  void initState() {
    super.initState();

    // 0. Trigger brand audio stinger
    _initAndPlayAudio();

    // 1. Generate 18 organically distributed radial ember sparks
    final random = math.Random(1337);
    _particles = List.generate(18, (i) {
      final isOrange = i % 2 == 0;
      final baseAngle = (i / 18) * 2 * math.pi;
      final jitter = (random.nextDouble() * 0.35 - 0.175);
      return _SparkParticle(
        angle: baseAngle + jitter,
        distance: 40.0 + random.nextDouble() * 65.0,
        size: 2.2 + random.nextDouble() * 1.8,
        color: isOrange ? const Color(0xFFF98F05) : const Color(0xFFF80201),
      );
    });

    // 2. Main choreography controller (Total: ~1550ms)
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1550),
    );

    // Ribbons accelerate inward (0ms - 680ms)
    _orangeSlide = Tween<Offset>(
      begin: const Offset(-0.85, -0.75),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.44, curve: Curves.easeOutBack),
    ));

    _redSlide = Tween<Offset>(
      begin: const Offset(0.85, 0.75),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.44, curve: Curves.easeOutBack),
    ));

    _ribbonFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.20, curve: Curves.easeIn),
    ));

    // Staggered echo wave expansion (680ms - 1100ms)
    _waveProgress = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.44, 0.72, curve: Curves.easeOutCubic),
    ));

    // 360° sparks burst (680ms - 1050ms)
    _sparkProgress = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.44, 0.68, curve: Curves.easeOutQuad),
    ));

    // Nivio official wordmark elevation (900ms - 1250ms)
    _wordmarkSlide = Tween<Offset>(
      begin: const Offset(0, 0.35),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.58, 0.80, curve: Curves.easeOutCubic),
    ));

    _wordmarkFade = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.58, 0.80, curve: Curves.easeIn),
    ));

    // Exit zoom-through camera transition (1320ms - 1550ms)
    _exitScale = Tween<double>(begin: 1.0, end: 22.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.85, 1.0, curve: Curves.easeInCubic),
    ));

    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.88, 1.0, curve: Curves.easeOut),
    ));

    // 3. Impact trigger listener (at 0.44 = ~680ms)
    _controller.addListener(() {
      if (_controller.value >= 0.44 && !_hasTriggeredImpact) {
        _hasTriggeredImpact = true;
        _triggerImpactHaptics();
      }
    });

    // 4. On sequence completion, route to destination
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateForward();
      }
    });

    // Start playback immediately on first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  void _triggerImpactHaptics() {
    // Primary punch: immediate heavy impact + vibration impulse for deep physical presence
    HapticFeedback.heavyImpact();
    HapticFeedback.vibrate();

    // Rebound snap: staggered pulse matching the secondary crimson echo wave
    Future.delayed(const Duration(milliseconds: 65), () {
      HapticFeedback.heavyImpact();
    });
  }

  Future<void> _initAndPlayAudio() async {
    try {
      final player = Player();
      _audioPlayer = player;

      void safeDispose() {
        if (!_audioDisposed) {
          _audioDisposed = true;
          player.dispose();
          if (_audioPlayer == player) {
            _audioPlayer = null;
          }
        }
      }

      // Auto-cleanup when playback completes or safety timeout at 4.5 seconds
      player.stream.completed.listen((completed) {
        if (completed) {
          safeDispose();
        }
      });
      Future.delayed(const Duration(milliseconds: 4500), safeDispose);

      await player.open(
        Media('asset:///assets/nivio-preload.mpeg'),
        play: true,
      );
    } catch (e) {
      debugPrint('[AppPreloaderScreen] Preload audio stinger error: $e');
    }
  }

  void _navigateForward() {
    if (widget.onComplete != null) {
      widget.onComplete!();
      return;
    }

    if (!mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    final targetRoute = user != null ? '/home' : '/auth';
    context.go(targetRoute);
  }

  @override
  void dispose() {
    _controller.dispose();
    if (!_controller.isCompleted) {
      // If sequence was aborted early, stop audio immediately
      if (!_audioDisposed) {
        _audioDisposed = true;
        _audioPlayer?.dispose();
        _audioPlayer = null;
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF05070B),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Center(
            child: FadeTransition(
              opacity: _exitFade,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Scalable Logo + VFX Group
                  Transform.scale(
                    scale: _exitScale.value,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 176,
                      height: 176,
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          // 1. Anchored Staggered Echo Waves & 360° Sparks
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _EchoWavesAndSparksPainter(
                                waveProgress: _waveProgress.value,
                                sparkProgress: _sparkProgress.value,
                                particles: _particles,
                              ),
                            ),
                          ),

                          // 2. Amber Top-Left Ribbon
                          Positioned.fill(
                            child: FadeTransition(
                              opacity: _ribbonFade,
                              child: SlideTransition(
                                position: _orangeSlide,
                                child: Image.asset(
                                  'assets/images/preloader_orange.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),

                          // 3. Crimson Bottom-Right Ribbon
                          Positioned.fill(
                            child: FadeTransition(
                              opacity: _ribbonFade,
                              child: SlideTransition(
                                position: _redSlide,
                                child: Image.asset(
                                  'assets/images/preloader_red.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 4. Official Nivio Wordmark Elevation
                  FadeTransition(
                    opacity: _wordmarkFade,
                    child: SlideTransition(
                      position: _wordmarkSlide,
                      child: Image.asset(
                        'assets/images/nivio-wordmark.png',
                        height: 60,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SparkParticle {
  final double angle;
  final double distance;
  final double size;
  final Color color;

  const _SparkParticle({
    required this.angle,
    required this.distance,
    required this.size,
    required this.color,
  });
}

class _EchoWavesAndSparksPainter extends CustomPainter {
  final double waveProgress;
  final double sparkProgress;
  final List<_SparkParticle> particles;

  const _EchoWavesAndSparksPainter({
    required this.waveProgress,
    required this.sparkProgress,
    required this.particles,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Staggered Dual Echo Waves (Pure Amber #F98F05 + Crimson #F80201 - Zero white)
    if (waveProgress > 0.0 && waveProgress < 1.0) {
      final baseRadius = 16.0 + (waveProgress * 155.0);
      final fade = (1.0 - waveProgress).clamp(0.0, 1.0);

      // Outer Echo Wave: Amber Orange (#F98F05)
      final outerRadius = baseRadius * 1.08;
      final outerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8 * (1.0 - waveProgress * 0.4)
        ..color = const Color(0xFFF98F05).withOpacity(fade * 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.5);
      canvas.drawCircle(center, outerRadius, outerPaint);

      // Inner Echo Wave: Crimson Red (#F80201)
      final innerRadius = baseRadius * 0.88;
      final innerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8 * (1.0 - waveProgress * 0.4)
        ..color = const Color(0xFFF80201).withOpacity(fade * 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3.5);
      canvas.drawCircle(center, innerRadius, innerPaint);
    }

    // 360-Degree Radial Ember Sparks
    if (sparkProgress > 0.0 && sparkProgress < 1.0) {
      final sparkOpacity = (1.0 - sparkProgress).clamp(0.0, 1.0);

      for (final p in particles) {
        final curDist = p.distance * Curves.easeOutCubic.transform(sparkProgress);
        final sparkCenter = Offset(
          center.dx + math.cos(p.angle) * curDist,
          center.dy + math.sin(p.angle) * curDist,
        );

        final sparkPaint = Paint()
          ..style = PaintingStyle.fill
          ..color = p.color.withOpacity(sparkOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2.0);

        canvas.drawCircle(
          sparkCenter,
          p.size * (1.0 - sparkProgress * 0.4),
          sparkPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _EchoWavesAndSparksPainter oldDelegate) {
    return oldDelegate.waveProgress != waveProgress ||
        oldDelegate.sparkProgress != sparkProgress;
  }
}
