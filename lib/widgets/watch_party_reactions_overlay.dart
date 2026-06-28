import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';

class WatchPartyReactionsOverlay extends ConsumerStatefulWidget {
  const WatchPartyReactionsOverlay({super.key});

  @override
  ConsumerState<WatchPartyReactionsOverlay> createState() =>
      _WatchPartyReactionsOverlayState();
}

class _FloatingReaction {
  final String id;
  final String emoji;
  final double leftPadding;

  _FloatingReaction({
    required this.id,
    required this.emoji,
    required this.leftPadding,
  });
}

class _WatchPartyReactionsOverlayState
    extends ConsumerState<WatchPartyReactionsOverlay> {
  final List<_FloatingReaction> _reactions = [];
  final Random _random = Random();

  void _addReaction(WatchPartyReaction reaction) {
    final floating = _FloatingReaction(
      id: UniqueKey().toString(),
      emoji: reaction.emoji,
      leftPadding: _random.nextDouble() * 60,
    );
    setState(() {
      _reactions.add(floating);
    });

    // Remove it after the animation finishes (2 seconds)
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _reactions.removeWhere((r) => r.id == floating.id);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<WatchPartyReaction>>(watchPartyReactionsProvider,
        (previous, next) {
      if (next.hasValue && next.value != null) {
        _addReaction(next.value!);
      }
    });

    return IgnorePointer(
      child: Stack(
        children: _reactions.map((r) => _FloatingReactionWidget(reaction: r)).toList(),
      ),
    );
  }
}

class _FloatingReactionWidget extends StatefulWidget {
  final _FloatingReaction reaction;

  const _FloatingReactionWidget({required this.reaction});

  @override
  State<_FloatingReactionWidget> createState() =>
      _FloatingReactionWidgetState();
}

class _FloatingReactionWidgetState extends State<_FloatingReactionWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _positionAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    );

    _positionAnimation = Tween<double>(begin: 0, end: 150).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 20),
    ]).animate(_controller);

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.5, end: 1.2), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.2, end: 1.0), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 60),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Positioned(
          bottom: 100 + _positionAnimation.value,
          right: 320 + widget.reaction.leftPadding, // Left of the chat panel
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Transform.scale(
              scale: _scaleAnimation.value,
              child: Text(
                widget.reaction.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
          ),
        );
      },
    );
  }
}
