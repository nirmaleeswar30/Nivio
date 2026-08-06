import 'package:flutter/material.dart';

import '../../../core/network/image/tmdb_image_builder.dart';
import '../../../shared/theme/index.dart';
import '../../../shared/widgets/widgets.dart';
import '../models/library_models.dart';
import '../services/library_data_service.dart';
import '../../player/models/playback_request.dart';
import '../../player/playback_request_factory.dart';
import 'library_empty_state.dart';

class DownloadsGrid extends StatelessWidget {
  const DownloadsGrid({
    super.key,
    required this.downloads,
    required this.service,
    this.onOpenDetail,
    this.onPlay,
  });

  final List<LibraryDownloadItem> downloads;
  final LibraryDownloadsService service;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    if (downloads.isEmpty) {
      return const LibraryEmptyState(
        title: 'No downloads yet',
        message: 'Downloaded movies and episodes will appear here.',
      );
    }

    return ResponsiveGrid(
      minItemWidth: 360,
      maxCrossAxisCount: 4,
      childAspectRatio: 1.56,
      crossAxisSpacing: AppSpacing.lg,
      mainAxisSpacing: AppSpacing.lg,
      children: [
        for (final item in downloads)
          _DownloadCard(
            item: item,
            service: service,
            onOpenDetail: onOpenDetail,
            onPlay: onPlay,
          ),
      ],
    );
  }
}

class _DownloadCard extends StatefulWidget {
  const _DownloadCard({
    required this.item,
    required this.service,
    this.onOpenDetail,
    this.onPlay,
  });

  final LibraryDownloadItem item;
  final LibraryDownloadsService service;
  final ValueChanged<String>? onOpenDetail;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  State<_DownloadCard> createState() => _DownloadCardState();
}

class _DownloadCardState extends State<_DownloadCard> {
  var _isHovered = false;

  LibraryDownloadItem get item => widget.item;

  @override
  Widget build(BuildContext context) {
    final titleParts = _titleParts(item);
    final posterParts = _posterParts(item);
    final title = titleParts.length > 1 ? titleParts.last : item.title;
    final parentTitle = titleParts.length > 1 ? titleParts.first : null;
    final poster = posterParts.length > 1
        ? posterParts.last
        : posterParts.firstOrNull;
    final size = widget.service.fileSizeBytes(item);
    final statusColor = _statusColor(item.status);
    final showProgress =
        item.status == LibraryDownloadStatus.downloading ||
        item.status == LibraryDownloadStatus.extracting ||
        item.status == LibraryDownloadStatus.pending;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        scale: _isHovered ? 1.018 : 1,
        child: Material(
          color: AppColors.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: _isHovered
                  ? AppColors.primary.withValues(alpha: 0.65)
                  : AppColors.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(AppRadius.medium),
          ),
          child: InkWell(
            onTap: () =>
                widget.onOpenDetail?.call('${item.mediaType}:${item.mediaId}'),
            child: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          statusColor.withValues(alpha: 0.12),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.16),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DownloadPoster(path: poster),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                _StatusChip(
                                  label: _shortStatusText(item.status),
                                  color: statusColor,
                                ),
                                const Spacer(),
                                _DownloadActions(
                                  item: item,
                                  service: widget.service,
                                  onPlay: widget.onPlay,
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),
                            if (parentTitle != null) ...[
                              Text(
                                parentTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                            ],
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.title.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Wrap(
                              spacing: AppSpacing.xs,
                              runSpacing: AppSpacing.xs,
                              children: [
                                _InfoChip(label: item.mediaType.toUpperCase()),
                                if (item.season != null && item.episode != null)
                                  _InfoChip(
                                    label: 'S${item.season} E${item.episode}',
                                  ),
                                if (size != null && size > 0)
                                  _InfoChip(label: _formatSize(size)),
                                if (item.selectedAudioLanguage
                                    case final String audio
                                    when audio.trim().isNotEmpty)
                                  _InfoChip(label: audio),
                                if (item.selectedSubtitleLanguage
                                    case final String subtitle
                                    when subtitle.trim().isNotEmpty)
                                  _InfoChip(label: subtitle),
                              ],
                            ),
                            const Spacer(),
                            if (showProgress) ...[
                              _DownloadProgress(item: item, color: statusColor),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                            Tooltip(
                              message: _detailStatusText(size),
                              waitDuration: const Duration(milliseconds: 350),
                              child: Text(
                                _detailStatusText(size),
                                maxLines:
                                    item.status == LibraryDownloadStatus.failed
                                    ? 3
                                    : 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.caption.copyWith(
                                  color: AppColors.textSecondary,
                                ),
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
          ),
        ),
      ),
    );
  }

