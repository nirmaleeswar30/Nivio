import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:phosphoricons_flutter/phosphoricons_flutter.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/screens/iptv_screen.dart';
import 'package:nivio/services/sports_service.dart';
import 'package:nivio/models/sports_match.dart';
import 'package:nivio/widgets/app_scroll_view.dart';

/// Combined "TV / Sports" tab: live sports events + IPTV / live TV channels.
class TvSportsScreen extends ConsumerStatefulWidget {
  const TvSportsScreen({super.key});

  @override
  ConsumerState<TvSportsScreen> createState() => _TvSportsScreenState();
}

class _TvSportsScreenState extends ConsumerState<TvSportsScreen> {
  int _index = 0; // 0 = Live TV, 1 = Sports

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return Scaffold(
      backgroundColor: NivioTheme.netflixBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF151922), NivioTheme.netflixBlack],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(isDesktop ? 68 : 16, 14, 16, 10),
                child: _SegmentedToggle(
                  index: _index,
                  labels: const ['Live TV', 'Sports'],
                  onChanged: (i) => setState(() => _index = i),
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: const [
                    IptvScreen(embedded: true),
                    SportsView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedToggle extends StatelessWidget {
  final int index;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _SegmentedToggle({
    required this.index,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final accent = NivioTheme.accentColorOf(context);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final selected = i == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(26),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[i],
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white60,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

/// Live sports events list.
class SportsView extends ConsumerStatefulWidget {
  const SportsView({super.key});

  @override
  ConsumerState<SportsView> createState() => _SportsViewState();
}

class _SportsViewState extends ConsumerState<SportsView>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<SportsMatch> _matches = [];
  bool _resolving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await ref.read(sportsServiceProvider).fetchMatches();
      if (!mounted) return;
      setState(() {
        _matches = matches;
        _loading = false;
        if (matches.isEmpty) _error = 'No live events right now.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load live sports.';
      });
    }
  }

  Future<void> _openMatch(SportsMatch match) async {
    if (_resolving) return;
    setState(() => _resolving = true);
    try {
      final streams = await ref.read(sportsServiceProvider).resolveStreams(match);
      if (!mounted) return;
      if (streams.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No playable stream for this event yet.')),
        );
        return;
      }
      if (streams.length == 1) {
        _play(match, streams.first);
      } else {
        _showStreamPicker(match, streams);
      }
    } finally {
      if (mounted) setState(() => _resolving = false);
    }
  }

  void _play(SportsMatch match, SportsStream stream) {
    final uri = Uri(
      path: '/player/0',
      queryParameters: {
        'directStreamUrl': stream.url,
        'directStreamTitle': match.title.isNotEmpty ? match.title : 'Live Sports',
        'directStreamReferer': SportsService.playbackReferer,
        'isLive': 'true',
      },
    );
    context.push(uri.toString());
  }

  void _showStreamPicker(SportsMatch match, List<SportsStream> streams) {
    showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Select stream',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              ...streams.map((s) => ListTile(
                    leading: Icon(PhosphorIconsRegular.broadcast,
                        color: NivioTheme.accentColorOf(context)),
                    title: Text(
                      'Stream ${s.streamNo}${s.hd ? ' · HD' : ''}',
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      s.language.isNotEmpty ? s.language : s.label,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      _play(match, s);
                    },
                  )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final leftPad = isDesktop ? 68.0 : 16.0;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_matches.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIconsRegular.broadcast,
                size: 46, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 14),
            Text(_error ?? 'No live events right now.',
                style: const TextStyle(color: Colors.white60)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: Stack(
        children: [
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 850),
              child: AppListView.builder(
                padding: EdgeInsets.fromLTRB(leftPad, 4, 16, 24),
                cacheExtent: 250,
                scrollSpeed: 2.0,
                silkyScrollDuration: const Duration(milliseconds: 500),
                animationCurve: Curves.easeOutQuart,
                itemCount: _matches.length,
                itemBuilder: (context, index) => _matchTile(_matches[index]),
              ),
            ),
          ),
          if (_resolving)
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _matchTile(SportsMatch match) {
    final live = match.isLikelyLive;
    final time = match.startTime;
    final subtitle = live
        ? 'LIVE · ${match.category}'
        : (time != null
            ? '${_formatTime(time)} · ${match.category}'
            : match.category);
    return RepaintBoundary(
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openMatch(match),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  _poster(match),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          match.title.isNotEmpty ? match.title : 'Live Event',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (live)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('LIVE',
                                    style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                              ),
                            Flexible(
                              child: Text(
                                live ? match.category : subtitle,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: NivioTheme.accentColorOf(context).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(PhosphorIconsRegular.play,
                        color: NivioTheme.accentColorOf(context), size: 16),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _poster(SportsMatch match) {
    final img = match.homeBadge.isNotEmpty ? match.homeBadge : match.poster;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: img.isNotEmpty
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: img,
                fit: BoxFit.contain,
                errorWidget: (c, u, e) => Icon(PhosphorIconsRegular.trophy,
                    color: Colors.white.withValues(alpha: 0.3), size: 22),
              ),
            )
          : Icon(PhosphorIconsRegular.trophy,
              color: Colors.white.withValues(alpha: 0.3), size: 22),
    );
  }

  String _formatTime(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ap = local.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
