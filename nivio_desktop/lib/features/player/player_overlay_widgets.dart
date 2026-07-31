part of 'player_screen.dart';

class _PlayerBufferingOverlay extends StatelessWidget {
  const _PlayerBufferingOverlay();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0x99000000),
            shape: BoxShape.circle,
          ),
          child: Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class _PlayerSwitchingOverlay extends StatelessWidget {
  const _PlayerSwitchingOverlay({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: const Color(0x99000000),
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xE6101010),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.4,
                      ),
                    ),
                    const SizedBox(width: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 320),
                      child: Text(
                        message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SkipOverlay extends StatelessWidget {
  const _SkipOverlay({
    required this.playback,
    required this.skipTimes,
    required this.onSkip,
  });

  final PlaybackState playback;
  final List<SkipTime> skipTimes;
  final ValueChanged<Duration> onSkip;

  @override
  Widget build(BuildContext context) {
    SkipTime? active;
    for (final skip in skipTimes) {
      final type = skip.type.toLowerCase();
      final isSupported =
          type == 'op' ||
          type == 'intro' ||
          type == 'mixed-op' ||
          type == 'ed' ||
          type == 'outro' ||
          type == 'mixed-ed';
      if (isSupported &&
          playback.position >= skip.startTime &&
          playback.position < skip.endTime) {
        active = skip;
        break;
      }
    }
    if (active == null) return const SizedBox.shrink();

    final skip = active;

    final skipType = skip.type.toLowerCase();
    final isOutro =
        skipType == 'ed' || skipType == 'outro' || skipType == 'mixed-ed';
    return Positioned(
      right: AppSpacing.xl,
      bottom: AppSpacing.xl,
      child: FilledButton.icon(
        onPressed: () => onSkip(skip.endTime),
        icon: const Icon(Icons.fast_forward),
        label: Text(isOutro ? 'Skip Outro' : 'Skip Intro'),
      ),
    );
  }
}

class _NextEpisodeOverlay extends StatelessWidget {
  const _NextEpisodeOverlay({
    required this.playback,
    required this.autoplay,
    required this.onNext,
  });

  final PlaybackState playback;
  final bool autoplay;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final remaining = playback.duration - playback.position;
    final showCountdown =
        autoplay &&
        remaining > Duration.zero &&
        remaining <= const Duration(seconds: 30);
    if (!showCountdown && playback.status != PlaybackStatus.completed) {
      return const SizedBox.shrink();
    }
    return Positioned(
      right: 18,
      bottom: 82,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.75),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: SizedBox(
          width: 280,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UP NEXT',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.play_arrow, size: 18),
                  label: Text(
                    showCountdown
                        ? 'Play in ${remaining.inSeconds}s'
                        : 'Play Now',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
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

class _PlayerLoadingOverlay extends StatelessWidget {
  const _PlayerLoadingOverlay({
    required this.title,
    required this.message,
    this.posterPath,
    this.subtitle,
  });

  final String title;
  final String message;
  final String? posterPath;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final imageUrl = TmdbImageBuilder.backdrop(posterPath, size: 'w780');
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Opacity(
              opacity: 0.16,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 56,
                  height: 56,
                  child: CircularProgressIndicator(
                    color: AppColors.primary,
                    strokeWidth: 3,
                  ),
                ),
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle!,
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        message,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerErrorOverlay extends StatelessWidget {
  const _PlayerErrorOverlay({
    required this.message,
    required this.canSwitchServer,
    required this.onSwitchServer,
    required this.onRetry,
    required this.onClose,
  });

  final String message;
  final bool canSwitchServer;
  final VoidCallback onSwitchServer;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xE6000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppColors.primary,
                  size: 52,
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Playback unavailable',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: AppSpacing.lg),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    if (canSwitchServer)
                      ElevatedButton.icon(
                        onPressed: onSwitchServer,
                        icon: const Icon(Icons.sync),
                        label: const Text('Switch Server'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    OutlinedButton(
                      onPressed: onClose,
                      child: const Text('Back'),
                    ),
                    FilledButton(
                      onPressed: onRetry,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EpisodePickerDialog extends StatefulWidget {
  const _EpisodePickerDialog({
    required this.totalEpisodes,
    required this.currentEpisode,
    required this.season,
  });

  final int totalEpisodes;
  final int currentEpisode;
  final int season;

  @override
  State<_EpisodePickerDialog> createState() => _EpisodePickerDialogState();
}

class _EpisodePickerDialogState extends State<_EpisodePickerDialog> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final episodes = List<int>.generate(widget.totalEpisodes, (i) => i + 1)
        .where((episode) => _query.isEmpty || '$episode'.contains(_query))
        .toList(growable: false);

    return Dialog(
      alignment: Alignment.bottomCenter,
      insetPadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Material(
          color: const Color(0xFF141414),
          child: SizedBox(
            width: 560,
            height: 560,
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[600],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Season ${widget.season}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              '${widget.totalEpisodes} Episodes',
                              style: TextStyle(
                                color: Colors.grey[400],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    controller: _controller,
                    onChanged: (value) => setState(() => _query = value.trim()),
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Search episodes...',
                      hintStyle: TextStyle(color: Colors.grey[500]),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                _controller.clear();
                                setState(() => _query = '');
                              },
                              icon: Icon(
                                Icons.clear,
                                color: Colors.grey[500],
                                size: 18,
                              ),
                            ),
                      filled: true,
                      fillColor: const Color(0xFF2A2A2A),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: episodes.isEmpty
                      ? Center(
                          child: Text(
                            'No episodes match "$_query"',
                            style: TextStyle(color: Colors.grey[400]),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: episodes.length,
                          itemBuilder: (context, index) {
                            final episode = episodes[index];
                            final current = episode == widget.currentEpisode;
                            final shape = RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: current
                                  ? const BorderSide(
                                      color: AppColors.primary,
                                      width: 1.5,
                                    )
                                  : BorderSide.none,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Material(
                                color: current
                                    ? AppColors.primary.withValues(alpha: 0.16)
                                    : const Color(0xFF1E1E1E),
                                shape: shape,
                                clipBehavior: Clip.antiAlias,
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.black45,
                                    child: Icon(
                                      current
                                          ? Icons.equalizer
                                          : Icons.play_arrow,
                                      color: current
                                          ? AppColors.primary
                                          : Colors.white,
                                    ),
                                  ),
                                  title: Text(
                                    'Episode $episode',
                                    style: TextStyle(
                                      color: current
                                          ? AppColors.primary
                                          : Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  trailing: current
                                      ? const Text(
                                          'NOW',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11,
                                          ),
                                        )
                                      : null,
                                  selected: current,
                                  selectedTileColor: AppColors.primary
                                      .withValues(alpha: 0.16),
                                  hoverColor: Colors.white.withValues(
                                    alpha: 0.06,
                                  ),
                                  shape: shape,
                                  onTap: () => Navigator.pop(context, episode),
                                ),
                              ),
                            );
                          },
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

class _VolumeOverlay extends StatelessWidget {
  const _VolumeOverlay({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 28,
      top: 0,
      bottom: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 44,
              height: 220,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xB3000000),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  const Icon(Icons.volume_up, color: Colors.white70, size: 18),
                  const SizedBox(height: 10),
                  Expanded(
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: LinearProgressIndicator(
                        value: (value / 2).clamp(0.0, 1.0),
                        color: AppColors.primary,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${(value * 100).round()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeText extends StatelessWidget {
  const _TimeText({required this.duration});

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    final text = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$minutes:$seconds'
        : '$minutes:$seconds';
    return Text(
      text,
      style: const TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w800,
        fontSize: 13,
      ),
    );
  }
}
