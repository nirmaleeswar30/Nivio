import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Floating real-time "Stats for Nerds" overlay for mpv playback inspection.
class PlayerStatsOverlay extends StatefulWidget {
  final Player player;
  final int? doviProfile;
  final bool isHdr;
  final VoidCallback? onClose;

  const PlayerStatsOverlay({
    super.key,
    required this.player,
    this.doviProfile,
    this.isHdr = false,
    this.onClose,
  });

  @override
  State<PlayerStatsOverlay> createState() => _PlayerStatsOverlayState();
}

class _PlayerStatsOverlayState extends State<PlayerStatsOverlay> {
  Timer? _timer;
  Map<String, String> _stats = {};
  bool _minimized = false;

  NativePlayer? get _mpv {
    final p = widget.player.platform;
    return p is NativePlayer ? p : null;
  }

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _timer = Timer.periodic(const Duration(milliseconds: 300), (_) => _fetchStats());
    // Also try to invoke mpv's internal stats.lua toggle if supported on the current VO
    try {
      _mpv?.command(['script-binding', 'stats/display-stats-toggle']);
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStats() async {
    final mpv = _mpv;
    if (mpv == null || !mounted) return;

    try {
      const keys = [
        'current-vo',
        'hwdec-current',
        'estimated-vf-fps',
        'container-fps',
        'video-fps',
        'vo-drop-frame-count',
        'frame-drop-count',
        'dwidth',
        'dheight',
        'video-codec',
        'video-format',
        'video-params/colormatrix',
        'video-params/gamma',
        'video-params/primaries',
        'avsync',
        'paused-for-cache',
        'core-idle',
        'time-pos',
      ];

      final results = <String, String>{};
      for (final k in keys) {
        try {
          results[k] = await mpv.getProperty(k);
        } catch (_) {
          results[k] = '';
        }
      }

      if (mounted) {
        setState(() => _stats = results);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_minimized) {
      return Positioned(
        top: 60,
        left: 20,
        child: GestureDetector(
          onTap: () => setState(() => _minimized = false),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.75),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.analytics_outlined, size: 14, color: Colors.greenAccent),
                SizedBox(width: 4),
                Text('STATS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
    }

    final vo = _stats['current-vo'] ?? 'loading...';
    final hwdec = _stats['hwdec-current'] ?? 'none';
    final fps = _stats['estimated-vf-fps']?.trim() ?? '';
    final containerFps = _stats['container-fps']?.trim() ?? '';
    final voDrops = _stats['vo-drop-frame-count'] ?? '0';
    final frameDrops = _stats['frame-drop-count'] ?? '0';
    final w = _stats['dwidth'] ?? '';
    final h = _stats['dheight'] ?? '';
    final codec = _stats['video-codec'] ?? '';
    final matrix = _stats['video-params/colormatrix'] ?? '';
    final gamma = _stats['video-params/gamma'] ?? '';
    final primaries = _stats['video-params/primaries'] ?? '';
    final avsync = _stats['avsync'] ?? '';
    final isBuffering = _stats['paused-for-cache'] == 'yes';

    final String dvText;
    if (widget.doviProfile != null) {
      final sub = widget.doviProfile == 8 ? '8.1' : '${widget.doviProfile}';
      dvText = vo == 'gpu-next' ? 'HDR10 (DV P$sub Base)' : 'Dolby Vision P$sub';
    } else {
      dvText = widget.isHdr ? 'HDR' : 'SDR';
    }

    return Positioned(
      top: 60,
      left: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.85),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.greenAccent.withOpacity(0.5)),
            boxShadow: const [
              BoxShadow(color: Colors.black54, blurRadius: 8),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.analytics_outlined, size: 14, color: Colors.greenAccent),
                      SizedBox(width: 6),
                      Text(
                        'STATS FOR NERDS',
                        style: TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: () => setState(() => _minimized = true),
                        child: const Icon(Icons.remove, size: 16, color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      if (widget.onClose != null)
                        GestureDetector(
                          onTap: widget.onClose,
                          child: const Icon(Icons.close, size: 16, color: Colors.white70),
                        ),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white12, height: 12),
              _statRow('VO Driver', vo, isHighlight: true),
              _statRow('Hardware Dec', hwdec),
              _statRow('Video FPS', '${fps.isNotEmpty ? fps : (containerFps.isNotEmpty ? containerFps : '--')} fps'),
              _statRow('Dropped Frames', '$voDrops (VO) / $frameDrops (Dec)', isWarning: voDrops != '0' || frameDrops != '0'),
              _statRow('Resolution', w.isNotEmpty ? '${w}x$h ($codec)' : '--'),
              _statRow('Format', dvText, isAccent: widget.doviProfile != null),
              _statRow('Colorspace', matrix.isNotEmpty ? '$gamma / $primaries' : '--'),
              _statRow('A/V Sync', avsync.isNotEmpty ? '$avsync s' : '--'),
              _statRow('Buffering', isBuffering ? 'YES (paused for cache)' : 'No', isWarning: isBuffering),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, {bool isHighlight = false, bool isAccent = false, bool isWarning = false}) {
    Color valColor = Colors.white;
    if (isHighlight) valColor = Colors.cyanAccent;
    if (isAccent) valColor = Colors.amberAccent;
    if (isWarning) valColor = Colors.redAccent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white60, fontSize: 10, fontFamily: 'monospace')),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: valColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
