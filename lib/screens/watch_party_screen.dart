import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nivio/core/theme.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/services/watch_party/watch_party_service_supabase.dart';

class WatchPartyScreen extends ConsumerStatefulWidget {
  const WatchPartyScreen({
    super.key,
    this.embedded = false,
    this.preselectedMediaId,
    this.preselectedMediaType,
    this.preselectedSeason = 1,
    this.preselectedMediaTitle,
  });

  final bool embedded;
  final int? preselectedMediaId;
  final String? preselectedMediaType;
  final int preselectedSeason;
  final String? preselectedMediaTitle;

  @override
  ConsumerState<WatchPartyScreen> createState() => _WatchPartyScreenState();
}

class _WatchPartyScreenState extends ConsumerState<WatchPartyScreen> {
  final TextEditingController _codeController = TextEditingController();
  StreamSubscription<WatchPartyPlaybackState>? _playbackSubscription;
  bool _isLoading = false;
  bool _hasNavigatedToPlayer = false;
  bool _isControllerUpdating = false;
  int? _selectedMediaId;
  String? _selectedMediaType;
  int _selectedSeason = 1;
  String? _selectedMediaTitle;

  @override
  void initState() {
    super.initState();
    _selectedMediaId = widget.preselectedMediaId;
    _selectedMediaType = widget.preselectedMediaType;
    _selectedSeason = widget.preselectedSeason;
    _selectedMediaTitle = widget.preselectedMediaTitle;

    final service = ref.read(watchPartyServiceProvider);
    if (service != null) {
      _playbackSubscription = service.playbackStream.listen(
        _handlePlaybackSync,
      );
    }
  }

  @override
  void didUpdateWidget(covariant WatchPartyScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final hasIncomingSelection =
        widget.preselectedMediaId != null &&
        (widget.preselectedMediaType ?? '').isNotEmpty;
    final incomingChanged =
        widget.preselectedMediaId != oldWidget.preselectedMediaId ||
        widget.preselectedMediaType != oldWidget.preselectedMediaType ||
        widget.preselectedSeason != oldWidget.preselectedSeason ||
        widget.preselectedMediaTitle != oldWidget.preselectedMediaTitle;

    // Keep local selection in sync when a new title is passed from media detail.
    if (hasIncomingSelection && incomingChanged) {
      setState(() {
        _selectedMediaId = widget.preselectedMediaId;
        _selectedMediaType = widget.preselectedMediaType;
        _selectedSeason = widget.preselectedSeason;
        _selectedMediaTitle = widget.preselectedMediaTitle;
      });
    }
  }

  @override
  void dispose() {
    _playbackSubscription?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  String _playerRoute({
    required int mediaId,
    required String mediaType,
    int? providerIndex,
    required int season,
    required int episode,
    required String partyCode,
    required bool isHost,
  }) {
    return Uri(
      path: '/player/$mediaId',
      queryParameters: {
        'season': '$season',
        'episode': '$episode',
        'type': mediaType,
        if (providerIndex != null) 'provider': '$providerIndex',
        'partyCode': partyCode.toUpperCase(),
        'partyRole': isHost ? 'host' : 'participant',
      },
    ).toString();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _handlePlaybackSync(WatchPartyPlaybackState playback) async {
    final service = ref.read(watchPartyServiceProvider);
    if (!mounted || service == null || _hasNavigatedToPlayer) return;
    if (!service.isInSession || service.sessionCode == null) return;
    if (service.isHost) return;

    _hasNavigatedToPlayer = true;
    context.push(
      _playerRoute(
        mediaId: playback.mediaId,
        mediaType: playback.mediaType.isEmpty ? 'movie' : playback.mediaType,
        providerIndex: playback.providerIndex,
        season: playback.season,
        episode: playback.episode,
        partyCode: service.sessionCode!,
        isHost: service.isHost,
      ),
    );
  }

  Future<void> _startParty() async {
    final service = ref.read(watchPartyServiceProvider);
    if (service == null) {
      _showMessage('Watch Party unavailable');
      return;
    }

    setState(() => _isLoading = true);
    final code = await service.createSession();
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (code == null) {
      _showMessage('Failed to create watch party');
      return;
    }

    if (_selectedMediaId == null || (_selectedMediaType ?? '').isEmpty) {
      _showMessage('Party started. Pick a title to begin playback.');
      return;
    }

    _hasNavigatedToPlayer = true;
    context.push(
      _playerRoute(
        mediaId: _selectedMediaId!,
        mediaType: _selectedMediaType!,
        season: _selectedSeason,
        episode: 1,
        partyCode: code,
        isHost: true,
      ),
    );
  }

  void _clearSelectedTitle() {
    setState(() {
      _selectedMediaId = null;
      _selectedMediaType = null;
      _selectedSeason = 1;
      _selectedMediaTitle = null;
    });
    _showMessage('Title unselected');
  }

  Future<void> _joinParty() async {
    final service = ref.read(watchPartyServiceProvider);
    if (service == null) {
      _showMessage('Watch Party unavailable');
      return;
    }

    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      _showMessage('Enter a valid 6-character code');
      return;
    }

    setState(() => _isLoading = true);
    final joined = await service.joinSession(code);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (!joined) {
      _showMessage('No watch party found for this code');
      return;
    }

    final playback = service.currentSession?.playbackState;
    if (playback != null) {
      _hasNavigatedToPlayer = true;
      context.push(
        _playerRoute(
          mediaId: playback.mediaId,
          mediaType: playback.mediaType.isEmpty ? 'movie' : playback.mediaType,
          providerIndex: playback.providerIndex,
          season: playback.season,
          episode: playback.episode,
          partyCode: code,
          isHost: false,
        ),
      );
      return;
    }

    await service.requestStateSync(reason: 'participant_joined_waiting');
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      final currentService = ref.read(watchPartyServiceProvider);
      if (currentService == null ||
          !currentService.isInSession ||
          currentService.isHost ||
          _hasNavigatedToPlayer) {
        return;
      }
      unawaited(currentService.requestStateSync(reason: 'participant_retry'));
    });

