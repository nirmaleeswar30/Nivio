import 'package:flutter/material.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/screens/new_episodes_screen.dart';
import 'package:nivio/screens/watchlist_screen.dart';

class LibraryScreen extends StatefulWidget {
  final int initialTab;

  const LibraryScreen({super.key, this.initialTab = 0});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = widget.initialTab.clamp(0, 1);
    if (nextIndex != _tabController.index) {
      _tabController.animateTo(nextIndex);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: const [
                    Text(
                      'Library',
                      style: TextStyle(
                        color: NivioTheme.netflixWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: AnimatedBuilder(
                    animation: _tabController.animation ?? _tabController,
                    builder: (context, child) {
                      final animationValue =
                          _tabController.animation?.value ??
                          _tabController.index.toDouble();
                      final activeIndex = animationValue.round().clamp(
                        0,
                        _tabController.length - 1,
                      );
                      final indicatorPadding = activeIndex == 0
                          ? const EdgeInsets.fromLTRB(6, 6, 10, 6)
                          : const EdgeInsets.fromLTRB(10, 6, 6, 6);
                      return TabBar(
                        controller: _tabController,
                        indicatorSize: TabBarIndicatorSize.tab,
                        indicatorPadding: indicatorPadding,
                        indicator: BoxDecoration(
                          color: NivioTheme.accentColorOf(
                            context,
                          ).withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        dividerColor: Colors.transparent,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white70,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                        tabs: const [
                          Tab(text: 'New Episodes'),
                          Tab(text: 'Watchlist'),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    const NewEpisodesScreen(embedded: true),
                    const WatchlistScreen(embedded: true),
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
