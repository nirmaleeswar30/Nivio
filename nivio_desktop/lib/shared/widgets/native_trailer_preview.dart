import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/services/trailer_preview_service.dart';

enum NativeTrailerPreviewTrigger { immediate, hover }

typedef NativeTrailerScrollHandler =
    void Function(NativeTrailerScrollEvent event);

class NativeTrailerScrollEvent {
  const NativeTrailerScrollEvent({
    required this.scrollDelta,
    required this.globalPosition,
  });

  final Offset scrollDelta;
  final Offset globalPosition;
}

class NativeTrailerPreviewOverlay extends StatefulWidget {
  const NativeTrailerPreviewOverlay({
    super.key,
    required this.mediaId,
    this.isLoading = false,
    this.startDelay = const Duration(milliseconds: 320),
    this.trigger = NativeTrailerPreviewTrigger.immediate,
    this.showCloseButton = false,
    this.onCloseRequested,
  });

  final String? mediaId;
  final bool isLoading;
  final Duration startDelay;
  final NativeTrailerPreviewTrigger trigger;
  final bool showCloseButton;
  final VoidCallback? onCloseRequested;

  static NativeTrailerScrollHandler? onNativeScroll;

  @override
  State<NativeTrailerPreviewOverlay> createState() =>
      _NativeTrailerPreviewOverlayState();
}

