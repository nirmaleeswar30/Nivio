import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rqbit_ffi/rqbit_ffi.dart';

import '../services/torrent/torrent_stream_service.dart';

/// A compact, self-contained badge that shows live P2P stats (download speed,
/// peers, buffered %) for the active "Nivio Torrents" stream. Polls the engine
/// directly and hides itself when there's nothing to show.
class TorrentStatsOverlay extends StatefulWidget {
  const TorrentStatsOverlay({
    super.key,
    required this.service,
    this.pollInterval = const Duration(milliseconds: 1500),
  });

  final TorrentStreamService service;
  final Duration pollInterval;

  @override
  State<TorrentStatsOverlay> createState() => _TorrentStatsOverlayState();
}

class _TorrentStatsOverlayState extends State<TorrentStatsOverlay> {
  Timer? _timer;
  TorrentStats? _stats;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(widget.pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final s = await widget.service.activeStats();
    if (mounted) setState(() => _stats = s);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = _stats;
    if (s == null || !widget.service.hasActive) {
      return const SizedBox.shrink();
    }

    final peers = s.peers?.live ?? 0;
    final connecting = s.peers?.connecting ?? 0;
    final speed = s.downloadMbps;
    final pct = (s.progressFraction * 100).clamp(0, 100);
    final isBuffering = s.state != 'live' || (peers == 0 && !s.finished);

    return Material(
      color: Colors.white24,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isBuffering ? Icons.hourglass_top_rounded : Icons.bolt_rounded,
              size: 14,
              color: isBuffering ? Colors.amberAccent : Colors.tealAccent,
            ),
            const SizedBox(width: 6),
            Text(
              '${speed.toStringAsFixed(1)} MB/s',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            _dot(),
            Icon(Icons.people_alt_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              connecting > 0 ? '$peers (+$connecting)' : '$peers',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
            _dot(),
            Text(
              '${pct.toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Container(
          width: 3,
          height: 3,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.4),
            shape: BoxShape.circle,
          ),
        ),
      );
}
