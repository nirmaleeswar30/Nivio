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
    _updateTimeLeft();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _updateTimeLeft();
        });
      }
    });
  }

  void _updateTimeLeft() {
    final now = DateTime.now();
    if (widget.targetDate.isAfter(now)) {
      _timeLeft = widget.targetDate.difference(now);
    } else {
      _timeLeft = Duration.zero;
      _timer?.cancel();
    }
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