class _NativeTrailerPreviewOverlayState
    extends State<NativeTrailerPreviewOverlay> {
  final GlobalKey _previewKey = GlobalKey();
  Timer? _startTimer;
  Timer? _validationTimer;
  Timer? _playbackKickTimer;
  Timer? _rectUpdateTimer;
  String? _youtubeVideoId;
  bool _disposed = false;
  bool _hovering = false;
  int _loadGeneration = 0;
  int? _linuxPreviewToken;

  bool get _shouldPreview =>
      !widget.isLoading &&
      (widget.trigger == NativeTrailerPreviewTrigger.immediate || _hovering);

  @override
  void initState() {
    super.initState();
    if (widget.trigger == NativeTrailerPreviewTrigger.immediate) {
      _scheduleTrailerStart();
    }
  }

  @override
  void didUpdateWidget(covariant NativeTrailerPreviewOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mediaId == widget.mediaId &&
        oldWidget.isLoading == widget.isLoading &&
        oldWidget.startDelay == widget.startDelay &&
        oldWidget.trigger == widget.trigger &&
        oldWidget.showCloseButton == widget.showCloseButton) {
      return;
    }
    if (_shouldPreview) {
      _scheduleTrailerStart();
    } else {
      _stopPreview();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _startTimer?.cancel();
    _validationTimer?.cancel();
    _playbackKickTimer?.cancel();
    _rectUpdateTimer?.cancel();
    _stopController();
    _linuxPreviewToken = null;
    super.dispose();
  }

  void _handleEnter() {
    if (widget.trigger != NativeTrailerPreviewTrigger.hover) return;
    _hovering = true;
    _scheduleTrailerStart();
  }

  void _handleExit() {
    if (widget.trigger != NativeTrailerPreviewTrigger.hover) return;
    _hovering = false;
    _stopPreview();
  }

  void _stopPreview() {
    _startTimer?.cancel();
    _validationTimer?.cancel();
    _playbackKickTimer?.cancel();
    _rectUpdateTimer?.cancel();
    _loadGeneration++;
    if (mounted && !_disposed && _youtubeVideoId != null) {
      setState(() => _youtubeVideoId = null);
    } else {
      _youtubeVideoId = null;
    }
    _stopController();
  }

  void _scheduleTrailerStart() {
    _startTimer?.cancel();
    _validationTimer?.cancel();
    _playbackKickTimer?.cancel();
    _rectUpdateTimer?.cancel();
    _stopController();
    _loadGeneration++;
    _youtubeVideoId = null;
    if (!_shouldPreview) return;
    _startTimer = Timer(widget.startDelay, () {
      unawaited(_loadTrailer());
    });
  }

  Future<void> _loadTrailer() async {
    final mediaId = widget.mediaId?.trim();
    if (mediaId == null || mediaId.isEmpty || !_shouldPreview) return;
    final generation = _loadGeneration;

    final key = await TrailerPreviewService.instance.resolve(mediaId);
    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        mediaId != widget.mediaId?.trim() ||
        key == null ||
        key.isEmpty ||
        !_shouldPreview) {
      return;
    }

    final token = _linuxPreviewToken ??= _SharedLinuxTrailerPreview.instance
        .claim();
    _SharedLinuxTrailerPreview.instance.registerCloseHandler(
      token,
      _handleCloseRequested,
    );
    final prepared = await _SharedLinuxTrailerPreview.instance.prepare(
      token: token,
    );
    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        mediaId != widget.mediaId?.trim() ||
        !prepared ||
        !_shouldPreview) {
      return;
    }

    setState(() {
      _youtubeVideoId = key;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        mediaId != widget.mediaId?.trim() ||
        !_shouldPreview) {
      return;
    }

    final loaded = await _showNativePreview(videoId: key, token: token);
    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        mediaId != widget.mediaId?.trim() ||
        !loaded ||
        !_shouldPreview) {
      return;
    }
    _scheduleTrailerValidation(generation);
    _startRectUpdates(generation);
  }

  Future<bool> _showNativePreview({
    required String videoId,
    required int token,
  }) async {
    final rect = _currentPreviewRect();
    if (rect == null) return false;
    return _SharedLinuxTrailerPreview.instance.show(
      videoId,
      token: token,
      rect: rect,
      muted: true,
      visible: false,
      showCloseButton: widget.showCloseButton,
    );
  }

  Rect? _currentPreviewRect() {
    final previewContext = _previewKey.currentContext;
    if (previewContext == null || !previewContext.mounted) {
      return null;
    }
    final box = previewContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) {
      return null;
    }
    final size = box.size;
    if (size.width <= 1 || size.height <= 1) {
      return null;
    }
    final topLeft = box.localToGlobal(Offset.zero);
    final bottomRight = box.localToGlobal(Offset(size.width, size.height));
    final rect = Rect.fromPoints(topLeft, bottomRight);
    if (rect.width <= 1 || rect.height <= 1) {
      return null;
    }
    return rect;
  }

  void _scheduleRectUpdate() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted || _youtubeVideoId == null || !_shouldPreview) {
        return;
      }
      _updateNativeRect();
    });
  }

  void _startRectUpdates(int generation) {
    _rectUpdateTimer?.cancel();
    var ticks = 0;
    _rectUpdateTimer = Timer.periodic(const Duration(milliseconds: 16), (
      timer,
    ) {
      ticks++;
      if (_disposed ||
          !mounted ||
          generation != _loadGeneration ||
          _youtubeVideoId == null ||
          !_shouldPreview ||
          ticks > 40) {
        timer.cancel();
        if (identical(_rectUpdateTimer, timer)) {
          _rectUpdateTimer = null;
        }
        return;
      }
      _updateNativeRect();
    });
  }

  void _updateNativeRect() {
    final token = _linuxPreviewToken;
    final rect = _currentPreviewRect();
    if (token == null || rect == null) return;
    unawaited(
      _SharedLinuxTrailerPreview.instance.updateRect(
        token: token,
        rect: rect,
        showCloseButton: widget.showCloseButton,
      ),
    );
  }

  void _scheduleTrailerValidation(int generation, [int attempt = 0]) {
    _validationTimer?.cancel();
    _validationTimer = Timer(const Duration(milliseconds: 650), () {
      unawaited(_validateTrailer(generation, attempt));
    });
  }

  Future<void> _validateTrailer(int generation, int attempt) async {
    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        !_shouldPreview) {
      return;
    }

    final status = await _SharedLinuxTrailerPreview.instance.status(
      token: _linuxPreviewToken,
    );
    if (status == null) {
      if (attempt >= 20) return;
      _scheduleTrailerValidation(generation, attempt + 1);
      return;
    }

    if (_disposed ||
        !mounted ||
        generation != _loadGeneration ||
        !_shouldPreview) {
      return;
    }

    final parsed = _decodeTrailerStatus(status);
    if (parsed != null) {
      final error = parsed['error']?.toString() ?? '';
      if (error.isNotEmpty) {
        _failTrailer(generation);
        return;
      }
      final playing = parsed['playing'] == true || parsed['playing'] == 'true';
      if (playing) {
        if (!mounted || generation != _loadGeneration || !_shouldPreview) {
          return;
        }
        _playbackKickTimer?.cancel();
        unawaited(
          _SharedLinuxTrailerPreview.instance.setVisible(
            token: _linuxPreviewToken,
            visible: true,
          ),
        );
        return;
      }
    }

    final normalized = status.toString().replaceAll(r'\"', '"').toLowerCase();
    final hasError =
        normalized.contains('error') && !normalized.contains('"error":""');
    if (hasError ||
        normalized.contains('153') ||
        normalized.contains('video player configuration')) {
      _failTrailer(generation);
      return;
    }

    if (normalized.contains('"playing":true')) {
      if (!mounted || generation != _loadGeneration || !_shouldPreview) return;
      _playbackKickTimer?.cancel();
      unawaited(
        _SharedLinuxTrailerPreview.instance.setVisible(
          token: _linuxPreviewToken,
          visible: true,
        ),
      );
      return;
    }

    if (attempt >= 20) return;
    _scheduleTrailerValidation(generation, attempt + 1);
  }

  Map<String, dynamic>? _decodeTrailerStatus(Object? status) {
    Object? value = status;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (value is Map) {
        return value.map((key, value) => MapEntry(key.toString(), value));
      }
      if (value is! String) return null;
      final text = value.trim();
      if (text.isEmpty) return null;
      try {
        value = jsonDecode(text);
      } catch (_) {
        return null;
      }
    }
    return value is Map
        ? value.map((key, value) => MapEntry(key.toString(), value))
        : null;
  }

  void _failTrailer(int generation) {
    if (generation != _loadGeneration) return;
    _playbackKickTimer?.cancel();
    if (mounted && !_disposed) {
      setState(() {
        _youtubeVideoId = null;
      });
    } else {
      _youtubeVideoId = null;
    }
    _stopController();
  }

  void _stopController() {
    _validationTimer?.cancel();
    _playbackKickTimer?.cancel();
    _rectUpdateTimer?.cancel();
    final token = _linuxPreviewToken;
    if (token != null) {
      _SharedLinuxTrailerPreview.instance.unregisterCloseHandler(token);
    }
    unawaited(_SharedLinuxTrailerPreview.instance.stop(token: token));
    _youtubeVideoId = null;
  }

  void _handleCloseRequested() {
    if (_disposed || !mounted) return;
    widget.onCloseRequested?.call();
    _stopPreview();
  }

  @override
  Widget build(BuildContext context) {
    final layer = Positioned.fill(
      child: IgnorePointer(
        child: SizedBox.expand(
          key: _previewKey,
          child: const ColoredBox(color: Colors.transparent),
        ),
      ),
    );

    if (widget.trigger != NativeTrailerPreviewTrigger.hover) {
      if (_youtubeVideoId != null) _scheduleRectUpdate();
      return layer;
    }

    if (_youtubeVideoId != null) _scheduleRectUpdate();
    return Positioned.fill(
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => _handleEnter(),
        onExit: (_) => _handleExit(),
        child: Stack(fit: StackFit.expand, children: [layer]),
      ),
    );
  }
}