    _showMessage('Joined. Waiting for host to start playback...');
  }

  Future<void> _leaveOrEndParty(WatchPartyServiceSupabase service) async {
    if (service.isHost) {
      await service.endSession();
      _showMessage('Watch party ended');
    } else {
      await service.leaveSession();
      _showMessage('Left watch party');
    }
    if (!mounted) return;
    setState(() {
      _hasNavigatedToPlayer = false;
    });
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code.toUpperCase()));
    _showMessage('Code copied');
  }

  Future<void> _setPlaybackController(
    WatchPartyServiceSupabase service, {
    required String? participantId,
    String? participantName,
  }) async {
    if (_isControllerUpdating) return;

    setState(() => _isControllerUpdating = true);
    await service.setPlaybackController(participantId);
    if (!mounted) return;
    setState(() => _isControllerUpdating = false);

    if (participantId == null) {
      _showMessage('Playback control returned to host');
    } else {
      _showMessage(
        participantName == null || participantName.trim().isEmpty
            ? 'Playback control delegated'
            : 'Playback control given to ${participantName.trim()}',
      );
    }
  }

  String _participantInitials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildParticipantAvatar(
    WatchPartyParticipant participant, {
    double radius = 12,
  }) {
    final photoUrl = (participant.photoUrl ?? '').trim();
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.white12,
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: participant.isHost
          ? NivioTheme.accentColorOf(context).withValues(alpha: 0.35)
          : Colors.white12,
      child: Text(
        _participantInitials(participant.name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSessionCard(
    WatchPartyServiceSupabase service,
    WatchPartySession session,
  ) {
    final playback = session.playbackState;
    WatchPartyParticipant? currentController;
    final controllerId = session.controllerId;
    if (controllerId != null && controllerId.isNotEmpty) {
      for (final participant in session.participants) {
        if (participant.id == controllerId) {
          currentController = participant;
          break;
        }
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Room ${session.sessionCode}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _copyCode(session.sessionCode),
                child: const Text('Copy Code'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${session.participantCount} participants',
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: session.participants.map((participant) {
              final isController = participant.id == controllerId;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: isController
                      ? NivioTheme.accentColorOf(context).withValues(alpha: 0.3)
                      : participant.isHost
                      ? NivioTheme.accentColorOf(context).withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(999),
                  border: isController
                      ? Border.all(color: NivioTheme.accentColorOf(context))
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildParticipantAvatar(participant),
                    const SizedBox(width: 7),
                    Text(
                      participant.isHost
                          ? '${participant.name} (Host)'
                          : participant.name,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    if (isController) ...[
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.sports_esports,
                        size: 14,
                        color: Colors.white,
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Text(
            currentController == null
                ? 'Delegated controller: None (host controls)'
                : 'Delegated controller: ${currentController.name} (host also controls)',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (service.isHost) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: _isControllerUpdating || controllerId == null
                      ? null
                      : () => _setPlaybackController(
                          service,
                          participantId: null,
                        ),
                  child: const Text('Host Controls'),
                ),
                ...session.participants
                    .where((participant) => !participant.isHost)
                    .map(
                      (participant) => OutlinedButton(
                        onPressed:
                            _isControllerUpdating ||
                                controllerId == participant.id
                            ? null
                            : () => _setPlaybackController(
                                service,
                                participantId: participant.id,
                                participantName: participant.name,
                              ),
                        child: Text('Give ${participant.name} Control'),
                      ),
                    ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          if (playback != null)
            FilledButton(
              onPressed: () {
                _hasNavigatedToPlayer = true;
                context.push(
                  _playerRoute(
                    mediaId: playback.mediaId,
                    mediaType: playback.mediaType.isEmpty
                        ? 'movie'
                        : playback.mediaType,
                    providerIndex: playback.providerIndex,
                    season: playback.season,
                    episode: playback.episode,
                    partyCode: session.sessionCode,
                    isHost: service.isHost,
                  ),
                );
              },
              child: const Text('Go To Playback'),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Waiting for host to start playback.',
                  style: TextStyle(color: Colors.white70),
                ),
                if (service.isHost) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Choose A Title'),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _leaveOrEndParty(service),
            child: Text(service.isHost ? 'End Party' : 'Leave Party'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(watchPartyServiceProvider);
    final session = ref.watch(watchPartySessionProvider).valueOrNull;
    final content = service == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Watch Party unavailable.\nAdd SUPABASE_URL and SUPABASE_ANON_KEY to .env.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          )
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if ((_selectedMediaTitle ?? '').trim().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Selected: ${_selectedMediaTitle}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _clearSelectedTitle,
                        child: const Text('Unselect'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (session != null)
                _buildSessionCard(service, session)
              else ...[
                FilledButton.icon(
                  onPressed: _isLoading ? null : _startParty,
                  icon: const Icon(Icons.add),
                  label: const Text('Start Watch Party'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _codeController,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Join with code',
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.06),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _isLoading ? null : _joinParty,
                  child: const Text('Join Party'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tip: Open any title and tap the users icon to preselect it here.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          );

    if (widget.embedded) {
      return Container(color: Colors.transparent, child: content);
    }

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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Text(
                      'Watch Party',
                      style: TextStyle(
                        color: NivioTheme.netflixWhite,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Expanded(child: content),
            ],
          ),
        ),
      ),
    );
  }
}
