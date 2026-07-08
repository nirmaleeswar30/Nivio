import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/download_service.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
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
    return ValueListenableBuilder(
      valueListenable: DownloadService.box.listenable(),
      builder: (context, Box<DownloadItem> box, _) {
        final downloads = box.values.toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

        if (downloads.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.download_for_offline_outlined, size: 64, color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
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

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 16, 16, widget.embedded ? 80 : 16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            if (group.length == 1) {
              return _buildDownloadItem(group.first);
            } else {
              return _buildDownloadGroup(group);
            }
          },
        );
      },
    );
  }

  Widget _buildDownloadGroup(List<DownloadItem> group) {
    final firstItem = group.first;
    
    final titleParts = firstItem.title.split('|||');
    final seriesName = titleParts.first;
    
    final posterParts = firstItem.posterPath?.split('|||') ?? [];
    final seriesPoster = posterParts.isNotEmpty ? posterParts.first : null;
    
    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(12),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: seriesPoster != null
                ? CachedNetworkImage(
                    imageUrl: seriesPoster.startsWith('http') ? seriesPoster : 'https://image.tmdb.org/t/p/w200$seriesPoster',
                    width: 50,
                    height: 75,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _buildFallbackPoster(),
                  )
                : _buildFallbackPoster(),
          ),
          title: MarqueeText(
            text: seriesName,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text('${group.length} Episodes', style: const TextStyle(color: Colors.white70)),
          children: group.map((item) => _buildDownloadItem(item, isGrouped: true)).toList(),
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildFallbackPoster() {
    return Container(
      width: 50,
      height: 75,
      color: Colors.white10,
      child: const Icon(Icons.movie, color: Colors.white54),
    );
  }

  Widget _buildDownloadItem(DownloadItem item, {bool isGrouped = false}) {
    final isCompleted = item.status == DownloadStatus.completed;
    final isFailed = item.status == DownloadStatus.failed;
    final isDownloading = item.status == DownloadStatus.downloading;

    final titleParts = item.title.split('|||');
    final String displayName;
    if (isGrouped && titleParts.length > 1) {
      displayName = titleParts.last;
    } else if (titleParts.length > 1) {
      displayName = '${titleParts.first} - ${titleParts.last}';
    } else {
      displayName = item.title;
    }
    
    final posterParts = item.posterPath?.split('|||') ?? [];
    final String? itemPoster = posterParts.length > 1 ? posterParts.last : (posterParts.isNotEmpty ? posterParts.first : null);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        margin: isGrouped ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
        child: Material(
          color: isGrouped ? Colors.transparent : Colors.white.withValues(alpha: 0.05),
          shape: RoundedRectangleBorder(
            borderRadius: isGrouped ? BorderRadius.zero : BorderRadius.circular(12),
          ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: itemPoster != null
              ? CachedNetworkImage(
                  imageUrl: itemPoster.startsWith('http') ? itemPoster : 'https://image.tmdb.org/t/p/w200$itemPoster',
                  width: item.season != null ? 80 : 50,
                  height: item.season != null ? 45 : 75,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _buildFallbackPoster(),
                )
              : _buildFallbackPoster(),
        ),
        title: MarqueeText(
          text: displayName,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.season != null && item.episode != null) Builder(
              builder: (context) {
                String sizeInfo = '';
                try {
                  final file = File(item.savePath);
                  if (file.existsSync()) {
                    final bytes = file.lengthSync();
                    if (bytes > 0) {
                      sizeInfo = ' • ${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                    }
                  }
                } catch (_) {}
                
                return Text('Season ${item.season} E${item.episode}$sizeInfo', style: const TextStyle(color: Colors.white70));
              }
            ) else Builder(
              builder: (context) {
                String sizeInfo = '';
                try {
                  final file = File(item.savePath);
                  if (file.existsSync()) {
                    final bytes = file.lengthSync();
                    if (bytes > 0) {
                      sizeInfo = '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
                    }
                  }
                } catch (_) {}
                
                if (sizeInfo.isEmpty) return const SizedBox(height: 8);
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Text(sizeInfo, style: const TextStyle(color: Colors.white70)),
                );
              }
            ),

            if (isDownloading)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: item.progress,
                    backgroundColor: Colors.white10,
                    color: NivioTheme.accentColorOf(context),
                  ),
                  const SizedBox(height: 4),
                  Text('${(item.progress * 100).toStringAsFixed(1)}%', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              )
            else if (item.status == DownloadStatus.extracting)
              Row(
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(item.progress >= 1.0 || item.downloadedBytes > 0 ? 'Merging files...' : 'Extracting video link...', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              )
            else if (isFailed)
              const Text('Failed', style: TextStyle(color: Colors.redAccent))
            else if (isCompleted)
              const Text('Completed', style: TextStyle(color: Colors.green))
            else
              Text(item.status.name, style: const TextStyle(color: Colors.white54)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompleted)
              IconButton(
                icon: const Icon(Icons.play_circle_fill, color: Colors.white),
                onPressed: () {
                  // Pass the local file path as a custom provider parameter to PlayerScreen
                  // We can intercept this in the player.
                  context.push(
                    '/player/${item.mediaId}?type=${item.mediaType}&season=${item.season ?? 1}&episode=${item.episode ?? 1}&localPath=${Uri.encodeComponent(item.savePath)}',
                  );
                },
              ),
            if (isDownloading || item.status == DownloadStatus.pending)
              IconButton(
                icon: const Icon(Icons.pause_circle_outline, color: Colors.white70),
                onPressed: () => DownloadService.pauseDownload(item.id),
              ),
            if (item.status == DownloadStatus.paused)
              IconButton(
                icon: const Icon(Icons.play_circle_outline, color: Colors.white),
                onPressed: () => DownloadService.resumeDownload(item.id),
              ),
            if (isFailed)
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                onPressed: () => DownloadService.startDownload(item),
              ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: () => DownloadService.deleteDownload(item.id),
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }
}
