import 'dart:io';
import 'package:nivio/widgets/dpad_focusable.dart';
import 'package:nivio/core/app_platform.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/download_service.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:nivio/widgets/marquee_text.dart';

class DownloadsScreen extends StatefulWidget {
  final bool embedded;
  const DownloadsScreen({super.key, this.embedded = false});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;

    return ValueListenableBuilder(
      valueListenable: DownloadService.box.listenable(),
      builder: (context, Box<DownloadItem> box, _) {
        final downloads = box.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (downloads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white24),
                SizedBox(height: 16),
                Text(
                  'No downloads yet',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          );
        }

        final groupedDownloads = <int, List<DownloadItem>>{};
        for (final item in downloads) {
          groupedDownloads.putIfAbsent(item.mediaId, () => []).add(item);
        }
        
        final groups = groupedDownloads.values.toList();

        return AppListView.builder(
          padding: EdgeInsets.fromLTRB(
            isDesktop ? 68 : 16,
            16,
            16,
            isDesktop ? 16 : (widget.embedded ? 96 : 16),
          ),
          cacheExtent: 250,
          scrollSpeed: 2.0,
          silkyScrollDuration: const Duration(milliseconds: 500),
          animationCurve: Curves.easeOutQuart,
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            if (group.length == 1) {
              return _DownloadItemCard(item: group.first, isDesktop: isDesktop);
            } else {
              return _DownloadGroupCard(group: group, isDesktop: isDesktop);
            }
          },
        );
      },
    );
  }
}

class _DownloadGroupCard extends StatefulWidget {
  final List<DownloadItem> group;
  final bool isDesktop;

  const _DownloadGroupCard({
    required this.group,
    required this.isDesktop,
  });

  @override
  State<_DownloadGroupCard> createState() => _DownloadGroupCardState();
}

