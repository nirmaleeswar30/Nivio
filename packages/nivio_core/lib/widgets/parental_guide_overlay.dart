import 'package:flutter/material.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/services/parental_guide_service.dart';

// Adapted for Nivio from NuvioMobile's GPL-3.0 parental guide overlay.
// https://github.com/NuvioMedia/NuvioMobile/blob/0d20af832d381e5ab3a385deccfbc47c12b93bf1/composeApp/src/commonMain/kotlin/com/nuvio/app/features/player/ParentalGuideOverlay.kt
class ParentalGuideOverlay extends StatefulWidget {
  const ParentalGuideOverlay({
    super.key,
    required this.warnings,
    required this.playing,
    required this.canShow,
    required this.animate,
  });

  final List<ParentalWarning> warnings;
  final bool playing;
  final bool canShow;
  final bool animate;

  @override
  State<ParentalGuideOverlay> createState() => _ParentalGuideOverlayState();
}

class _ParentalGuideOverlayState extends State<ParentalGuideOverlay>
    with SingleTickerProviderStateMixin {
  static const _rowHeight = 18.0;
  static const _rowGap = 2.0;
  static const _hold = 5000;
  late final AnimationController _animation;
  List<ParentalWarning> _warnings = const [];
  bool _animate = true;

  int get _fadeOutStart => 700 + _warnings.length * 280 + _hold;
  int get _lineRetractStart => _fadeOutStart + _warnings.length * 210 + 100;
  int get _total => _animate ? _lineRetractStart + 700 : _hold;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(
      vsync: this,
      animationBehavior: AnimationBehavior.preserve,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updatePlayback();
  }

  @override
  void didUpdateWidget(ParentalGuideOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updatePlayback();
  }

  void _updatePlayback() {
    if (!widget.canShow) {
      // A source change or PiP interrupts the sequence for this episode.
      if (_animation.isAnimating) _animation.value = 1;
      return;
    }
    if (_warnings.isNotEmpty || widget.warnings.isEmpty || !widget.playing) {
      return;
    }
    _warnings = widget.warnings;
    _animate = widget.animate && !MediaQuery.disableAnimationsOf(context);
    _animation.duration = Duration(milliseconds: _total);
    _animation.forward();
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_warnings.isEmpty || !widget.canShow) return const SizedBox.shrink();

    final accent = NivioTheme.accentColorOf(context);
    final rowHeight =
        _rowHeight +
        (MediaQuery.textScalerOf(context).scale(11) - 11).clamp(
          0.0,
          double.infinity,
        );
    final fullHeight = _warnings.length * (rowHeight + _rowGap) - _rowGap;
    final base =
        Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: 11,
          decoration: TextDecoration.none,
        ) ??
        const TextStyle(fontSize: 11, decoration: TextDecoration.none);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        if (_animation.value == 1) return const SizedBox.shrink();
        final elapsed = _animation.value * _total;
        double fade(int start, int duration) => Curves.fastOutSlowIn.transform(
          ((elapsed - start) / duration).clamp(0.0, 1.0),
        );
        final opacity = _animate
            ? fade(0, 300) * (1 - fade(_lineRetractStart + 500, 200))
            : 1.0;
        final line = _animate
            ? fade(300, 400) * (1 - fade(_lineRetractStart, 300))
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('parental-guide-accent'),
                width: 3,
                height: fullHeight * line,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  spacing: _rowGap,
                  children: [
                    for (final (index, warning) in _warnings.indexed)
                      Opacity(
                        opacity: _animate
                            ? fade(780 + index * 280, 200) *
                                  (1 -
                                      fade(
                                        _fadeOutStart +
                                            (_warnings.length - 1 - index) *
                                                210 +
                                            60,
                                        150,
                                      ))
                            : 1,
                        child: SizedBox(
                          height: rowHeight,
                          child: Align(
                            widthFactor: 1,
                            alignment: AlignmentDirectional.centerStart,
                            child: Text.rich(
                              TextSpan(
                                style: base,
                                children: [
                                  TextSpan(
                                    text: warning.label,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white.withValues(
                                        alpha: .85,
                                      ),
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' · ',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .4),
                                    ),
                                  ),
                                  TextSpan(
                                    text: warning.severity,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: .5),
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
