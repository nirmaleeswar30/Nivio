import 'dart:async';
import 'package:flutter/material.dart';

class CountdownTimerWidget extends StatefulWidget {
  final DateTime targetDate;
  final TextStyle? textStyle;
  final Widget Function(BuildContext context, String timeString)? builder;

  const CountdownTimerWidget({
    super.key,
    required this.targetDate,
    this.textStyle,
    this.builder,
  });

  @override
  State<CountdownTimerWidget> createState() => _CountdownTimerWidgetState();
}

class _CountdownTimerWidgetState extends State<CountdownTimerWidget> {
  Timer? _timer;
  late Duration _timeLeft;

  @override
  void initState() {
    super.initState();
    _scheduleNextUpdate();
  }

  void _scheduleNextUpdate() {
    _timer?.cancel();
    final now = DateTime.now();
    _timeLeft = widget.targetDate.isAfter(now) 
        ? widget.targetDate.difference(now) 
        : Duration.zero;

    if (mounted) {
      setState(() {});
    }

    if (_timeLeft <= Duration.zero) return;

    // Calculate precise time until the formatted string will change next
    Duration delayUntilNextUpdate;
    if (_timeLeft.inDays > 0) {
      // Formatted as "Xd Yh", string changes only when hours cross.
      // E.g., when the current minutes and seconds drop to zero.
      final minutes = _timeLeft.inMinutes % 60;
      final seconds = _timeLeft.inSeconds % 60;
      delayUntilNextUpdate = Duration(minutes: minutes, seconds: seconds);
      // If we are exactly on the hour, wait 1 hour for the next change
      if (delayUntilNextUpdate.inSeconds == 0) {
        delayUntilNextUpdate = const Duration(hours: 1);
      }
    } else if (_timeLeft.inHours > 0) {
      // Formatted as "Xh Ym", string changes every minute.
      final seconds = _timeLeft.inSeconds % 60;
      delayUntilNextUpdate = Duration(seconds: seconds);
      if (delayUntilNextUpdate.inSeconds == 0) {
        delayUntilNextUpdate = const Duration(minutes: 1);
      }
    } else {
      // Formatted as "Xm Ys", string changes every second.
      delayUntilNextUpdate = const Duration(seconds: 1);
    }

    // Add a tiny buffer (50ms) to ensure we cross the time boundary safely
    delayUntilNextUpdate += const Duration(milliseconds: 50);

    _timer = Timer(delayUntilNextUpdate, () {
      if (mounted) _scheduleNextUpdate();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    if (d.inSeconds <= 0) return 'Aired';
    if (d.inDays > 0) {
      return 'Airs in ${d.inDays}d ${d.inHours % 24}h';
    }
    if (d.inHours > 0) {
      return 'Airs in ${d.inHours}h ${d.inMinutes % 60}m';
    }
    return 'Airs in ${d.inMinutes}m ${d.inSeconds % 60}s';
  }

  @override
  Widget build(BuildContext context) {
    final timeString = _formatDuration(_timeLeft);

    if (widget.builder != null) {
      return widget.builder!(context, timeString);
    }

    return Text(
      timeString,
      style: widget.textStyle ??
          const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
    );
  }
}