class _DownloadGroupCardState extends State<_DownloadGroupCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final firstItem = widget.group.first;
    
    final titleParts = firstItem.title.split('|||');
    final seriesName = titleParts.first;
    
    final posterParts = firstItem.posterPath?.split('|||') ?? [];
    final seriesPoster = posterParts.isNotEmpty ? posterParts.first : null;
    final groupSize = _getGroupSize(widget.group);
    final hasActiveDownloads = widget.group.any((item) => item.status == DownloadStatus.downloading);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.008 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? Colors.white.withValues(alpha: 0.065)
                : Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasActiveDownloads 
                  ? NivioTheme.accentColorOf(context).withValues(alpha: 0.4)
                  : (_isHovered
                      ? Colors.white.withValues(alpha: 0.16)
                      : Colors.white.withValues(alpha: 0.07)),
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              childrenPadding: const EdgeInsets.only(bottom: 6),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: seriesPoster != null
                    ? CachedNetworkImage(
                        imageUrl: seriesPoster.startsWith('http') ? seriesPoster : 'https://image.tmdb.org/t/p/w200$seriesPoster',
                        width: 60,
                        height: 88,
                        fit: BoxFit.cover,
                        memCacheWidth: 200,
                        errorWidget: (_, __, ___) => _buildFallbackPoster(width: 60, height: 88),
                      )
                    : _buildFallbackPoster(width: 60, height: 88),
              ),
              title: MarqueeText(
                text: seriesName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Text(
                      '${widget.group.length} ${widget.group.length == 1 ? 'Episode' : 'Episodes'}',
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    if (groupSize.isNotEmpty) ...[
                      const Text(' • ', style: TextStyle(color: Colors.white38, fontSize: 13)),
                      Text(groupSize, style: const TextStyle(color: Colors.white54, fontSize: 13)),
                    ],
                    if (hasActiveDownloads) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: NivioTheme.accentColorOf(context).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'DOWNLOADING',
                          style: TextStyle(
                            color: NivioTheme.accentColorOf(context),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              children: widget.group
                  .map((item) => _DownloadItemCard(item: item, isGrouped: true, isDesktop: widget.isDesktop))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _DownloadItemCard extends StatefulWidget {
  final DownloadItem item;
  final bool isGrouped;
  final bool isDesktop;

  const _DownloadItemCard({
    required this.item,
    this.isGrouped = false,
    required this.isDesktop,
  });

  @override
  State<_DownloadItemCard> createState() => _DownloadItemCardState();
}

class _DownloadItemCardState extends State<_DownloadItemCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isCompleted = item.status == DownloadStatus.completed;
    final isFailed = item.status == DownloadStatus.failed;
    final isDownloading = item.status == DownloadStatus.downloading;
    final isPaused = item.status == DownloadStatus.paused;

    final titleParts = item.title.split('|||');
    final String displayName;
    if (widget.isGrouped && titleParts.length > 1) {
      displayName = titleParts.last;
    } else if (titleParts.length > 1) {
      displayName = '${titleParts.first} - ${titleParts.last}';
    } else {
      displayName = item.title;
    }
    
    final posterParts = item.posterPath?.split('|||') ?? [];
    final String? itemPoster = posterParts.length > 1 ? posterParts.last : (posterParts.isNotEmpty ? posterParts.first : null);
    final isEpisode = item.season != null;
    final sizeText = _getItemSize(item);
    final thumbWidth = isEpisode ? (widget.isDesktop ? 116.0 : 100.0) : (widget.isDesktop ? 68.0 : 58.0);
    final thumbHeight = isEpisode ? (widget.isDesktop ? 66.0 : 58.0) : (widget.isDesktop ? 100.0 : 86.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedScale(
        scale: _isHovered ? 1.012 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: widget.isGrouped 
              ? const EdgeInsets.symmetric(horizontal: 4, vertical: 3)
              : const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: widget.isGrouped 
                ? (_isHovered ? Colors.white.withValues(alpha: 0.055) : Colors.white.withValues(alpha: 0.03))
                : (_isHovered ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isDownloading 
                  ? NivioTheme.accentColorOf(context).withValues(alpha: _isHovered ? 0.5 : 0.3)
                  : (_isHovered ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.07)),
              width: 1,
            ),
            boxShadow: _isHovered
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.45),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: isCompleted
                  ? () {
                      context.push(
                        '/player/${item.mediaId}?type=${item.mediaType}&season=${item.season ?? 1}&episode=${item.episode ?? 1}&localPath=${Uri.encodeComponent(item.savePath)}',
                      );
                    }
                  : (isDownloading && DownloadService.canStreamWhileDownloading(item))
                      ? () {
                          context.push(
                            '/player/${item.mediaId}?type=${item.mediaType}&season=${item.season ?? 1}&episode=${item.episode ?? 1}&downloadStreamId=${Uri.encodeComponent(item.id)}',
                          );
                        }
                      : null,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Row: Thumbnail + Info + Top-right action
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Thumbnail with play overlay when completed
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: itemPoster != null
                                  ? CachedNetworkImage(
                                      imageUrl: itemPoster.startsWith('http')
                                          ? itemPoster
                                          : 'https://image.tmdb.org/t/p/w200$itemPoster',
                                      width: thumbWidth,
                                      height: thumbHeight,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 260,
                                      errorWidget: (_, __, ___) => _buildFallbackPoster(isEpisode: isEpisode, width: thumbWidth, height: thumbHeight),
                                    )
                                  : _buildFallbackPoster(isEpisode: isEpisode, width: thumbWidth, height: thumbHeight),
                            ),
                            if (isCompleted)
                              AnimatedScale(
                                scale: _isHovered ? 1.12 : 1.0,
                                duration: const Duration(milliseconds: 140),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.65),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: _isHovered ? Colors.white : Colors.white70,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(width: 14),

                        // Title & Metadata
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  height: 1.25,
                                ),
                              ),
                              const SizedBox(height: 5),
                              // Metadata Row (Season/Episode & Size)
                              Row(
                                children: [
                                  if (isEpisode && item.episode != null) ...[
                                    Text(
                                      'S${item.season} E${item.episode}',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    if (sizeText.isNotEmpty)
                                      const Text(' • ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                                  ],
                                  if (sizeText.isNotEmpty)
                                    Flexible(
                                      child: Text(
                                        sizeText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                                      ),
                                    ),
                                ],
                              ),
                              // On mobile or when completed, status badge is shown here in the top column
                              if (!widget.isDesktop || isCompleted) ...[
                                const SizedBox(height: 7),
                                _buildStatusBadge(context, item),
                              ],
                            ],
                          ),
                        ),

                        // Quick action on right: Delete / Cancel
                        _DownloadDeleteButton(
                          isCompleted: isCompleted,
                          onTap: () => DownloadService.deleteDownload(item.id),
                        ),
                      ],
                    ),

                    // Progress Bar when Downloading
                    if (isDownloading) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: item.progress.clamp(0.0, 1.0),
                          minHeight: 4,
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          valueColor: AlwaysStoppedAnimation<Color>(NivioTheme.accentColorOf(context)),
                        ),
                      ),
                    ],

                    // Action Footer Row: Dedicated for "Watch while downloading", Pause, Resume, Retry
                    if (isDownloading || isPaused || isFailed) ...[
                      const SizedBox(height: 12),
                      if (widget.isDesktop)
                        // Desktop Footer: Space on left fully utilized, Watch while downloading placed immediately before Pause/Resume on the right!
                        Row(
                          children: [
                            // Left side: space fully utilized for status & metrics
                            _buildStatusBadge(context, item),
                            if (sizeText.isNotEmpty) ...[
                              const Text(' • ', style: TextStyle(color: Colors.white38, fontSize: 12)),
                              Text(sizeText, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                            const Spacer(),
                            // Watch while downloading immediately to the left before pause/resume
                            if (DownloadService.canStreamWhileDownloading(item)) ...[
                              _StreamWhileDownloadingButton(
                                label: 'Watch while downloading',
                                onTap: () {
                                  context.push(
                                    '/player/${item.mediaId}?type=${item.mediaType}&season=${item.season ?? 1}&episode=${item.episode ?? 1}&downloadStreamId=${Uri.encodeComponent(item.id)}',
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (isDownloading)
                              _DownloadActionButton(
                                icon: Icons.pause_rounded,
                                label: 'Pause',
                                onTap: () => DownloadService.pauseDownload(item.id),
                              )
                            else if (isPaused)
                              _DownloadActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'Resume',
                                color: Colors.white,
                                hoverColor: Colors.white,
                                hoverBgColor: NivioTheme.accentColorOf(context).withValues(alpha: 0.25),
                                onTap: () => DownloadService.resumeDownload(item.id),
                              )
                            else if (isFailed)
                              _DownloadActionButton(
                                icon: Icons.refresh_rounded,
                                label: 'Retry',
                                onTap: () => DownloadService.startDownload(item),
                              ),
                          ],
                        )
                      else
                        // Mobile Footer: Compact Watch Now + Pause/Resume with zero overflow
                        Row(
                          children: [
                            if (DownloadService.canStreamWhileDownloading(item)) ...[
                              _StreamWhileDownloadingButton(
                                label: 'Watch Now',
                                onTap: () {
                                  context.push(
                                    '/player/${item.mediaId}?type=${item.mediaType}&season=${item.season ?? 1}&episode=${item.episode ?? 1}&downloadStreamId=${Uri.encodeComponent(item.id)}',
                                  );
                                },
                              ),
                              const Spacer(),
                            ] else ...[
                              const Spacer(),
                            ],

                            if (isDownloading)
                              _DownloadActionButton(
                                icon: Icons.pause_rounded,
                                label: 'Pause',
                                onTap: () => DownloadService.pauseDownload(item.id),
                              )
                            else if (isPaused)
                              _DownloadActionButton(
                                icon: Icons.play_arrow_rounded,
                                label: 'Resume',
                                color: Colors.white,
                                hoverColor: Colors.white,
                                hoverBgColor: NivioTheme.accentColorOf(context).withValues(alpha: 0.25),
                                onTap: () => DownloadService.resumeDownload(item.id),
                              )
                            else if (isFailed)
                              _DownloadActionButton(
                                icon: Icons.refresh_rounded,
                                label: 'Retry',
                                onTap: () => DownloadService.startDownload(item),
                              ),
                          ],
                        ),
                    ],
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

class _StreamWhileDownloadingButton extends StatefulWidget {
  final VoidCallback onTap;
  final String label;

  const _StreamWhileDownloadingButton({
    required this.onTap,
    this.label = 'Watch while downloading',
  });

  @override
  State<_StreamWhileDownloadingButton> createState() => _StreamWhileDownloadingButtonState();
}

class _StreamWhileDownloadingButtonState extends State<_StreamWhileDownloadingButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        style: DpadFocusStyle.highlight,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.lightBlueAccent.withValues(alpha: 0.24)
                  : Colors.lightBlueAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered
                    ? Colors.lightBlueAccent.withValues(alpha: 0.75)
                    : Colors.lightBlueAccent.withValues(alpha: 0.35),
                width: 1.2,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: Colors.lightBlueAccent.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.play_arrow_rounded,
                  color: _isHovered ? Colors.white : Colors.lightBlueAccent,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _isHovered ? Colors.white : Colors.lightBlueAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _DownloadActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Color? hoverColor;
  final Color? hoverBgColor;

  const _DownloadActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
    this.hoverColor,
    this.hoverBgColor,
  });

  @override
  State<_DownloadActionButton> createState() => _DownloadActionButtonState();
}

class _DownloadActionButtonState extends State<_DownloadActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.color ?? Colors.white70;
    final activeHoverColor = widget.hoverColor ?? Colors.white;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        style: DpadFocusStyle.highlight,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _isHovered
                  ? (widget.hoverBgColor ?? Colors.white.withValues(alpha: 0.16))
                  : Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isHovered
                    ? Colors.white.withValues(alpha: 0.35)
                    : Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
              boxShadow: _isHovered
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.icon,
                  size: 15,
                  color: _isHovered ? activeHoverColor : baseColor,
                ),
                const SizedBox(width: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    color: _isHovered ? activeHoverColor : baseColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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

class _DownloadDeleteButton extends StatefulWidget {
  final bool isCompleted;
  final VoidCallback onTap;

  const _DownloadDeleteButton({
    required this.isCompleted,
    required this.onTap,
  });

  @override
  State<_DownloadDeleteButton> createState() => _DownloadDeleteButtonState();
}

class _DownloadDeleteButtonState extends State<_DownloadDeleteButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: FocusableTap(
        style: DpadFocusStyle.highlight,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _isHovered ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _isHovered
                  ? Colors.redAccent.withValues(alpha: 0.18)
                  : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                widget.isCompleted ? Icons.delete_outline_rounded : Icons.close_rounded,
                color: _isHovered
                    ? Colors.redAccent
                    : (widget.isCompleted
                        ? Colors.redAccent.withValues(alpha: 0.7)
                        : Colors.white54),
                size: 19,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildFallbackPoster({bool isEpisode = false, double? width, double? height}) {
  return Container(
    width: width ?? (isEpisode ? 116 : 68),
    height: height ?? (isEpisode ? 66 : 100),
    decoration: BoxDecoration(
      color: Colors.white10,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const Icon(Icons.movie_outlined, color: Colors.white38, size: 24),
  );
}

Widget _buildStatusBadge(BuildContext context, DownloadItem item) {
  switch (item.status) {
    case DownloadStatus.completed:
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 14),
          SizedBox(width: 4),
          Text('Downloaded', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      );
    case DownloadStatus.downloading:
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              value: item.progress > 0 ? item.progress : null,
              strokeWidth: 2,
              color: NivioTheme.accentColorOf(context),
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Downloading ${(item.progress * 100).toStringAsFixed(1)}%',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: NivioTheme.accentColorOf(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    case DownloadStatus.paused:
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.pause_circle_filled_rounded, color: Colors.amberAccent, size: 14),
          SizedBox(width: 4),
          Text('Paused', style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      );
    case DownloadStatus.extracting:
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              item.progress >= 1.0 || item.downloadedBytes > 0 ? 'Merging files...' : 'Extracting video...',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      );
    case DownloadStatus.failed:
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 14),
          SizedBox(width: 4),
          Text('Failed', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      );
    case DownloadStatus.pending:
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded, color: Colors.white54, size: 14),
          SizedBox(width: 4),
          Text('Waiting...', style: TextStyle(color: Colors.white54, fontSize: 12)),
        ],
      );
  }
}

String _getItemSize(DownloadItem item) {
  if (item.totalBytes > 0 && item.status == DownloadStatus.downloading) {
    final downloaded = item.downloadedBytes > 0 ? item.downloadedBytes : _getFileBytes(item.savePath);
    if (downloaded > 0) {
      return '${_formatBytes(downloaded)} / ${_formatBytes(item.totalBytes)}';
    }
    return _formatBytes(item.totalBytes);
  }
  final bytes = _getFileBytes(item.savePath);
  if (bytes > 0) {
    return _formatBytes(bytes);
  }
  if (item.totalBytes > 0) {
    return _formatBytes(item.totalBytes);
  }
  return '';
}

String _getGroupSize(List<DownloadItem> group) {
  int total = 0;
  for (final item in group) {
    final b = _getFileBytes(item.savePath);
    total += (b > 0) ? b : item.totalBytes;
  }
  return _formatBytes(total);
}

int _getFileBytes(String path) {
  try {
    final f = File(path);
    if (f.existsSync()) return f.lengthSync();
  } catch (_) {}
  return 0;
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '';
  final mb = bytes / (1024 * 1024);
  if (mb >= 1024) {
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
  return '${mb.toStringAsFixed(1)} MB';
}
