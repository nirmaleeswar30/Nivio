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
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: isDesktop ? 290 : double.infinity,
                    child: _ModernTabSwitcher(
                      index: _index,
                      onChanged: (i) => setState(() => _index = i),
                      isDesktop: isDesktop,
                    ),
                  ),
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

class _ModernTabSwitcher extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;
  final bool isDesktop;

  const _ModernTabSwitcher({
    required this.index,
    required this.onChanged,
    this.isDesktop = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = NivioTheme.accentColorOf(context);
    final items = const [
      (label: 'Live TV', iconFill: PhosphorIconsFill.television, iconReg: PhosphorIconsRegular.television),
      (label: 'Sports', iconFill: PhosphorIconsFill.trophy, iconReg: PhosphorIconsRegular.trophy),
    ];

    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: const Color(0xFF141720),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: isDesktop ? MainAxisSize.min : MainAxisSize.max,
        children: List.generate(items.length, (i) {
          final selected = i == index;
          final item = items[i];
          final tabWidget = _TabItem(
            label: item.label,
            icon: selected ? item.iconFill : item.iconReg,
            selected: selected,
            accentColor: accent,
            onTap: () => onChanged(i),
          );

          return Expanded(child: tabWidget);
        }),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color accentColor;
  final VoidCallback onTap;

  const _TabItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.selected
                ? widget.accentColor
                : (_hovered ? Colors.white.withValues(alpha: 0.08) : Colors.transparent),
            borderRadius: BorderRadius.circular(9),
            boxShadow: widget.selected
                ? [
                    BoxShadow(
                      color: widget.accentColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 16,
                color: widget.selected
                    ? Colors.white
                    : (_hovered ? Colors.white : Colors.white60),
              ),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  color: widget.selected
                      ? Colors.white
                      : (_hovered ? Colors.white : Colors.white60),
                  fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
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
  String _selectedCategory = 'All';

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

  List<String> get _categories {
    final set = <String>{};
    for (final m in _matches) {
      final cat = m.category.trim();
      if (cat.isNotEmpty) {
        set.add(cat);
      }
    }
    final list = set.toList()..sort();
    return ['All', ...list];
  }

  List<SportsMatch> get _filteredMatches {
    if (_selectedCategory == 'All') return _matches;
    return _matches.where((m) =>
      m.category.toLowerCase() == _selectedCategory.toLowerCase() ||
      m.category.toLowerCase().contains(_selectedCategory.toLowerCase())
    ).toList();
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
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    showModalBottomSheet(
      context: context,
      backgroundColor: NivioTheme.netflixDarkGrey,
      constraints: BoxConstraints(maxWidth: isDesktop ? 500 : double.infinity),
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

    final filtered = _filteredMatches;
    final liveCount = _matches.where((m) => m.isLikelyLive).length;
    final cats = _categories;

    return RefreshIndicator(
      onRefresh: _load,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Category filter chips
              if (cats.length > 1) ...[
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: leftPad),
                    itemCount: cats.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, idx) {
                      final cat = cats[idx];
                      final count = cat == 'All'
                          ? _matches.length
                          : _matches.where((m) => m.category.toLowerCase() == cat.toLowerCase()).length;
                      final isSelected = _selectedCategory == cat;
                      final accent = NivioTheme.accentColorOf(context);

                      return _SportsCategoryChip(
                        label: '$cat ($count)',
                        isSelected: isSelected,
                        accentColor: accent,
                        onTap: () => setState(() => _selectedCategory = cat),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
              ],

              // Sub-header status bar
              Padding(
                padding: EdgeInsets.fromLTRB(leftPad, 4, 16, 8),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: liveCount > 0 ? const Color(0xFFEF4444) : Colors.amber,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (liveCount > 0 ? const Color(0xFFEF4444) : Colors.amber).withValues(alpha: 0.6),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      liveCount > 0
                          ? '$liveCount LIVE EVENT${liveCount > 1 ? 'S' : ''}'
                          : '${_matches.length} SCHEDULED EVENT${_matches.length > 1 ? 'S' : ''}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (_selectedCategory != 'All') ...[
                      const SizedBox(width: 8),
                      Text(
                        '· $_selectedCategory (${filtered.length})',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    const Spacer(),
                    IconButton(
                      icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
                      tooltip: 'Refresh sports',
                      color: Colors.white60,
                      onPressed: _load,
                    ),
                  ],
                ),
              ),

              // Match Grid
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsRegular.trophy,
                                size: 40, color: Colors.white.withValues(alpha: 0.3)),
                            const SizedBox(height: 12),
                            Text(
                              'No events found in "$_selectedCategory"',
                              style: const TextStyle(color: Colors.white60, fontSize: 14),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => setState(() => _selectedCategory = 'All'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: const Text('Show all categories'),
                            ),
                          ],
                        ),
                      )
                    : AppGridView.builder(
                        padding: EdgeInsets.fromLTRB(leftPad, 4, 16, 28),
                        cacheExtent: isDesktop ? 1000 : 350,
                        scrollSpeed: 2.0,
                        silkyScrollDuration: const Duration(milliseconds: 500),
                        animationCurve: Curves.easeOutQuart,
                        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: isDesktop ? 440 : 480,
                          childAspectRatio: isDesktop ? 1.85 : 1.9,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) => _SportsMatchCard(
                          key: ValueKey(filtered[index].id),
                          match: filtered[index],
                          onOpen: () => _openMatch(filtered[index]),
                        ),
                      ),
              ),
            ],
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
}

