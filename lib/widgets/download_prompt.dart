import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stream_result.dart';
import '../services/download_service.dart';
import '../services/m3u8_parser.dart';
import '../services/streaming_service.dart';
import '../providers/settings_providers.dart';
import '../providers/service_providers.dart';
import '../models/search_result.dart';
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
    SearchResult? media,
    int? providerIndex,
  }) async {
    final selection = await pickLanguages(
      context: context,
      ref: ref,
      streamResult: streamResult,
      media: media,
      season: season,
      episode: episode,
      providerIndex: providerIndex,
      isAnime: mediaType == 'anime',
    );
    if (selection == null) return;
    
    var urlToDownload = selection.selectedSource?.url ?? selection.updatedResult?.url ?? streamResult.url;
    var finalResult = selection.updatedResult ?? streamResult;
    var currentProviderIndex = selection.finalProviderIndex ?? providerIndex;

    if (media != null && currentProviderIndex != null && selection.audioLang != null && 
        selection.audioLang != finalResult.selectedAudio && 
        finalResult.availableAudios.contains(selection.audioLang)) {
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: NivioTheme.netflixDarkGrey,
            content: Row(
              children: [
                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: NivioTheme.accentColorOf(context), strokeWidth: 2)),
                const SizedBox(width: 16),
                Expanded(child: Text('Fetching ${selection.audioLang} stream...', style: const TextStyle(color: NivioTheme.netflixWhite))),
              ],
            ),
          ),
        );
      }

      final streamingService = ref.read(streamingServiceProvider);
      final newResult = await streamingService.fetchStreamUrl(
        media: media,
        season: season ?? 1,
        episode: episode ?? 1,
        providerIndex: currentProviderIndex,
        preferredQuality: selection.selectedSource?.quality,
        subDubPreference: selection.audioLang!.toLowerCase().contains('dub') ? 'dub' : 'sub',
        preferredAudio: selection.audioLang,
      );

      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading
      }

      if (newResult != null) {
        urlToDownload = selection.selectedSource?.url ?? newResult.url;
        finalResult = newResult;
      }
    }
    
    String? subtitleUrl;
    if (selection.subtitleLang != null && selection.subtitleLang != 'Off') {
      try {
        final match = finalResult.subtitles.firstWhere(
          (s) => s.lang.toLowerCase() == selection.subtitleLang!.toLowerCase(),
          orElse: () => finalResult.subtitles.firstWhere(
            (s) => s.lang.toLowerCase().contains(selection.subtitleLang!.toLowerCase()),
            orElse: () => finalResult.subtitles.first,
          ),
        );
        subtitleUrl = match.url;
      } catch (_) {}
    }

    await _queue(
      mediaId, title, mediaType, season, episode, posterPath, 
      urlToDownload, finalResult.headers, selection.audioLang, selection.subtitleLang, subtitleUrl
    );
    
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Download queued!')));
    }
  }

  static Future<void> _queue(
    int mediaId, String title, String mediaType, int? season, int? episode, String? posterPath,
    String url, Map<String, String>? headers, String? audioLang, String? subLang, String? subtitleUrl
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
      subtitleUrl: subtitleUrl,
    );
  }

  /// Shows a language picker dialog and returns the selected audio/subtitle languages.
  /// Returns null if the user cancels. Used by batch/seasonal downloads to ask once
  /// and apply the same language selection to all episodes.
  static Future<({String? audioLang, String? subtitleLang, StreamSource? selectedSource, int? finalProviderIndex, StreamResult? updatedResult})?> pickLanguages({
    required BuildContext context,
    required WidgetRef ref,
    required StreamResult streamResult,
    SearchResult? media,
    int? season,
    int? episode,
    int? providerIndex,
    bool isAnime = false,
  }) async {
    StreamSource? selectedSource;
    int? currentProviderIndex = providerIndex;
    StreamResult currentResult = streamResult;
    
    // Determine if media is anime accurately using the method from StreamingService
    bool isAnimeMedia = isAnime;
    if (media != null) {
       isAnimeMedia = StreamingService.isAnimeMedia(media);
    }
    
    // Fetch server list for the dropdown
    List<Map<String, dynamic>> availableServers = [];
    if (media != null && currentProviderIndex != null) {
      final streamingService = ref.read(streamingServiceProvider);
      final max = streamingService.totalProvidersFor(isAnime: isAnimeMedia);
      debugPrint('DownloadPrompt: isAnimeMedia=$isAnimeMedia, max=$max');
      for (int i = 0; i < max; i++) {
        if (streamingService.isDownloadable(i, isAnime: isAnimeMedia)) {
          final name = streamingService.getProviderName(i, isAnime: isAnimeMedia);
          debugPrint('DownloadPrompt: downloadable server = $name');
          availableServers.add({
             'index': i,
             'name': name
          });
        }
      }
    }
    
    debugPrint('DownloadPrompt: sources=${currentResult.sources.length}, availableServers=${availableServers.length}');
    // 1. If we have multiple sources (like Animepahe qualities/audios), or we have servers to choose from, prompt first
    if (currentResult.sources.length > 1 || availableServers.length > 1) {
      if (!context.mounted) return null;
      
      selectedSource = streamResult.sources.first;
      bool confirmed = false;
      
      await showModalBottomSheet(
        context: context,
        backgroundColor: NivioTheme.netflixDarkGrey,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) {
          bool isLoadingServer = false;
          return StatefulBuilder(
            builder: (ctx, setState) {
              return SafeArea(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (availableServers.length > 1) ...[
                        const Text('Select Server (Advanced)', style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: currentProviderIndex,
                              isExpanded: true,
                              dropdownColor: NivioTheme.netflixDarkGrey,
                              icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                              items: availableServers.map((s) {
                                return DropdownMenuItem<int>(
                                  value: s['index'],
                                  child: Text(s['name'], style: const TextStyle(color: NivioTheme.netflixWhite)),
                                );
                              }).toList(),
                              onChanged: (newIdx) async {
                                if (newIdx == null || newIdx == currentProviderIndex) return;
                                
                                setState(() => isLoadingServer = true);
                                final streamingService = ref.read(streamingServiceProvider);
                                try {
                                  final newResult = await streamingService.fetchStreamUrl(
                                    media: media!,
                                    season: season ?? 1,
                                    episode: episode ?? 1,
                                    providerIndex: newIdx,
                                  );
                                  if (newResult != null) {
                                    setState(() {
                                      currentProviderIndex = newIdx;
                                      currentResult = newResult;
                                      selectedSource = newResult.sources.isNotEmpty ? newResult.sources.first : null;
                                    });
                                  } else {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to probe selected server.')));
                                    }
                                  }
                                } finally {
                                  if (context.mounted) setState(() => isLoadingServer = false);
                                }
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                      if (currentResult.sources.isNotEmpty) ...[
                        const Text('Select Quality', style: TextStyle(color: NivioTheme.netflixWhite, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<StreamSource>(
                              value: selectedSource,
                              isExpanded: true,
                              dropdownColor: NivioTheme.netflixDarkGrey,
                              icon: const Icon(Icons.arrow_drop_down, color: NivioTheme.netflixWhite),
                              items: currentResult.sources.map((source) {
                                final hasMixedAudio = currentResult.sources.any((s) => s.isDub) && currentResult.sources.any((s) => !s.isDub);
                                final label = (isAnimeMedia && hasMixedAudio)
                                    ? "${source.quality} ${source.isDub ? '(Dub)' : '(Sub)'}"
                                    : source.quality;
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
                          onPressed: isLoadingServer ? null : () {
                            confirmed = true;
                            Navigator.pop(ctx);
                          },
                          child: isLoadingServer 
                              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                              : const Text('Next', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
      
      if (!confirmed) return null;
    }

    // 2. Extract target URL from selection or fallback to default
    final targetUrl = selectedSource?.url ?? streamResult.url;
    final isM3u8 = targetUrl.toLowerCase().contains('.m3u8') || streamResult.isM3U8;

    // 3. Show loading indicator and probe M3U8 if necessary
    List<M3u8Track> audioTracks = [];
    List<M3u8Track> subtitleTracks = [];

    if (isM3u8) {
      if (!context.mounted) return null;
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
      try {
        final tracks = await M3u8Parser.parseTracks(targetUrl, streamResult.headers);
        audioTracks = tracks['audio'] ?? [];
        subtitleTracks = tracks['subtitle'] ?? [];
      } catch (e) {
        debugPrint('M3u8Parser error: $e');
      }

      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading
      }
    }

    for (final audio in streamResult.availableAudios) {
      if (!audioTracks.any((t) => t.language == audio)) {
        audioTracks.add(M3u8Track(language: audio, name: audio));
      }
    }

    for (final sub in streamResult.subtitles) {
      if (!subtitleTracks.any((t) => t.language == sub.lang)) {
        subtitleTracks.add(M3u8Track(language: sub.lang, name: sub.lang));
      }
    }

    if (audioTracks.isEmpty && subtitleTracks.isEmpty && streamResult.availableAudios.isEmpty && streamResult.subtitles.isEmpty) {
      return (audioLang: null, subtitleLang: null, selectedSource: selectedSource, finalProviderIndex: currentProviderIndex, updatedResult: currentResult);
    }

    // Determine default selection based on global settings
    final prefAudio = ref.read(preferredDownloadAudioLanguageProvider);
    final prefSubtitle = ref.read(preferredDownloadSubtitleLanguageProvider);

    String? selectedAudio;
    String? selectedSubtitle;

    if (streamResult.selectedAudio.isNotEmpty && audioTracks.any((t) => t.language == streamResult.selectedAudio)) {
      selectedAudio = streamResult.selectedAudio;
    } else if (prefAudio == 'Original' && audioTracks.isNotEmpty) {
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
    ({String? audioLang, String? subtitleLang, StreamSource? selectedSource, int? finalProviderIndex, StreamResult? updatedResult})? result;

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
                          result = (audioLang: selectedAudio, subtitleLang: selectedSubtitle, selectedSource: selectedSource, finalProviderIndex: currentProviderIndex, updatedResult: currentResult);
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
