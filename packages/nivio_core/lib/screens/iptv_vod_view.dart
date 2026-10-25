import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';

import 'package:nivio/core/app_platform.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/widgets/app_scroll_view.dart';
import 'package:nivio/widgets/dpad_focusable.dart';
import '../models/iptv_vod.dart';
import '../services/iptv_service.dart';

/// Movies or Series from IPTV playlists (Xtream VOD, or M3U `/movie/` and
/// `/series/` entries): search, category filter and a poster grid. Tapping a
/// series opens its seasons and episodes.
class IptvVodView extends ConsumerStatefulWidget {
  final IptvVodLibrary library;
  final bool series;
  final void Function(String url, String title) onPlay;

  const IptvVodView({
    super.key,
    required this.library,
    required this.series,
    required this.onPlay,
  });

  @override
  ConsumerState<IptvVodView> createState() => _IptvVodViewState();
}

class _IptvVodViewState extends ConsumerState<IptvVodView> {
  String _query = '';
  String _group = 'All';

  List<String> get _groups {
    final names = <String>{
      for (final m in widget.library.movies)
        if (!widget.series) m.group,
      for (final s in widget.library.series)
        if (widget.series) s.group,
    }.toList()
      ..sort();
    return ['All', ...names];
  }

  bool _matches(String name, String group) =>
      (_group == 'All' || group == _group) && (_query.isEmpty || name.toLowerCase().contains(_query));

  @override
  void didUpdateWidget(covariant IptvVodView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.series != widget.series) _group = 'All';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppPlatform.useDesktopLayout;
    final movies = widget.series
        ? const <IptvMovie>[]
        : widget.library.movies.where((m) => _matches(m.name, m.group)).toList();
    final series = widget.series
        ? widget.library.series.where((s) => _matches(s.name, s.group)).toList()
        : const <IptvSeries>[];
    final count = widget.series ? series.length : movies.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 10),
              SizedBox(width: isDesktop ? 220 : 130, child: _categoryButton()),
            ],
          ),
        ),
        Expanded(
          child: count == 0
              ? Center(
                  child: Text(
                    widget.series ? 'No series found' : 'No movies found',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 15),
                  ),
                )
              : AppGridView.builder(
                  padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 4, 16, 24 + bottomInset),
                  cacheExtent: 800,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: isDesktop ? 170 : 125,
                    childAspectRatio: 0.52,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: count,
                  itemBuilder: (context, i) {
                    if (widget.series) {
                      final s = series[i];
                      return _PosterCard(
                        title: s.name,
                        poster: s.poster,
                        rating: s.rating,
                        icon: PhosphorIconsRegular.television,
                        onTap: () => _openSeries(s),
                      );
                    }
                    final m = movies[i];
                    return _PosterCard(
                      title: m.name,
                      poster: m.poster,
                      rating: m.rating,
                      icon: PhosphorIconsRegular.filmStrip,
                      onTap: () => widget.onPlay(m.url, m.name),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _searchField() {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
    );
    return TvTextFieldGate(
      borderRadius: BorderRadius.circular(12),
      builder: (context, focusNode) => TextField(
        focusNode: focusNode,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.series ? 'Search series...' : 'Search movies...',
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3)),
          filled: true,
          fillColor: Colors.white.withValues(alpha: 0.06),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(borderSide: BorderSide(color: NivioTheme.accentColorOf(context))),
          prefixIcon: Icon(PhosphorIconsRegular.magnifyingGlass, color: Colors.white.withValues(alpha: 0.5), size: 20),
        ),
        onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
      ),
    );
  }

  Widget _categoryButton() {
    return Material(
      color: Colors.transparent,
      child: FocusableInkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _pickCategory,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _group,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              Icon(PhosphorIconsRegular.caretDown, color: Colors.white.withValues(alpha: 0.5), size: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _pickCategory() {
    final groups = _groups;
    final accent = NivioTheme.accentColorOf(context);
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      backgroundColor: NivioTheme.netflixDarkGrey,
      constraints: BoxConstraints(maxWidth: AppPlatform.useDesktopLayout ? 500 : double.infinity),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Select Category',
              style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: AppListView.builder(
              padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(sheetContext).bottom + 8),
              itemCount: groups.length,
              itemBuilder: (context, i) {
                final g = groups[i];
                final selected = g == _group;
                return ListTile(
                  title: Text(
                    g,
                    style: TextStyle(color: selected ? accent : Colors.white, fontWeight: selected ? FontWeight.bold : FontWeight.normal),
                  ),
                  trailing: selected ? Icon(Icons.check, color: accent) : null,
                  onTap: () {
                    setState(() => _group = g);
                    Navigator.pop(sheetContext);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _openSeries(IptvSeries series) {
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: NivioTheme.netflixDarkGrey,
      constraints: BoxConstraints(maxWidth: AppPlatform.useDesktopLayout ? 620 : double.infinity),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 0.88,
        child: _SeriesEpisodesSheet(
          series: series,
          loadEpisodes: () => ref.read(iptvServiceProvider).seriesEpisodes(series),
          onPlay: (episode) {
            Navigator.pop(sheetContext);
            final label = 'S${episode.season} E${episode.episode}';
            widget.onPlay(episode.url, '${series.name} · $label');
          },
        ),
      ),
    );
  }
}

class _PosterCard extends StatelessWidget {
  final String title;
  final String poster;
  final String rating;
  final IconData icon;
  final VoidCallback onTap;

  const _PosterCard({
    required this.title,
    required this.poster,
    required this.rating,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: Colors.white.withValues(alpha: 0.06),
      alignment: Alignment.center,
      child: Icon(icon, color: Colors.white24, size: 34),
    );
    final ratingValue = double.tryParse(rating);
    return FocusableTap(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  poster.startsWith('http')
                      ? CachedNetworkImage(
                          imageUrl: poster,
                          fit: BoxFit.cover,
                          memCacheWidth: 300,
                          placeholder: (_, __) => placeholder,
                          errorWidget: (_, __, ___) => placeholder,
                        )
                      : placeholder,
                  if (ratingValue != null && ratingValue > 0)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '★ ${ratingValue.toStringAsFixed(1)}',
                          style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.25),
          ),
        ],
      ),
    );
  }
}