class _SportsCategoryChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final Color accentColor;
  final VoidCallback onTap;

  const _SportsCategoryChip({
    required this.label,
    required this.isSelected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_SportsCategoryChip> createState() => _SportsCategoryChipState();
}

class _SportsCategoryChipState extends State<_SportsCategoryChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? widget.accentColor.withValues(alpha: 0.9)
                : (_hovered
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.isSelected
                  ? widget.accentColor
                  : (_hovered
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08)),
              width: 1,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              color: widget.isSelected
                  ? Colors.white
                  : (_hovered ? Colors.white : Colors.white70),
              fontSize: 12.5,
              fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _SportsMatchCard extends StatefulWidget {
  final SportsMatch match;
  final VoidCallback onOpen;

  const _SportsMatchCard({
    super.key,
    required this.match,
    required this.onOpen,
  });

  @override
  State<_SportsMatchCard> createState() => _SportsMatchCardState();
}

class _SportsMatchCardState extends State<_SportsMatchCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final match = widget.match;
    final accent = NivioTheme.accentColorOf(context);
    final isLive = match.isLikelyLive;
    final time = match.startTime;

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onOpen,
          behavior: HitTestBehavior.opaque,
          child: AnimatedScale(
            scale: _isHovered ? 1.025 : 1.0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: _isHovered ? const Color(0xFF1B202D) : const Color(0xFF141720),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isHovered
                      ? accent.withValues(alpha: 0.5)
                      : Colors.white.withValues(alpha: 0.08),
                  width: _isHovered ? 1.5 : 1.0,
                ),
                boxShadow: _isHovered
                    ? [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.55),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Row: Category + LIVE/Kickoff Time + Hot Tag
                  Row(
                    children: [
                      if (match.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            match.category.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      if (match.popular) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(PhosphorIconsFill.fire, size: 11, color: Colors.amber),
                              SizedBox(width: 3),
                              Text(
                                'HOT',
                                style: TextStyle(
                                  color: Colors.amber,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (isLive)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: const [
                              BoxShadow(color: Color(0x66DC2626), blurRadius: 6),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 5,
                                height: 5,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Text(
                                'LIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        )
                      else if (time != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsRegular.clock, size: 12, color: Colors.white60),
                              const SizedBox(width: 4),
                              Text(
                                _formatTime(time),
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),

                  // Center Matchup Area
                  Expanded(
                    child: match.hasTeams
                        ? _buildTeamsMatchup(match)
                        : _buildEventMatchup(match),
                  ),

                  // Bottom Action Row
                  Row(
                    children: [
                      const Icon(PhosphorIconsRegular.broadcast, size: 14, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text(
                        '${match.sources.length} stream${match.sources.length == 1 ? '' : 's'}${match.sources.any((s) => s.source.isNotEmpty) ? ' · HD' : ''}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const Spacer(),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6.5),
                        decoration: BoxDecoration(
                          color: _isHovered ? accent : accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _isHovered ? accent : accent.withValues(alpha: 0.35),
                          ),
                          boxShadow: _isHovered
                              ? [
                                  BoxShadow(
                                    color: accent.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              PhosphorIconsFill.play,
                              size: 11,
                              color: _isHovered ? Colors.white : accent,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              isLive ? 'Watch Live' : 'Watch',
                              style: TextStyle(
                                color: _isHovered ? Colors.white : accent,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTeamsMatchup(SportsMatch match) {
    return Row(
      children: [
        // Home Team
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _teamBadge(match.homeBadge, match.homeTeam),
              const SizedBox(height: 8),
              Text(
                match.homeTeam,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // VS Divider
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            alignment: Alignment.center,
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
        // Away Team
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _teamBadge(match.awayBadge, match.awayTeam),
              const SizedBox(height: 8),
              Text(
                match.awayTeam,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _teamBadge(String url, String name) {
    final hasUrl = url.isNotEmpty && (url.startsWith('http://') || url.startsWith('https://'));
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(5),
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => _badgeLetterFallback(name),
            )
          : _badgeLetterFallback(name),
    );
  }

  Widget _badgeLetterFallback(String name) {
    final char = name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
    return Center(
      child: Text(
        char,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.6),
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEventMatchup(SportsMatch match) {
    final img = match.homeBadge.isNotEmpty ? match.homeBadge : match.poster;
    final hasUrl = img.isNotEmpty && (img.startsWith('http://') || img.startsWith('https://'));

    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: hasUrl
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: img,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Icon(
                      PhosphorIconsRegular.trophy,
                      color: Colors.white.withValues(alpha: 0.35),
                      size: 26,
                    ),
                  ),
                )
              : Icon(
                  PhosphorIconsRegular.trophy,
                  color: Colors.white.withValues(alpha: 0.35),
                  size: 26,
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                match.title.isNotEmpty ? match.title : 'Live Sports Event',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  height: 1.25,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (match.category.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  match.category,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ],
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
