import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_flutter/lucide_flutter.dart';

import '../../shared/models/watch_party_models.dart';
import '../../shared/theme/index.dart';
import '../../shared/widgets/widgets.dart';
import '../player/models/playback_request.dart';
import '../player/playback_request_factory.dart';
import 'services/watch_party_service_supabase.dart';
import 'services/watch_party_session_manager.dart';
import 'services/watch_party_supabase_config.dart';

class PartyPreselection {
  const PartyPreselection({
    required this.mediaId,
    required this.mediaType,
    required this.season,
    required this.title,
  });

  final int mediaId;
  final String mediaType;
  final int season;
  final String title;
}

class PartyView extends StatefulWidget {
  const PartyView({super.key, this.onPlay, this.preselection});

  final ValueChanged<PlaybackRequest>? onPlay;
  final PartyPreselection? preselection;

  @override
  State<PartyView> createState() => _PartyViewState();
}

class _PartyViewState extends State<PartyView> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final List<WatchPartyChatMessage> _messages = [];
  final List<WatchPartyReaction> _reactions = [];

  WatchPartyServiceSupabase? _service;
  WatchPartySession? _session;
  StreamSubscription<WatchPartyPlaybackState>? _playbackSub;
  StreamSubscription<WatchPartySession?>? _sessionSub;
  StreamSubscription<WatchPartyChatMessage>? _chatSub;
  StreamSubscription<WatchPartyReaction>? _reactionSub;
  StreamSubscription<String>? _errorSub;

  bool _isInitializing = true;
  bool _isCreatingParty = false;
  bool _isJoiningParty = false;
  bool _isControllerUpdating = false;
  bool _hasNavigatedToPlayer = false;
  PartyPreselection? _selection;
  String? _error;

  bool get _isPartyActionBusy => _isCreatingParty || _isJoiningParty;

  @override
  void initState() {
    super.initState();
    _selection = widget.preselection;
    unawaited(_initialize());
  }

  @override
  void didUpdateWidget(covariant PartyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.preselection;
    if (incoming == null || incoming == oldWidget.preselection) return;
    setState(() => _selection = incoming);
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _sessionSub?.cancel();
    _chatSub?.cancel();
    _reactionSub?.cancel();
    _errorSub?.cancel();
    _codeController.dispose();
    _chatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const NivioPageBackdrop(
        child: Center(child: LoadingView(message: 'Loading party...')),
      );
    }

    if (!WatchPartySupabaseConfig.isAvailable || _service == null) {
      return NivioPageBackdrop(
        child: PageContainer(
          child: Center(
            child: EmptyState(
              title: 'Watch Party unavailable',
              message:
                  'Add SUPABASE_URL and SUPABASE_ANON_KEY to .env, then restart the desktop app.',
              actionLabel: 'Retry',
              onAction: _initialize,
            ),
          ),
        ),
      );
    }

    return NivioPageBackdrop(
      child: DesktopScrollbar(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl,
            AppSpacing.lg,
            AppSpacing.xxl,
            AppSpacing.massive,
          ),
          child: PageContainer(
            maxWidth: 1040,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Text(
                    'Watch Party',
                    style: AppTypography.pageTitle.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                if (_error != null) ...[
                  _ErrorBanner(message: _error!, onDismiss: _clearError),
                  const SizedBox(height: AppSpacing.lg),
                ],
                if (_session == null)
                  _buildLobby()
                else
                  _buildSession(_session!),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLobby() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: _LobbyPanel(
          title: 'Start Watch Party',
          message: 'Create a room or join one with a 6-character invite code.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_selection != null) ...[
                _SelectedTitleBanner(
                  selection: _selection!,
                  onClear: _clearSelectedTitle,
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              PrimaryButton(
                label: 'Start Watch Party',
                icon: const Icon(Icons.add),
                isLoading: _isCreatingParty,
                onPressed: _isPartyActionBusy ? null : _startParty,
                minimumSize: const Size(0, 50),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _codeController,
                maxLength: 6,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                ],
                style: AppTypography.body.copyWith(
                  color: AppColors.textPrimary,
                ),
                decoration: _partyInputDecoration(hintText: 'Join with code'),
                onSubmitted: (_) {
                  if (!_isPartyActionBusy) unawaited(_joinParty());
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              SecondaryButton(
                label: 'Join Party',
                isLoading: _isJoiningParty,
                onPressed: _isPartyActionBusy ? null : _joinParty,
                minimumSize: const Size(0, 44),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Open playback from a room once the host starts a title.',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSession(WatchPartySession session) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.standard;
        final info = _SessionInfoPanel(
          session: session,
          service: _service!,
          isControllerUpdating: _isControllerUpdating,
          onCopyCode: () => _copyCode(session.sessionCode),
          onLeaveOrEnd: _leaveOrEndParty,
          onSetController: _setPlaybackController,
          onOpenPlayback: _openPlayback,
        );
        final chat = _ChatPanel(
          messages: _messages,
          reactions: _reactions,
          controller: _chatController,
          onSendMessage: _sendChatMessage,
          onSendReaction: _sendReaction,
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: info),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(width: 380, child: chat),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            info,
            const SizedBox(height: AppSpacing.xl),
            chat,
          ],
        );
      },
    );
  }

  Future<void> _initialize() async {
    setState(() {
      _isInitializing = true;
      _error = null;
    });

    try {
      await WatchPartySupabaseConfig.initializeIfConfigured();
      if (!WatchPartySupabaseConfig.isAvailable) {
        return;
      }

      final service = await WatchPartySessionManager.instance.ensureService();
      if (service == null) return;

      await _sessionSub?.cancel();
      await _playbackSub?.cancel();
      await _chatSub?.cancel();
      await _reactionSub?.cancel();
      await _errorSub?.cancel();

      _service = service;
      _session = service.currentSession;
      _playbackSub = service.playbackStream.listen(_handlePlaybackSync);
      _sessionSub = service.sessionStream.listen((session) {
        if (!mounted) return;
        setState(() => _session = session);
      });
      _chatSub = service.chatStream.listen((message) {
        if (!mounted) return;
        setState(() => _messages.add(message));
      });
      _reactionSub = service.reactionStream.listen((reaction) {
        if (!mounted) return;
        setState(() {
          _reactions.add(reaction);
          if (_reactions.length > 12) _reactions.removeAt(0);
        });
      });
      _errorSub = service.errorStream.listen((message) {
        if (!mounted) return;
        setState(() => _error = message);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Failed to initialize watch party: $error');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _startParty() async {
    final service = _service;
    if (service == null) return;

    setState(() {
      _isCreatingParty = true;
      _error = null;
    });

    final code = await service.createSession();
    if (!mounted) return;
    setState(() => _isCreatingParty = false);

    if (code == null) {
      setState(() => _error = 'Failed to create watch party.');
      return;
    }

    final selection = _selection;
    if (selection == null) {
      _showMessage('Party started. Pick a title to begin playback.');
      return;
    }

    _hasNavigatedToPlayer = true;
    widget.onPlay?.call(
      PlaybackRequestFactory.fromCompositeId(
        '${selection.mediaType}:${selection.mediaId}',
        selection.title,
      ).copyWith(
        season: selection.mediaType == 'movie' ? null : selection.season,
        episode: selection.mediaType == 'movie' ? null : 1,
        watchPartyCode: code,
        watchPartyRole: 'host',
      ),
    );
  }

  void _clearSelectedTitle() {
    setState(() => _selection = null);
    _showMessage('Title unselected');
  }

  void _handlePlaybackSync(WatchPartyPlaybackState playback) {
    final service = _service;
    if (!mounted || service == null || _hasNavigatedToPlayer) return;
    if (!service.isInSession || service.sessionCode == null) return;
    if (service.isHost) return;

    _hasNavigatedToPlayer = true;
    _openPlayback(playback);
  }

  Future<void> _joinParty() async {
    final service = _service;
    if (service == null) return;

    final code = _codeController.text.trim().toUpperCase();
    if (code.length != 6) {
      setState(() => _error = 'Enter a valid 6-character code.');
      return;
    }

    setState(() {
      _isJoiningParty = true;
      _error = null;
    });

    final joined = await service.joinSession(code);
    if (!mounted) return;
    setState(() => _isJoiningParty = false);

    if (!joined) {
      setState(() => _error = 'No watch party found for this code.');
      return;
    }

    final playback = service.currentSession?.playbackState;
    if (playback != null) {
      _hasNavigatedToPlayer = true;
      _openPlayback(playback);
      return;
    }

    await service.requestStateSync(reason: 'participant_joined_waiting');
    Future.delayed(const Duration(milliseconds: 1200), () {
      final currentService = _service;
      if (!mounted ||
          currentService == null ||
          !currentService.isInSession ||
          currentService.isHost) {
        return;
      }
      unawaited(currentService.requestStateSync(reason: 'participant_retry'));
    });

    _showMessage('Joined. Waiting for host playback sync...');
  }

  Future<void> _leaveOrEndParty() async {
    final service = _service;
    if (service == null) return;

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
      _messages.clear();
      _reactions.clear();
    });
  }

  Future<void> _setPlaybackController(String? participantId) async {
    final service = _service;
    if (service == null || _isControllerUpdating) return;

    setState(() => _isControllerUpdating = true);
    await service.setPlaybackController(participantId);
    if (!mounted) return;
    setState(() => _isControllerUpdating = false);
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code.toUpperCase()));
    _showMessage('Code copied');
  }

  Future<void> _sendChatMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    await _service?.sendChatMessage(text);
    _chatController.clear();
  }

  Future<void> _sendReaction(String emoji) async {
    await _service?.sendReaction(emoji);
  }

  void _openPlayback(WatchPartyPlaybackState playback) {
    widget.onPlay?.call(
      PlaybackRequestFactory.fromParty(
        playback,
        partyCode: _session?.sessionCode ?? _service?.sessionCode,
        partyRole: _service?.isHost == true ? 'host' : 'participant',
      ),
    );
  }

  void _clearError() {
    setState(() => _error = null);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SelectedTitleBanner extends StatelessWidget {
  const _SelectedTitleBanner({required this.selection, required this.onClear});

  final PartyPreselection selection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final meta = selection.mediaType == 'movie'
        ? 'Movie'
        : '${selection.mediaType.toUpperCase()} | Season ${selection.season}';

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            const Icon(LucideIcons.circlePlay, color: AppColors.textPrimary),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selected: ${selection.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.body.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(meta, style: AppTypography.caption),
                ],
              ),
            ),
            TextButton(onPressed: onClear, child: const Text('Unselect')),
          ],
        ),
      ),
    );
  }
}