class _SeriesEpisodesSheet extends StatefulWidget {
  final IptvSeries series;
  final Future<List<IptvEpisode>> Function() loadEpisodes;
  final ValueChanged<IptvEpisode> onPlay;

  const _SeriesEpisodesSheet({
    required this.series,
    required this.loadEpisodes,
    required this.onPlay,
  });

  @override
  State<_SeriesEpisodesSheet> createState() => _SeriesEpisodesSheetState();
}

class _SeriesEpisodesSheetState extends State<_SeriesEpisodesSheet> {
  late Future<List<IptvEpisode>> _future = widget.loadEpisodes();
  int? _season;

  @override
  Widget build(BuildContext context) {
    final accent = NivioTheme.accentColorOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.series.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        if (widget.series.plot.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              widget.series.plot,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.35),
            ),
          ),
        Expanded(
          child: FutureBuilder<List<IptvEpisode>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          'Could not load episodes: ${snap.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white60),
                        ),
                      ),
                      TextButton(
                        onPressed: () => setState(() => _future = widget.loadEpisodes()),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              final episodes = snap.data ?? const <IptvEpisode>[];
              if (episodes.isEmpty) {
                return const Center(child: Text('No episodes available', style: TextStyle(color: Colors.white60)));
              }
              final seasons = episodes.map((e) => e.season).toSet().toList()..sort();
              final season = (_season != null && seasons.contains(_season)) ? _season! : seasons.first;
              final shown = episodes.where((e) => e.season == season).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (seasons.length > 1)
                    SizedBox(
                      height: 46,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        children: [
                          for (final s in seasons)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text('Season $s'),
                                selected: s == season,
                                onSelected: (_) => setState(() => _season = s),
                                selectedColor: accent.withValues(alpha: 0.3),
                                backgroundColor: Colors.white.withValues(alpha: 0.06),
                                labelStyle: TextStyle(color: s == season ? Colors.white : Colors.white70),
                                side: BorderSide(color: s == season ? accent : Colors.white12),
                                showCheckmark: false,
                              ),
                            ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: AppListView.builder(
                      padding: EdgeInsets.fromLTRB(12, 4, 12, 16 + MediaQuery.paddingOf(context).bottom),
                      itemCount: shown.length,
                      itemBuilder: (context, i) {
                        final e = shown[i];
                        final title = e.title.isNotEmpty ? e.title : 'Episode ${e.episode}';
                        return FocusableInkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.onPlay(e),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 36,
                                  child: Text(
                                    '${e.episode}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: accent, fontSize: 16, fontWeight: FontWeight.w800),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                      if (e.plot.isNotEmpty)
                                        Text(e.plot, maxLines: 2, overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                const Icon(PhosphorIconsRegular.play, color: Colors.white54, size: 18),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