final class _SharedLinuxTrailerPreview {
  _SharedLinuxTrailerPreview._() {
    _channel.setMethodCallHandler(_handleNativeMethodCall);
  }

  static final _SharedLinuxTrailerPreview instance =
      _SharedLinuxTrailerPreview._();
  static const MethodChannel _channel = MethodChannel(
    'nivio/native_trailer_preview',
  );

  int _activeToken = 0;
  bool _disabled = false;
  String? _loadedVideoId;
  final Map<int, VoidCallback> _closeHandlers = <int, VoidCallback>{};

  Future<Object?> _handleNativeMethodCall(MethodCall call) async {
    final args = call.arguments;
    if (args is! Map) return null;
    if (call.method == 'nativeClose') {
      final token = _readInt(args, 'token');
      _closeHandlers[token]?.call();
      return null;
    }
    if (call.method != 'nativeScroll') return null;
    NativeTrailerPreviewOverlay.onNativeScroll?.call(
      NativeTrailerScrollEvent(
        scrollDelta: Offset(_readDouble(args, 'dx'), _readDouble(args, 'dy')),
        globalPosition: Offset(_readDouble(args, 'x'), _readDouble(args, 'y')),
      ),
    );
    return null;
  }

  double _readDouble(Map<dynamic, dynamic> args, String key) {
    final value = args[key];
    if (value is num) return value.toDouble();
    return 0;
  }

