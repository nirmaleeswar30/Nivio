import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stream_result.dart';
import '../services/download_service.dart';
import '../services/m3u8_parser.dart';
import '../providers/settings_providers.dart';
import '../core/theme.dart';

class DownloadPrompt {
  static Future<void> showAndQueue({
    required BuildContext context,
    required WidgetRef ref,
    required StreamResult streamResult,
    required int mediaId,
    required String title,
    required String mediaType,
    int? season,
    int? episode,
    String? posterPath,
  }) async {
    // If we have multiple sources (like Animepahe qualities/audios), prompt for those
    if (streamResult.sources.length > 1) {
      if (!context.mounted) return;
      
      StreamSource? selectedSource = streamResult.sources.first;
      
      await showModalBottomSheet(
        context: context,
        backgroundColor: NivioTheme.netflixDarkGrey,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setState) {
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Quality', style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<StreamSource>(
                            value: selectedSource,
                            isExpanded: true,
                            dropdownColor: NivioTheme.netflixDarkGrey,
                            icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                            items: streamResult.sources.map((source) {
                              final label = "${source.quality} ${source.isDub ? '(Dub)' : '(Sub)'}";
                              return DropdownMenuItem(
                                value: source,
                                child: Text(label, style: const TextStyle(color: NivioTheme.netflixWhite)),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => selectedSource = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: NivioTheme.accentColorOf(context),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          onPressed: () {
                            Navigator.pop(ctx);
                            _queue(mediaId, title, mediaType, season, episode, posterPath, selectedSource!.url, streamResult.headers, null, null);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download queued!')));
                            }
                          },
                          child: const Text('Confirm Download', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
      return;
    }

    // If it's not m3u8, or it's a provider that doesn't use m3u8, just download directly.
    if (!streamResult.isM3U8) {
      await _queue(mediaId, title, mediaType, season, episode, posterPath, streamResult.url, streamResult.headers, null, null);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download queued!')));
      }
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context), strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text('Fetching available languages...', style: TextStyle(color: NivioTheme.netflixWhite)),
            ),
          ],
        ),
      ),
    );

    // Parse languages
    final tracks = await M3u8Parser.parseTracks(streamResult.url, streamResult.headers);
    final audioTracks = tracks['audio'] ?? [];
    final subtitleTracks = tracks['subtitle'] ?? [];

    if (context.mounted) {
      Navigator.pop(context); // Dismiss loading
    }

    // If no tracks found, just download directly
    if (audioTracks.isEmpty && subtitleTracks.isEmpty) {
      await _queue(mediaId, title, mediaType, season, episode, posterPath, streamResult.url, streamResult.headers, null, null);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download queued!')));
      }
      return;
    }

    // Determine default selection based on global settings
    final prefAudio = ref.read(preferredDownloadAudioLanguageProvider);
    final prefSubtitle = ref.read(preferredDownloadSubtitleLanguageProvider);

    String? selectedAudio;
    String? selectedSubtitle;

    // Try to match preferred audio. If 'Original', pick first.
    if (prefAudio == 'Original' && audioTracks.isNotEmpty) {
      selectedAudio = audioTracks.first.language;
    } else {
      final match = audioTracks.where((t) => t.name.toLowerCase().contains(prefAudio.toLowerCase()));
      if (match.isNotEmpty) selectedAudio = match.first.language;
      else if (audioTracks.isNotEmpty) selectedAudio = audioTracks.first.language;
    }

    // Try to match preferred subtitle
    if (prefSubtitle == 'Auto' && subtitleTracks.isNotEmpty) {
      selectedSubtitle = subtitleTracks.first.language;
    } else if (prefSubtitle == 'Off') {
      selectedSubtitle = null;
    } else {
      final match = subtitleTracks.where((t) => t.name.toLowerCase().contains(prefSubtitle.toLowerCase()));
      if (match.isNotEmpty) selectedSubtitle = match.first.language;
      else if (subtitleTracks.isNotEmpty) selectedSubtitle = subtitleTracks.first.language;
    }

    if (!context.mounted) return;

    // Show Bottom Sheet for confirmation
    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Download Languages', style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 24),
                    if (audioTracks.isNotEmpty) ...[
                      const Text('Audio Track', style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedAudio,
                            isExpanded: true,
                            dropdownColor: NivioTheme.netflixDarkGrey,
                            icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                            items: audioTracks.map((t) {
                              return DropdownMenuItem(
                                value: t.language,
                                child: Text(t.name, style: const TextStyle(color: NivioTheme.netflixWhite)),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => selectedAudio = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (subtitleTracks.isNotEmpty) ...[
                      const Text('Subtitle Track', style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: selectedSubtitle,
                            isExpanded: true,
                            dropdownColor: NivioTheme.netflixDarkGrey,
                            icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('None (Off)', style: TextStyle(color: NivioTheme.netflixWhite))),
                              ...subtitleTracks.map((t) {
                                return DropdownMenuItem(
                                  value: t.language,
                                  child: Text(t.name, style: const TextStyle(color: NivioTheme.netflixWhite)),
                                );
                              }).toList(),
                            ],
                            onChanged: (val) => setState(() => selectedSubtitle = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivioTheme.accentColorOf(context),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _queue(mediaId, title, mediaType, season, episode, posterPath, streamResult.url, streamResult.headers, selectedAudio, selectedSubtitle);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download queued!')));
                          }
                        },
                        child: const Text('Confirm Download', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _queue(
    int mediaId, String title, String mediaType, int? season, int? episode, String? posterPath,
    String url, Map<String, String>? headers, String? audioLang, String? subLang
  ) async {
    await DownloadService.queueDownload(
      mediaId: mediaId,
      title: title,
      mediaType: mediaType,
      season: season,
      episode: episode,
      posterPath: posterPath,
      streamUrl: url,
      headers: headers,
      selectedAudioLanguage: audioLang,
      selectedSubtitleLanguage: subLang,
    );
  }

  /// Shows a language picker dialog and returns the selected audio/subtitle languages.
  /// Returns null if the user cancels. Used by batch/seasonal downloads to ask once
  /// and apply the same language selection to all episodes.
  static Future<({String? audioLang, String? subtitleLang})?> pickLanguages({
    required BuildContext context,
    required WidgetRef ref,
    required StreamResult streamResult,
  }) async {
    // If it has multiple sources (Animepahe), no language selection needed
    if (streamResult.sources.length > 1 || !streamResult.isM3U8) {
      return (audioLang: null, subtitleLang: null);
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: NivioTheme.netflixDarkGrey,
        content: Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context), strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text('Fetching available languages...', style: TextStyle(color: NivioTheme.netflixWhite)),
            ),
          ],
        ),
      ),
    );

    // Parse languages
    final tracks = await M3u8Parser.parseTracks(streamResult.url, streamResult.headers);
    final audioTracks = tracks['audio'] ?? [];
    final subtitleTracks = tracks['subtitle'] ?? [];

    if (context.mounted) {
      Navigator.pop(context); // Dismiss loading
    }

    // If no tracks found, no language selection needed
    if (audioTracks.isEmpty && subtitleTracks.isEmpty) {
      return (audioLang: null, subtitleLang: null);
    }

    // Determine default selection based on global settings
    final prefAudio = ref.read(preferredDownloadAudioLanguageProvider);
    final prefSubtitle = ref.read(preferredDownloadSubtitleLanguageProvider);

    String? selectedAudio;
    String? selectedSubtitle;

    if (prefAudio == 'Original' && audioTracks.isNotEmpty) {
      selectedAudio = audioTracks.first.language;
    } else {
      final match = audioTracks.where((t) => t.name.toLowerCase().contains(prefAudio.toLowerCase()));
      if (match.isNotEmpty) selectedAudio = match.first.language;
      else if (audioTracks.isNotEmpty) selectedAudio = audioTracks.first.language;
    }

    if (prefSubtitle == 'Auto' && subtitleTracks.isNotEmpty) {
      selectedSubtitle = subtitleTracks.first.language;
    } else if (prefSubtitle == 'Off') {
      selectedSubtitle = null;
    } else {
      final match = subtitleTracks.where((t) => t.name.toLowerCase().contains(prefSubtitle.toLowerCase()));
      if (match.isNotEmpty) selectedSubtitle = match.first.language;
      else if (subtitleTracks.isNotEmpty) selectedSubtitle = subtitleTracks.first.language;
    }

    if (!context.mounted) return null;

    // Show language picker
    ({String? audioLang, String? subtitleLang})? result;

    await showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return SafeArea(
              child: Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Select Download Languages', style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    const Text('This selection will be applied to all episodes', style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 13)),
                    const SizedBox(height: 24),
                    if (audioTracks.isNotEmpty) ...[
                      const Text('Audio Track', style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedAudio,
                            isExpanded: true,
                            dropdownColor: NivioTheme.netflixDarkGrey,
                            icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                            items: audioTracks.map((t) {
                              return DropdownMenuItem(
                                value: t.language,
                                child: Text(t.name, style: const TextStyle(color: NivioTheme.netflixWhite)),
                              );
                            }).toList(),
                            onChanged: (val) => setState(() => selectedAudio = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (subtitleTracks.isNotEmpty) ...[
                      const Text('Subtitle Track', style: TextStyle(color: NivioTheme.netflixLightGrey, fontSize: 14)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: selectedSubtitle,
                            isExpanded: true,
                            dropdownColor: NivioTheme.netflixDarkGrey,
                            icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('None (Off)', style: TextStyle(color: NivioTheme.netflixWhite))),
                              ...subtitleTracks.map((t) {
                                return DropdownMenuItem(
                                  value: t.language,
                                  child: Text(t.name, style: const TextStyle(color: NivioTheme.netflixWhite)),
                                );
                              }),
                            ],
                            onChanged: (val) => setState(() => selectedSubtitle = val),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: NivioTheme.accentColorOf(context),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: () {
                          result = (audioLang: selectedAudio, subtitleLang: selectedSubtitle);
                          Navigator.pop(ctx);
                        },
                        child: const Text('Start Downloads', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return result;
  }
}
