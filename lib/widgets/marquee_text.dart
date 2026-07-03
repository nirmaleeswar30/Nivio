import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double blankSpace;
  final double velocity;
  final Duration pauseAfterRound;
  final CrossAxisAlignment crossAxisAlignment;

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.blankSpace = 30.0,
    this.velocity = 30.0,
    this.pauseAfterRound = const Duration(seconds: 2),
    this.crossAxisAlignment = CrossAxisAlignment.start,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> {
  late ScrollController _scrollController;
  bool _isScrolling = false;
  double _currentScrollDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startScrolling();
    });
  }

  @override
  void dispose() {
    _isScrolling = false;
    _scrollController.dispose();
    super.dispose();
  }

  void _startScrolling() async {
    _isScrolling = true;
    while (_isScrolling && mounted) {
      await Future.delayed(widget.pauseAfterRound);
      if (!_isScrolling || !mounted) break;
      
      if (_scrollController.hasClients && _currentScrollDistance > 0) {
        final int durationMs = (_currentScrollDistance / widget.velocity * 1000).toInt();
        
        await _scrollController.animateTo(
          _currentScrollDistance,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.linear,
        );
        
        if (!_isScrolling || !mounted) break;
        
        // Jump back to start immediately for continuous effect
        _scrollController.jumpTo(0.0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final textStyle = widget.style ?? DefaultTextStyle.of(context).style;
        final textPainter = TextPainter(
          text: TextSpan(text: widget.text, style: textStyle),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: double.infinity);

        if (textPainter.size.width > constraints.maxWidth) {
          _currentScrollDistance = textPainter.size.width + widget.blankSpace;
          
          return SizedBox(
            height: textPainter.size.height,
            child: SingleChildScrollView(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              child: Row(
                children: [
                  Text(widget.text, style: textStyle),
                  SizedBox(width: widget.blankSpace),
                  Text(widget.text, style: textStyle),
                  SizedBox(width: constraints.maxWidth), // Extra padding to fill the rest of the screen after the second text
                ],
              ),
            ),
          );
        } else {
          return Text(
            widget.text,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }
      },
    );
  }
}
