import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/models/download_item.dart';
import 'package:nivio/services/download_service.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';

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
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.all(12),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: firstItem.posterPath != null
                ? CachedNetworkImage(
                    imageUrl: 'https://image.tmdb.org/t/p/w200${firstItem.posterPath}',
                    width: 50,
                    height: 75,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _buildFallbackPoster(),
                  )
                : _buildFallbackPoster(),
          ),
          title: Text(
            firstItem.title,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text('${group.length} Episodes', style: const TextStyle(color: Colors.white70)),
          children: group.map((item) => _buildDownloadItem(item, isGrouped: true)).toList(),
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

    return Container(
      margin: isGrouped ? EdgeInsets.zero : const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isGrouped ? Colors.transparent : Colors.white.withValues(alpha: 0.05),
        borderRadius: isGrouped ? BorderRadius.zero : BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: isGrouped
              ? const SizedBox(width: 50, child: Icon(Icons.movie, color: Colors.transparent))
              : (item.posterPath != null
                  ? CachedNetworkImage(
                      imageUrl: 'https://image.tmdb.org/t/p/w200${item.posterPath}',
                      width: 50,
                      height: 75,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _buildFallbackPoster(),
                    )
                  : _buildFallbackPoster()),
        ),
        title: Text(
          item.title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
              const Row(
                children: [
                  SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 8),
                  Text('Extracting video link...', style: TextStyle(color: Colors.white70, fontSize: 12)),
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
    );
  }
}