class _LobbyPanel extends StatelessWidget {
  const _LobbyPanel({
    required this.title,
    required this.message,
    required this.child,
  });

  final String title;
  final String message;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypography.sectionTitle.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            child,
          ],
        ),
      ),
    );
  }
}

InputDecoration _partyInputDecoration({required String hintText}) {
  return InputDecoration(
    hintText: hintText,
    counterText: '',
    hintStyle: AppTypography.body.copyWith(
      color: AppColors.textPrimary.withValues(alpha: 0.35),
    ),
    filled: true,
    fillColor: AppColors.textPrimary.withValues(alpha: 0.06),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.md,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
  );
}

class _SessionInfoPanel extends StatelessWidget {
  const _SessionInfoPanel({
    required this.session,
    required this.service,
    required this.isControllerUpdating,
    required this.onCopyCode,
    required this.onLeaveOrEnd,
    required this.onSetController,
    required this.onOpenPlayback,
  });

  final WatchPartySession session;
  final WatchPartyServiceSupabase service;
  final bool isControllerUpdating;
  final VoidCallback onCopyCode;
  final VoidCallback onLeaveOrEnd;
  final ValueChanged<String?> onSetController;
  final ValueChanged<WatchPartyPlaybackState> onOpenPlayback;

  @override
  Widget build(BuildContext context) {
    final playback = session.playbackState;
    final controller = session.controllerId == null
        ? null
        : session.participants
              .where((participant) => participant.id == session.controllerId)
              .firstOrNull;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Room ${session.sessionCode}',
                    style: AppTypography.sectionTitle.copyWith(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onCopyCode,
                  child: const Text('Copy Code'),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${session.participantCount} participants',
              style: AppTypography.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final participant in session.participants)
                  _ParticipantChip(
                    participant: participant,
                    isController: participant.id == session.controllerId,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              controller == null
                  ? 'Delegated controller: None (host controls)'
                  : 'Delegated controller: ${controller.name} (host also controls)',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            if (service.isHost) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  SecondaryButton(
                    label: 'Host Controls',
                    minimumSize: const Size(0, 36),
                    onPressed:
                        isControllerUpdating || session.controllerId == null
                        ? null
                        : () => onSetController(null),
                  ),
                  for (final participant in session.participants.where(
                    (p) => !p.isHost,
                  ))
                    SecondaryButton(
                      label: 'Give ${participant.name} Control',
                      minimumSize: const Size(0, 36),
                      onPressed:
                          isControllerUpdating ||
                              session.controllerId == participant.id
                          ? null
                          : () => onSetController(participant.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            _PlaybackPanel(playback: playback, onOpenPlayback: onOpenPlayback),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: SecondaryButton(
                label: service.isHost ? 'End Party' : 'Leave Party',
                onPressed: onLeaveOrEnd,
                minimumSize: const Size(0, 36),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ParticipantChip extends StatelessWidget {
  const _ParticipantChip({
    required this.participant,
    required this.isController,
  });

  final WatchPartyParticipant participant;
  final bool isController;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: isController
            ? AppColors.primary.withValues(alpha: 0.3)
            : participant.isHost
            ? AppColors.primary.withValues(alpha: 0.2)
            : AppColors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: isController ? Border.all(color: AppColors.primary) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ParticipantAvatar(participant: participant),
          const SizedBox(width: 7),
          Text(
            participant.isHost
                ? '${participant.name} (Host)'
                : participant.name,
            style: AppTypography.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (isController) ...[
            const SizedBox(width: AppSpacing.xs),
            const Icon(
              Icons.sports_esports,
              size: 14,
              color: AppColors.textPrimary,
            ),
          ],
        ],
      ),
    );
  }
}

class _ParticipantAvatar extends StatelessWidget {
  const _ParticipantAvatar({required this.participant});

  final WatchPartyParticipant participant;

  @override
  Widget build(BuildContext context) {
    const radius = 12.0;
    final photoUrl = (participant.photoUrl ?? '').trim();
    if (photoUrl.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.textPrimary.withValues(alpha: 0.12),
        backgroundImage: NetworkImage(photoUrl),
      );
    }

    return CircleAvatar(
      radius: radius,
      backgroundColor: participant.isHost
          ? AppColors.primary.withValues(alpha: 0.35)
          : AppColors.textPrimary.withValues(alpha: 0.12),
      child: Text(
        _initials(participant.name),
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _PlaybackPanel extends StatelessWidget {
  const _PlaybackPanel({required this.playback, required this.onOpenPlayback});

  final WatchPartyPlaybackState? playback;
  final ValueChanged<WatchPartyPlaybackState> onOpenPlayback;

  @override
  Widget build(BuildContext context) {
    final state = playback;
    if (state == null) {
      return Text(
        'Waiting for host to start playback.',
        style: AppTypography.body.copyWith(color: AppColors.textSecondary),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(
          color: AppColors.textPrimary.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current media ${state.mediaId}',
              style: AppTypography.title.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '${state.mediaType.isEmpty ? 'movie' : state.mediaType} • S${state.season} E${state.episode} • ${state.isPlaying ? 'Playing' : 'Paused'} • ${state.expectedPositionMs ~/ 1000}s',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Go To Playback',
              onPressed: () => onOpenPlayback(state),
              minimumSize: const Size(0, 40),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatPanel extends StatelessWidget {
  const _ChatPanel({
    required this.messages,
    required this.reactions,
    required this.controller,
    required this.onSendMessage,
    required this.onSendReaction,
  });

  final List<WatchPartyChatMessage> messages;
  final List<WatchPartyReaction> reactions;
  final TextEditingController controller;
  final VoidCallback onSendMessage;
  final ValueChanged<String> onSendReaction;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.06),
        border: Border.all(color: AppColors.textPrimary.withValues(alpha: 0.1)),
        borderRadius: BorderRadius.circular(AppRadius.extraLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Chat', style: AppTypography.title),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 260,
              child: messages.isEmpty
                  ? Center(
                      child: Text(
                        'No messages yet.',
                        style: AppTypography.body.copyWith(
                          color: AppColors.textPrimary.withValues(alpha: 0.5),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            message.senderName,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            message.text,
                            style: AppTypography.body.copyWith(
                              color: AppColors.textPrimary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              style: AppTypography.body.copyWith(color: AppColors.textPrimary),
              decoration: _partyInputDecoration(hintText: 'Send a message'),
              onSubmitted: (_) => onSendMessage(),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: PrimaryButton(
                    label: 'Send',
                    onPressed: onSendMessage,
                    minimumSize: const Size(0, 40),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final emoji in const ['👍', '😂', '🔥', '😮', '❤️'])
                  ActionChip(
                    label: Text(emoji),
                    backgroundColor: AppColors.textPrimary.withValues(
                      alpha: 0.08,
                    ),
                    side: BorderSide(
                      color: AppColors.textPrimary.withValues(alpha: 0.1),
                    ),
                    onPressed: () => onSendReaction(emoji),
                  ),
              ],
            ),
            if (reactions.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  for (final reaction in reactions.reversed.take(8))
                    Chip(
                      label: Text('${reaction.emoji} ${reaction.senderName}'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(AppRadius.medium),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Expanded(child: Text(message)),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: onDismiss,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}