  int _readInt(Map<dynamic, dynamic> args, String key) {
    final value = args[key];
    if (value is num) return value.toInt();
    return 0;
  }

  int claim() {
    _activeToken++;
    return _activeToken;
  }

  void registerCloseHandler(int token, VoidCallback handler) {
    _closeHandlers[token] = handler;
  }

  void unregisterCloseHandler(int token) {
    _closeHandlers.remove(token);
  }

  Future<bool> prepare({required int token}) async {
    if (!_isSupported || _disabled || token != _activeToken) return false;
    try {
      final prepared = await _channel.invokeMethod<bool>('prepare', {
        'token': token,
      });
      return prepared == true && token == _activeToken;
    } on MissingPluginException {
      _disabled = true;
      return false;
    } on PlatformException {
      _disabled = true;
      return false;
    }
  }

  Future<bool> show(
    String videoId, {
    required int token,
    required Rect rect,
    required bool muted,
    required bool visible,
    required bool showCloseButton,
  }) async {
    if (!_isSupported || _disabled || token != _activeToken) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('show', {
        'token': token,
        'videoId': videoId,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
        'muted': muted,
        'visible': visible,
        'showCloseButton': showCloseButton,
      });
      if (shown == true) {
        _loadedVideoId = videoId;
      }
      return shown == true && token == _activeToken;
    } on MissingPluginException {
      _disabled = true;
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> updateRect({
    required int token,
    required Rect rect,
    required bool showCloseButton,
  }) async {
    if (!_isSupported || _disabled || token != _activeToken) return;
    try {
      await _channel.invokeMethod<void>('updateRect', {
        'token': token,
        'x': rect.left,
        'y': rect.top,
        'width': rect.width,
        'height': rect.height,
        'showCloseButton': showCloseButton,
      });
    } on MissingPluginException {
      _disabled = true;
    } on PlatformException {
      // Native preview updates are best-effort during hover movement.
    }
  }

  Future<void> setVisible({required int? token, required bool visible}) async {
    if (!_isSupported || _disabled || token == null || token != _activeToken) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('setVisible', {
        'token': token,
        'visible': visible,
      });
    } on MissingPluginException {
      _disabled = true;
    } on PlatformException {
      // Native visibility is best-effort; disposal will still hide the view.
    }
  }

  Future<Object?> status({required int? token}) async {
    if (!_isSupported || _disabled || token == null || token != _activeToken) {
      return null;
    }
    if (_loadedVideoId == null) return null;
    try {
      return _channel.invokeMethod<Object?>('status', {'token': token});
    } on MissingPluginException {
      _disabled = true;
      return null;
    } on PlatformException {
      return null;
    }
  }

  Future<void> stop({required int? token}) async {
    if (!_isSupported || _disabled || token == null || token != _activeToken) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('hide', {'token': token});
      _loadedVideoId = null;
    } on MissingPluginException {
      _disabled = true;
    } on PlatformException {
      // Stop is best-effort because the native view may already be gone.
    }
  }

  bool get _isSupported =>
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.windows;
}
