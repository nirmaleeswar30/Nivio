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

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(16, 16, 16, widget.embedded ? 80 : 16),
          itemCount: downloads.length,
          itemBuilder: (context, index) {
            final item = downloads[index];
            return _buildDownloadItem(item);
          },
        );
      },
    );
  }

  Widget _buildDownloadItem(DownloadItem item) {
    final isCompleted = item.status == DownloadStatus.completed;
    final isFailed = item.status == DownloadStatus.failed;
    final isDownloading = item.status == DownloadStatus.downloading;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: item.posterPath != null
              ? CachedNetworkImage(
                  imageUrl: 'https://image.tmdb.org/t/p/w200${item.posterPath}',
                  width: 50,
                  height: 75,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 50,
                    height: 75,
                    color: Colors.white10,
                    child: const Icon(Icons.movie, color: Colors.white54),
                  ),
                )
              : Container(
                  width: 50,
                  height: 75,
                  color: Colors.white10,
                  child: const Icon(Icons.movie, color: Colors.white54),
                ),
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
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white70),
              color: const Color(0xFF2B2D33),
              onSelected: (value) {
                if (value == 'delete') {
                  DownloadService.deleteDownload(item.id);
                } else if (value == 'retry' && isFailed) {
                  DownloadService.startDownload(item);
                }
              },
              itemBuilder: (context) => [
                if (isFailed)
                  const PopupMenuItem(
                    value: 'retry',
                    child: Text('Retry', style: TextStyle(color: Colors.white)),
                  ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