  String _detailStatusText(int? size) {
    final parts = <String>[];
    parts.add(switch (item.status) {
      LibraryDownloadStatus.pending => 'Waiting to start',
      LibraryDownloadStatus.downloading =>
        'Downloading ${(item.progress * 100).toStringAsFixed(1)}%',
      LibraryDownloadStatus.completed => 'Ready offline',
      LibraryDownloadStatus.failed =>
        item.failureReason?.trim().isNotEmpty == true
            ? 'Failed: ${item.failureReason}'
            : 'Download failed',
      LibraryDownloadStatus.paused => 'Paused',
      LibraryDownloadStatus.extracting =>
        item.progress >= 1.0 ? 'Merging files' : 'Preparing video',
    });
    if (size != null && size > 0) parts.add(_formatSize(size));
    return parts.join(' · ');
  }
}

class _DownloadPoster extends StatelessWidget {
  const _DownloadPoster({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final url = path == null || path!.isEmpty
        ? null
        : TmdbImageBuilder.poster(path!);

    return AspectRatio(
      aspectRatio: AppBreakpoints.posterRatio,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: DecoratedBox(
          decoration: const BoxDecoration(color: AppColors.surfaceVariant),
          child: url == null
              ? const Center(child: Icon(Icons.movie_outlined, size: 32))
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 32),
                  ),
                ),
        ),
      ),
    );
  }
}

class _DownloadActions extends StatelessWidget {
  const _DownloadActions({
    required this.item,
    required this.service,
    this.onPlay,
  });

  final LibraryDownloadItem item;
  final LibraryDownloadsService service;
  final ValueChanged<PlaybackRequest>? onPlay;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.xs,
      children: [
        if (item.status == LibraryDownloadStatus.completed)
          _ActionButton(
            tooltip: service.fileExists(item)
                ? 'Play download'
                : 'Downloaded file missing',
            onPressed: service.fileExists(item)
                ? () => onPlay?.call(PlaybackRequestFactory.fromDownload(item))
                : null,
            icon: Icons.play_arrow_rounded,
          ),
        if (item.status == LibraryDownloadStatus.downloading ||
            item.status == LibraryDownloadStatus.pending)
          _ActionButton(
            tooltip: 'Pause',
            onPressed: () => service.pause(item.id),
            icon: Icons.pause_rounded,
          ),
        if (item.status == LibraryDownloadStatus.paused)
          _ActionButton(
            tooltip: 'Resume',
            onPressed: () => service.resume(item.id),
            icon: Icons.play_arrow_rounded,
          ),
        if (item.status == LibraryDownloadStatus.failed)
          _ActionButton(
            tooltip: 'Retry',
            onPressed: () => service.retry(item.id),
            icon: Icons.refresh_rounded,
          ),
        _ActionButton(
          tooltip: 'Delete',
          onPressed: () => service.delete(item.id),
          icon: Icons.delete_outline_rounded,
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox.square(
        dimension: 34,
        child: IconButton(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: 0.06),
            foregroundColor: AppColors.textPrimary,
            disabledForegroundColor: AppColors.disabledText,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.small),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
            ),
          ),
          onPressed: onPressed,
          icon: Icon(icon, size: 18),
        ),
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.item, required this.color});

  final LibraryDownloadItem item;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = item.progress.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '${(value * 100).toStringAsFixed(0)}%',
              style: AppTypography.metadata.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const Spacer(),
            Text(
              _shortStatusText(item.status),
              style: AppTypography.metadata.copyWith(
                color: AppColors.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.small),
          child: LinearProgressIndicator(
            value: item.status == LibraryDownloadStatus.pending ? null : value,
            minHeight: 6,
            backgroundColor: Colors.white.withValues(alpha: 0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: color.withValues(alpha: 0.34)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: AppTypography.metadata.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: AppTypography.metadata.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

String _shortStatusText(LibraryDownloadStatus status) {
  return switch (status) {
    LibraryDownloadStatus.pending => 'Pending',
    LibraryDownloadStatus.downloading => 'Downloading',
    LibraryDownloadStatus.completed => 'Ready',
    LibraryDownloadStatus.failed => 'Failed',
    LibraryDownloadStatus.paused => 'Paused',
    LibraryDownloadStatus.extracting => 'Preparing',
  };
}

Color _statusColor(LibraryDownloadStatus status) {
  return switch (status) {
    LibraryDownloadStatus.pending => AppColors.textMuted,
    LibraryDownloadStatus.downloading => AppColors.primary,
    LibraryDownloadStatus.completed => AppColors.success,
    LibraryDownloadStatus.failed => AppColors.danger,
    LibraryDownloadStatus.paused => AppColors.warning,
    LibraryDownloadStatus.extracting => AppColors.primary,
  };
}

String _formatSize(int size) =>
    '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';

List<String> _titleParts(LibraryDownloadItem item) => item.title.split('|||');

List<String> _posterParts(LibraryDownloadItem item) =>
    item.posterPath?.split('|||') ?? const [];
