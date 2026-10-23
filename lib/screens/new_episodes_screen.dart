import 'package:cached_network_image/cached_network_image.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nivio/core/constants.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/services/schedule_api_service.dart';
import 'package:nivio/services/episode_check_service.dart';
import 'package:nivio/widgets/countdown_timer_widget.dart';
import 'package:nivio/widgets/app_scroll_view.dart';


class NewEpisodesScreen extends StatefulWidget {
  final bool embedded;

  const NewEpisodesScreen({super.key, this.embedded = false});

  @override
  State<NewEpisodesScreen> createState() => _NewEpisodesScreenState();
}

class _NewEpisodesScreenState extends State<NewEpisodesScreen> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  bool _watchlistOnly = true;
  bool _isLoading = false;
  List<ScheduleItem> _schedules = [];
  
  late final PageController _pageController;
  late final ScrollController _scrollController;
  final int _initialPage = 500;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _initialPage);
    _scrollController = ScrollController();
    _selectedDay = _focusedDay;
    _fetchSchedule();
    
    // Clear notification indicator on home screen
    EpisodeCheckService.markAllAsRead();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  DateTime _getStartOfWeek(DateTime date) {
    return date.subtract(Duration(days: date.weekday - 1));
  }

  Future<void> _fetchSchedule() async {
    if (_selectedDay == null) return;
    setState(() => _isLoading = true);
    
    final items = await ScheduleApiService.fetchScheduleForDate(
      _selectedDay!, 
      watchlistOnly: _watchlistOnly,
    );
    
    if (mounted) {
      setState(() {
        _schedules = items;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF151922), NivioTheme.netflixBlack],
        ),
      ),
      child: SafeArea(
        top: !widget.embedded,
        bottom: false,
        child: AppCustomScrollView(
          controller: _scrollController,
          scrollSpeed: 2.0,
          silkyScrollDuration: const Duration(milliseconds: 500),
          animationCurve: Curves.easeOutQuart,
          slivers: [
            if (!widget.embedded) SliverToBoxAdapter(child: _buildHeader()),
            // On desktop the 56px nav rail overlays the page's left edge;
            // inset the calendar so the previous-week arrow clears it (the
            // day row then lines up with the grid's 68px inset below).
            SliverPadding(
              padding: EdgeInsets.only(left: isDesktop ? 52 : 0),
              sliver: SliverToBoxAdapter(child: _buildCalendar()),
            ),
            SliverToBoxAdapter(child: _buildFilters()),
            if (_isLoading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: Colors.white)),
              )
            else if (_schedules.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: EdgeInsets.only(
                  top: 8, 
                  bottom: isDesktop ? 16 : (widget.embedded ? 96 : 16),
                  left: isDesktop ? 68 : 0,
                  right: isDesktop ? 20 : 0,
                ),
                sliver: isDesktop
                    ? SliverGrid(
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 180,
                          childAspectRatio: 0.72,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 14,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildDesktopScheduleCard(_schedules[index]);
                          },
                          childCount: _schedules.length,
                          addRepaintBoundaries: false,
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            return _buildScheduleItem(_schedules[index]);
                          },
                          childCount: _schedules.length,
                          addRepaintBoundaries: false,
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.calendar_month_rounded, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          const Text(
            'Release Calendar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          Tooltip(
            message: 'Air times reflect original TV broadcast schedules in your local time.\nStreaming releases (Crunchyroll, Netflix) typically launch 30–90 min later.',
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.info_outline_rounded, color: Colors.white70, size: 20),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMonthPicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _focusedDay,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: ColorScheme.dark(
              primary: NivioTheme.accentColorOf(context),
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E1E),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      final nowStart = _getStartOfWeek(DateTime.now());
      final pickedStart = _getStartOfWeek(picked);
      final differenceInWeeks = pickedStart.difference(nowStart).inDays ~/ 7;
      final targetPage = _initialPage + differenceInWeeks;
      
      _pageController.animateToPage(
        targetPage,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
      setState(() {
        _focusedDay = picked;
        _selectedDay = picked;
      });
      _fetchSchedule();
    }
  }

  Widget _buildCalendar() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                onPressed: () {
                  _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                },
              ),
              InkWell(
                onTap: _showMonthPicker,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat.yMMMM().format(_focusedDay),
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                onPressed: () {
                  _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) {
              final isWeekend = d == 'Sat' || d == 'Sun';
              return SizedBox(
                width: 32,
                child: Text(
                  d,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: isWeekend ? Colors.white54 : Colors.white70, fontSize: 12),
                ),
              );
            }).toList(),
          ),
        ),
        SizedBox(
          height: 50,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              final startOfWeek = _getStartOfWeek(DateTime.now()).add(Duration(days: (index - _initialPage) * 7));
              setState(() {
                _focusedDay = startOfWeek;
              });
            },
            itemBuilder: (context, index) {
              final startOfWeek = _getStartOfWeek(DateTime.now()).add(Duration(days: (index - _initialPage) * 7));
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: List.generate(7, (i) {
                    final date = startOfWeek.add(Duration(days: i));
                    final isSelected = isSameDay(_selectedDay, date);
                    final isToday = isSameDay(DateTime.now(), date);
                    final isWeekend = date.weekday == 6 || date.weekday == 7;

                    Color bgColor = Colors.transparent;
                    if (isSelected) bgColor = NivioTheme.accentColorOf(context);
                    else if (isToday) bgColor = NivioTheme.accentColorOf(context).withValues(alpha: 0.3);

                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedDay = date;
                          _focusedDay = date;
                        });
                        _fetchSchedule();
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: bgColor,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: isSelected || isToday ? Colors.white : (isWeekend ? Colors.white70 : Colors.white),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('My Watchlist'),
            selected: _watchlistOnly,
            onSelected: (val) {
              if (val) {
                setState(() => _watchlistOnly = true);
                _fetchSchedule();
              }
            },
            selectedColor: NivioTheme.accentColorOf(context).withValues(alpha: 0.2),
            labelStyle: TextStyle(
              color: _watchlistOnly ? NivioTheme.accentColorOf(context) : Colors.white70,
              fontWeight: _watchlistOnly ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.white10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.transparent),
            ),
          ),
          const SizedBox(width: 12),
          ChoiceChip(
            label: const Text('Discover'),
            selected: !_watchlistOnly,
            onSelected: (val) {
              if (val) {
                setState(() => _watchlistOnly = false);
                _fetchSchedule();
              }
            },
            selectedColor: NivioTheme.accentColorOf(context).withValues(alpha: 0.2),
            labelStyle: TextStyle(
              color: !_watchlistOnly ? NivioTheme.accentColorOf(context) : Colors.white70,
              fontWeight: !_watchlistOnly ? FontWeight.bold : FontWeight.normal,
            ),
            backgroundColor: Colors.white10,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.transparent),
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Air times reflect original TV broadcast schedules in your local time.\nStreaming releases (Crunchyroll, Netflix) typically launch 30–90 min later.',
            triggerMode: TooltipTriggerMode.tap,
            showDuration: const Duration(seconds: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            textStyle: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF1E222D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white24, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Padding(
              padding: EdgeInsets.all(6.0),
              child: Icon(Icons.info_outline_rounded, color: Colors.white60, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.calendar_today_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
        const SizedBox(height: 16),
        Text(
          _watchlistOnly 
            ? 'No releases in your watchlist today'
            : 'No upcoming releases found today',
          style: const TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }



  Widget _buildScheduleItem(ScheduleItem item) {
    final now = DateTime.now();
    final isToday = item.releaseDate.year == now.year && 
                    item.releaseDate.month == now.month && 
                    item.releaseDate.day == now.day;
    final isPast = item.releaseDate.isBefore(now);
    
    String statusText;
    if (isToday) {
      statusText = (item.hasPreciseTime && isPast) ? 'Aired Today' : 'Airing Today';
    } else if (item.releaseDate.isBefore(DateTime(now.year, now.month, now.day))) {
      statusText = 'Aired';
    } else {
      statusText = 'Upcoming';
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
             if (item.id == -1) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Details unavailable. Please search for this show.')),
                );
                return;
             }
             final type = item.mediaType;
             final season = item.seasonNumber ?? 1;
             final episode = item.episodeNumber ?? 1;
             context.push('/player/${item.id}?type=$type&season=$season&episode=$episode');
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Poster
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: item.posterPath != null
                      ? CachedNetworkImage(
                          imageUrl: item.posterPath!.startsWith('http') 
                              ? item.posterPath! 
                              : '$tmdbImageBaseUrl/$posterSize${item.posterPath}',
                          width: 70,
                          height: 105,
                          memCacheWidth: 200,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _buildPlaceholder(),
                        )
                      : _buildPlaceholder(),
                ),
                const SizedBox(width: 16),
                
                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: NivioTheme.accentColorOf(context).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.mediaType.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: NivioTheme.accentColorOf(context),
                              ),
                            ),
                          ),
                          if (item.episodeNumber != null) ...[
                            const SizedBox(width: 8),
                            Text(
                              'Episode ${item.episodeNumber}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      
                      // Timing
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded, 
                            size: 14, 
                            color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                          ),
                          const SizedBox(width: 4),
                          if (item.hasPreciseTime) ...[
                            CountdownTimerWidget(
                              targetDate: item.releaseDate,
                              textStyle: TextStyle(
                                color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Broadcast air time (local). Streaming/simulcast drops ~30-90m later.',
                              triggerMode: TooltipTriggerMode.tap,
                              showDuration: const Duration(seconds: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E222D),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24, width: 1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.5),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Text(
                                '• ${DateFormat('h:mm a').format(item.releaseDate)}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ),
                          ] else ...[
                            Text(
                              statusText,
                              style: TextStyle(
                                color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ),
    ),
  );
}

  Widget _buildPlaceholder() {
    return Container(
      width: 70,
      height: 105,
      color: Colors.white10,
      child: const Icon(Icons.movie_creation_outlined, color: Colors.white54),
    );
  }

  Widget _buildDesktopScheduleCard(ScheduleItem item) {
    final now = DateTime.now();
    final isToday = item.releaseDate.year == now.year && 
                    item.releaseDate.month == now.month && 
                    item.releaseDate.day == now.day;
    final isPast = item.releaseDate.isBefore(now);
    
    String statusText;
    if (isToday) {
      statusText = (item.hasPreciseTime && isPast) ? 'Aired Today' : 'Airing Today';
    } else if (item.releaseDate.isBefore(DateTime(now.year, now.month, now.day))) {
      statusText = 'Aired';
    } else {
      statusText = 'Upcoming';
    }

    return Container(
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            if (item.id == -1) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Details unavailable. Please search for this show.')),
              );
              return;
            }
            final type = item.mediaType;
            final season = item.seasonNumber ?? 1;
            final episode = item.episodeNumber ?? 1;
            context.push('/player/${item.id}?type=$type&season=$season&episode=$episode');
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Poster
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.posterPath != null
                        ? CachedNetworkImage(
                              imageUrl: item.posterPath!.startsWith('http') 
                                  ? item.posterPath! 
                                  : '$tmdbImageBaseUrl/w342${item.posterPath}',
                              fit: BoxFit.cover,
                              memCacheWidth: 300,
                              errorWidget: (_, __, ___) => const Center(
                                child: Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 40),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.movie_creation_outlined, color: Colors.white54, size: 40),
                            ),
                      // MediaType badge top-left
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NivioTheme.accentColorOf(context),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.mediaType.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      // Episode number bottom-right
                      if (item.episodeNumber != null)
                        Positioned(
                          bottom: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'EP ${item.episodeNumber}',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Info Area
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Timing
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded, 
                          size: 12, 
                          color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: item.hasPreciseTime
                              ? CountdownTimerWidget(
                                  targetDate: item.releaseDate,
                                  textStyle: TextStyle(
                                    color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                )
                              : Text(
                                  statusText,
                                  style: TextStyle(
                                    color: isPast ? Colors.white54 : NivioTheme.accentColorOf(context),
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
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
            ],
          ),
      ),
    ),
  );
}
}
