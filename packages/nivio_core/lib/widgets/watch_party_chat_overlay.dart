import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nivio/providers/watch_party_provider.dart';
import 'package:nivio/services/watch_party/watch_party_models.dart';
import 'package:nivio/core/theme.dart';

class WatchPartyChatOverlay extends ConsumerStatefulWidget {
  final bool areControlsVisible;
  final bool forceHide;
  final ValueChanged<bool>? onFocusChanged;

  const WatchPartyChatOverlay({
    super.key, 
    required this.areControlsVisible,
    this.forceHide = false,
    this.onFocusChanged,
  });

  @override
  ConsumerState<WatchPartyChatOverlay> createState() =>
      _WatchPartyChatOverlayState();
}

class _WatchPartyChatOverlayState extends ConsumerState<WatchPartyChatOverlay> {
  final List<WatchPartyChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  
  Timer? _hideTimer;
  bool _isTemporarilyVisible = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) setState(() {});
      widget.onFocusChanged?.call(_focusNode.hasFocus);
      if (_focusNode.hasFocus) {
        _keepVisible();
      } else {
        _startHideTimer();
      }
    });
  }

  void _keepVisible() {
    _hideTimer?.cancel();
    if (!_isTemporarilyVisible) {
      setState(() => _isTemporarilyVisible = true);
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_focusNode.hasFocus) return; // Don't hide if user is typing
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _isTemporarilyVisible) {
        setState(() => _isTemporarilyVisible = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _scrollController.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 100,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    
    final service = ref.read(watchPartyServiceProvider);
    service?.sendChatMessage(text);
    
    _textController.clear();
    _focusNode.unfocus();
    
    _keepVisible();
    _startHideTimer();
  }

  Widget _buildReactionButton(String emoji) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Material(
        color: Colors.black45,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            final service = ref.read(watchPartyServiceProvider);
            service?.sendReaction(emoji);
          },
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<WatchPartyChatMessage>>(watchPartyChatProvider,
        (previous, next) {
      if (next.hasValue && next.value != null) {
        setState(() {
          _messages.add(next.value!);
          if (_messages.length > 50) {
            _messages.removeAt(0); // Keep only last 50 messages
          }
        });
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
        
        // Show chat overlay temporarily when receiving a new message
        _keepVisible();
        _startHideTimer();
      }
    });

    final shouldShow = (widget.areControlsVisible || _isTemporarilyVisible) && !widget.forceHide;

    return PopScope(
      canPop: !_focusNode.hasFocus,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _focusNode.hasFocus) {
          _focusNode.unfocus();
        }
      },
      child: AnimatedOpacity(
        opacity: shouldShow ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: IgnorePointer(
        ignoring: !shouldShow,
        child: SizedBox(
          width: 300,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final msg = _messages[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    msg.senderName,
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    msg.text,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: Colors.white24,
                            backgroundImage: msg.senderPhotoUrl != null
                                ? NetworkImage(msg.senderPhotoUrl!)
                                : null,
                            child: msg.senderPhotoUrl == null
                                ? Text(
                                    msg.senderName.substring(0, 1).toUpperCase(),
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.white),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildReactionButton('❤️'),
                    _buildReactionButton('😂'),
                    _buildReactionButton('😮'),
                    _buildReactionButton('😢'),
                    _buildReactionButton('👏'),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _focusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        decoration: InputDecoration(
                          hintText: 'Say something...',
                          hintStyle: const TextStyle(color: Colors.white54),
                          filled: true,
                          fillColor: Colors.black45,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: NivioTheme.accentColorOf(context),
                        shape: BoxShape.circle,
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 18),
                        onPressed: _sendMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
