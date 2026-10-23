import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

/// What the OS media overlay / lock screen / headset UI shows.
@immutable
class MediaSessionMetadata {
  final String title;
  final String? subtitle;
  final String? artUrl;

  const MediaSessionMetadata({required this.title, this.subtitle, this.artUrl});

  @override
  bool operator ==(Object other) =>
      other is MediaSessionMetadata &&
      other.title == title &&
      other.subtitle == subtitle &&
      other.artUrl == artUrl;

  @override
  int get hashCode => Object.hash(title, subtitle, artUrl);
}

/// Publishes the active media_kit [Player] as the OS media session so
/// hardware media buttons (Bluetooth headphones/earbuds, keyboard media keys,
/// OS overlay / lock screen controls) control playback:
///
///  * Windows: System Media Transport Controls (runner, `com.nivio/media_session`)
///  * Android: framework MediaSession (MainActivity, same channel)
///  * Linux:   MPRIS on the session bus (what desktop media keys and bluez's
///             mpris-proxy talk to)
///
/// Media keys delivered to the focused window as key events are handled too;
/// commands arriving through two routes at once are collapsed.
class MediaSessionService {
  MediaSessionService._();
  static final MediaSessionService instance = MediaSessionService._();

  static const MethodChannel _channel = MethodChannel('com.nivio/media_session');

  Object? _owner;
  Player? _player;
  MediaSessionMetadata? _metadata;
  Duration _seekStep = const Duration(seconds: 10);
  final List<StreamSubscription<dynamic>> _subs = [];
  Timer? _positionTimer;
  bool _channelHandlerSet = false;
  bool _keyHandlerInstalled = false;
  _MprisServer? _mpris;
  Future<void>? _mprisStarting;
  int _trackId = 0;

  String? _lastCommandGroup;
  DateTime _lastCommandAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool get _usesChannel => Platform.isWindows || Platform.isAndroid;

  /// Makes [player] the session's target. [owner] is whoever drives the
  /// player (the player screen); only the current owner can [detach].
  void attach({
    required Object owner,
    required Player player,
    required MediaSessionMetadata metadata,
    Duration? seekStep,
  }) {
    _owner = owner;
    if (seekStep != null && seekStep > Duration.zero) _seekStep = seekStep;
    if (metadata != _metadata) _trackId++;
    _metadata = metadata;

    if (!identical(player, _player)) {
      _cancelPlayerListeners();
      _player = player;
      _subs
        ..add(player.stream.playing.listen((_) => _push()))
        ..add(player.stream.duration.listen((_) => _push()))
        ..add(player.stream.completed.listen((_) => _push()));
      _positionTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pushChannel());
    }

    _installKeyHandler();
    if (_usesChannel && !_channelHandlerSet) {
      _channelHandlerSet = true;
      _channel.setMethodCallHandler(_onNativeCall);
    }
    if (Platform.isLinux) {
      _mprisStarting ??= _startMpris();
    }
    _push();
  }

  /// Updates the title/artwork while [owner] still drives the session.
  void updateMetadata(Object owner, MediaSessionMetadata metadata) {
    if (!identical(owner, _owner) || metadata == _metadata) return;
    _metadata = metadata;
    _trackId++;
    _push();
  }

  /// [owner] stops driving the session but the player keeps running
  /// (handed to the mini player), so the buttons must keep working.
  void releaseOwner(Object owner) {
    if (identical(owner, _owner)) _owner = null;
  }

  /// Tears the session down if [owner] still owns it.
  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _teardown();
  }

  /// Tears the session down if it targets [player] (player being disposed).
  void detachPlayer(Player player) {
    if (!identical(player, _player)) return;
    _teardown();
  }

  void _teardown() {
    _owner = null;
    _player = null;
    _metadata = null;
    _cancelPlayerListeners();
    _removeKeyHandler();
    if (_usesChannel) {
      _channel.invokeMethod<void>('clear').catchError((Object e) {
        debugPrint('MediaSession clear failed: $e');
      });
    }
    _mpris?.setActive(false);
  }

  void _cancelPlayerListeners() {
    for (final sub in _subs) {
      sub.cancel();
    }
    _subs.clear();
    _positionTimer?.cancel();
    _positionTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Commands from the OS / keyboard
  // ---------------------------------------------------------------------------

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method != 'onCommand') return null;
    final args = call.arguments;
    if (args is! Map) return null;
    final command = args['command'];
    final positionMs = args['positionMs'];
    if (command is String) {
      _dispatch(
        command,
        position: positionMs is num ? Duration(milliseconds: positionMs.toInt()) : null,
      );
    }
    return null;
  }

  void _dispatch(String command, {Duration? position}) {
    final player = _player;
    if (player == null) return;

    // A single button press can reach us twice (e.g. Windows delivers the
    // media key to the focused window *and* to SMTC). Two play/pause toggles
    // cancel out, which looks like the button "doesn't work".
    final group = switch (command) {
      'play' || 'pause' || 'toggle' => 'playback',
      _ => command,
    };
    final now = DateTime.now();
    if (command != 'seek' &&
        group == _lastCommandGroup &&
        now.difference(_lastCommandAt) < const Duration(milliseconds: 350)) {
      return;
    }
    _lastCommandGroup = group;
    _lastCommandAt = now;

    switch (command) {
      case 'play':
        unawaited(player.play());
      case 'pause':
      case 'stop':
        unawaited(player.pause());
      case 'toggle':
        unawaited(player.playOrPause());
      case 'next':
      case 'fastForward':
        unawaited(_seekTo(player.state.position + _seekStep));
      case 'previous':
      case 'rewind':
        unawaited(_seekTo(player.state.position - _seekStep));
      case 'seek':
        if (position != null) unawaited(_seekTo(position));
    }
  }

  Future<void> _seekTo(Duration target) async {
    final player = _player;
    if (player == null) return;
    final duration = player.state.duration;
    var clamped = target < Duration.zero ? Duration.zero : target;
    if (duration > Duration.zero && clamped > duration) clamped = duration;
    await player.seek(clamped);
    _pushChannel();
    _mpris?.emitSeeked(clamped);
  }

  void _installKeyHandler() {
    if (_keyHandlerInstalled) return;
    _keyHandlerInstalled = true;
    HardwareKeyboard.instance.addHandler(_onKeyEvent);
  }

  void _removeKeyHandler() {
    if (!_keyHandlerInstalled) return;
    _keyHandlerInstalled = false;
    HardwareKeyboard.instance.removeHandler(_onKeyEvent);
  }

  bool _onKeyEvent(KeyEvent event) {
    if (_player == null || event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final String? command;
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      command = 'toggle';
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      command = 'play';
    } else if (key == LogicalKeyboardKey.mediaPause) {
      command = 'pause';
    } else if (key == LogicalKeyboardKey.mediaStop) {
      command = 'stop';
    } else if (key == LogicalKeyboardKey.mediaTrackNext) {
      command = 'next';
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      command = 'previous';
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      command = 'fastForward';
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      command = 'rewind';
    } else {
      command = null;
    }
    if (command == null) return false;
    _dispatch(command);
    return true;
  }

  // ---------------------------------------------------------------------------
  // State to the OS
  // ---------------------------------------------------------------------------

  void _push() {
    _pushChannel();
    _mpris?.setActive(_player != null);
    _mpris?.syncProperties();
  }

  void _pushChannel() {
    if (!_usesChannel) return;
    final player = _player;
    final metadata = _metadata;
    if (player == null || metadata == null) return;
    final state = player.state;
    _channel.invokeMethod<void>('update', <String, Object>{
      'title': metadata.title,
      'subtitle': metadata.subtitle ?? '',
      'artUrl': metadata.artUrl ?? '',
      'durationMs': state.duration.inMilliseconds,
      'positionMs': state.position.inMilliseconds,
      'playing': state.playing,
    }).catchError((Object e) {
      debugPrint('MediaSession update failed: $e');
    });
  }

  Future<void> _startMpris() async {
    final server = await _MprisServer.start(this);
    _mpris = server;
    // State may have changed (or the session ended) while connecting.
    server?.setActive(_player != null);
    server?.syncProperties();
  }
}

/// org.mpris.MediaPlayer2 + org.mpris.MediaPlayer2.Player on /org/mpris/MediaPlayer2.
class _MprisServer extends DBusObject {
  _MprisServer._(this._service, this._bus)
      : super(DBusObjectPath('/org/mpris/MediaPlayer2'));

  static const _rootInterface = 'org.mpris.MediaPlayer2';
  static const _playerInterface = 'org.mpris.MediaPlayer2.Player';
  static const _busName = 'org.mpris.MediaPlayer2.nivio';
  static final _noTrack = DBusObjectPath('/org/mpris/MediaPlayer2/TrackList/NoTrack');

  final MediaSessionService _service;
  final DBusClient _bus;
  String? _ownedName;
  bool _active = false;
  Map<String, DBusValue> _published = const {};

  static Future<_MprisServer?> start(MediaSessionService service) async {
    DBusClient? bus;
    try {
      bus = DBusClient.session();
      final server = _MprisServer._(service, bus);
      await bus.registerObject(server);
      return server;
    } catch (e) {
      debugPrint('MPRIS unavailable (no session bus?): $e');
      try {
        await bus?.close();
      } catch (_) {}
      return null;
    }
  }

  /// Owns the MPRIS bus name only while something is playing, so desktops
  /// don't show an empty Nivio media widget.
  void setActive(bool active) {
    if (active == _active) return;
    _active = active;
    unawaited(active ? _acquireName() : _releaseName());
  }

  Future<void> _acquireName() async {
    if (_ownedName != null) return;
    try {
      for (final name in [_busName, '$_busName.instance$pid']) {
        final reply = await _bus.requestName(name, flags: {DBusRequestNameFlag.doNotQueue});
        if (reply == DBusRequestNameReply.primaryOwner ||
            reply == DBusRequestNameReply.alreadyOwner) {
          _ownedName = name;
          break;
        }
      }
      if (!_active) await _releaseName();
    } catch (e) {
      debugPrint('MPRIS name request failed: $e');
    }
  }

  Future<void> _releaseName() async {
    final name = _ownedName;
    if (name == null) return;
    _ownedName = null;
    try {
      await _bus.releaseName(name);
    } catch (_) {}
  }

  String get _trackPath => '/com/nivio/track/t${_service._trackId}';

  DBusValue _metadataValue() {
    final metadata = _service._metadata;
    final player = _service._player;
    if (metadata == null || player == null) {
      return DBusDict.stringVariant({'mpris:trackid': _noTrack});
    }
    final duration = player.state.duration;
    return DBusDict.stringVariant({
      'mpris:trackid': DBusObjectPath(_trackPath),
      if (duration > Duration.zero) 'mpris:length': DBusInt64(duration.inMicroseconds),
      'xesam:title': DBusString(metadata.title),
      if (metadata.subtitle != null && metadata.subtitle!.isNotEmpty)
        'xesam:artist': DBusArray.string([metadata.subtitle!]),
      if (metadata.artUrl != null && metadata.artUrl!.isNotEmpty)
        'mpris:artUrl': DBusString(metadata.artUrl!),
    });
  }

  /// Player properties except Position (clients poll it; changes are
  /// announced with the Seeked signal instead).
  Map<String, DBusValue> _playerProperties() {
    final player = _service._player;
    final hasPlayer = player != null;
    final status = !hasPlayer
        ? 'Stopped'
        : (player.state.playing ? 'Playing' : 'Paused');
    final volume = ((player?.state.volume ?? 100) / 100).clamp(0.0, 2.0);
    return {
      'PlaybackStatus': DBusString(status),
      'Rate': const DBusDouble(1.0),
      'MinimumRate': const DBusDouble(1.0),
      'MaximumRate': const DBusDouble(1.0),
      'Metadata': _metadataValue(),
      'Volume': DBusDouble(volume.toDouble()),
      'CanGoNext': DBusBoolean(hasPlayer),
      'CanGoPrevious': DBusBoolean(hasPlayer),
      'CanPlay': DBusBoolean(hasPlayer),
      'CanPause': DBusBoolean(hasPlayer),
      'CanSeek': DBusBoolean(hasPlayer && player.state.duration > Duration.zero),
      'CanControl': const DBusBoolean(true),
    };
  }

  Map<String, DBusValue> _rootProperties() => {
        'CanQuit': const DBusBoolean(false),
        'CanRaise': const DBusBoolean(true),
        'HasTrackList': const DBusBoolean(false),
        'Identity': const DBusString('Nivio'),
        'DesktopEntry': const DBusString('nivio'),
        'SupportedUriSchemes': DBusArray.string(const []),
        'SupportedMimeTypes': DBusArray.string(const []),
      };

  void syncProperties() {
    final current = _playerProperties();
    final changed = <String, DBusValue>{};
    current.forEach((key, value) {
      if (_published[key] != value) changed[key] = value;
    });
    _published = current;
    if (changed.isEmpty) return;
    unawaited(emitPropertiesChanged(_playerInterface, changedProperties: changed)
        .catchError((Object _) {}));
  }

  void emitSeeked(Duration position) {
    unawaited(emitSignal(_playerInterface, 'Seeked', [DBusInt64(position.inMicroseconds)])
        .catchError((Object _) {}));
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall methodCall) async {
    if (methodCall.interface == _rootInterface) {
      switch (methodCall.name) {
        case 'Raise':
          unawaited(() async {
            try {
              await windowManager.show();
              await windowManager.focus();
            } catch (_) {}
          }());
          return DBusMethodSuccessResponse();
        case 'Quit':
          return DBusMethodErrorResponse.notSupported();
      }
      return DBusMethodErrorResponse.unknownMethod();
    }

    if (methodCall.interface != _playerInterface) {
      return DBusMethodErrorResponse.unknownInterface();
    }

    final values = methodCall.values;
    switch (methodCall.name) {
      case 'Play':
        _service._dispatch('play');
      case 'Pause':
        _service._dispatch('pause');
      case 'PlayPause':
        _service._dispatch('toggle');
      case 'Stop':
        _service._dispatch('stop');
      case 'Next':
        _service._dispatch('next');
      case 'Previous':
        _service._dispatch('previous');
      case 'Seek':
        if (values.length != 1 || values[0] is! DBusInt64) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        final player = _service._player;
        if (player != null) {
          final offset = Duration(microseconds: (values[0] as DBusInt64).value);
          _service._dispatch('seek', position: player.state.position + offset);
        }
      case 'SetPosition':
        if (values.length != 2 || values[0] is! DBusObjectPath || values[1] is! DBusInt64) {
          return DBusMethodErrorResponse.invalidArgs();
        }
        // Per spec, ignore requests for a track that is no longer current.
        if ((values[0] as DBusObjectPath).value == _trackPath) {
          _service._dispatch('seek', position: Duration(microseconds: (values[1] as DBusInt64).value));
        }
      case 'OpenUri':
        return DBusMethodErrorResponse.notSupported();
      default:
        return DBusMethodErrorResponse.unknownMethod();
    }
    return DBusMethodSuccessResponse();
  }

  @override
  Future<DBusMethodResponse> getProperty(String interface, String name) async {
    final DBusValue? value;
    if (interface == _rootInterface) {
      value = _rootProperties()[name];
    } else if (interface == _playerInterface) {
      value = name == 'Position'
          ? DBusInt64((_service._player?.state.position ?? Duration.zero).inMicroseconds)
          : _playerProperties()[name];
    } else {
      return DBusMethodErrorResponse.unknownInterface();
    }
    return value == null
        ? DBusMethodErrorResponse.unknownProperty()
        : DBusGetPropertyResponse(value);
  }

  @override
  Future<DBusMethodResponse> getAllProperties(String interface) async {
    if (interface == _rootInterface) {
      return DBusGetAllPropertiesResponse(_rootProperties());
    }
    if (interface == _playerInterface) {
      return DBusGetAllPropertiesResponse({
        ..._playerProperties(),
        'Position': DBusInt64((_service._player?.state.position ?? Duration.zero).inMicroseconds),
      });
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  Future<DBusMethodResponse> setProperty(String interface, String name, DBusValue value) async {
    if (interface == _playerInterface) {
      if (name == 'Volume' && value is DBusDouble) {
        final player = _service._player;
        if (player != null) {
          await player.setVolume((value.value * 100).clamp(0.0, 200.0));
          syncProperties();
        }
        return DBusMethodSuccessResponse();
      }
      // Rate is fixed at 1.0 (MinimumRate == MaximumRate); accept and ignore.
      if (name == 'Rate') return DBusMethodSuccessResponse();
      if (_playerProperties().containsKey(name) || name == 'Position') {
        return DBusMethodErrorResponse.propertyReadOnly();
      }
      return DBusMethodErrorResponse.unknownProperty();
    }
    if (interface == _rootInterface) {
      return _rootProperties().containsKey(name)
          ? DBusMethodErrorResponse.propertyReadOnly()
          : DBusMethodErrorResponse.unknownProperty();
    }
    return DBusMethodErrorResponse.unknownInterface();
  }

  @override
  List<DBusIntrospectInterface> introspect() {
    DBusIntrospectProperty prop(String name, String type,
            [DBusPropertyAccess access = DBusPropertyAccess.read]) =>
        DBusIntrospectProperty(name, DBusSignature(type), access: access);
    DBusIntrospectArgument inArg(String name, String type) =>
        DBusIntrospectArgument(DBusSignature(type), DBusArgumentDirection.in_, name: name);

    return [
      DBusIntrospectInterface(
        _rootInterface,
        methods: [DBusIntrospectMethod('Raise'), DBusIntrospectMethod('Quit')],
        properties: [
          prop('CanQuit', 'b'),
          prop('CanRaise', 'b'),
          prop('HasTrackList', 'b'),
          prop('Identity', 's'),
          prop('DesktopEntry', 's'),
          prop('SupportedUriSchemes', 'as'),
          prop('SupportedMimeTypes', 'as'),
        ],
      ),
      DBusIntrospectInterface(
        _playerInterface,
        methods: [
          DBusIntrospectMethod('Next'),
          DBusIntrospectMethod('Previous'),
          DBusIntrospectMethod('Pause'),
          DBusIntrospectMethod('PlayPause'),
          DBusIntrospectMethod('Stop'),
          DBusIntrospectMethod('Play'),
          DBusIntrospectMethod('Seek', args: [inArg('Offset', 'x')]),
          DBusIntrospectMethod('SetPosition', args: [inArg('TrackId', 'o'), inArg('Position', 'x')]),
          DBusIntrospectMethod('OpenUri', args: [inArg('Uri', 's')]),
        ],
        signals: [
          DBusIntrospectSignal('Seeked', args: [
            DBusIntrospectArgument(DBusSignature('x'), DBusArgumentDirection.out, name: 'Position'),
          ]),
        ],
        properties: [
          prop('PlaybackStatus', 's'),
          prop('Rate', 'd', DBusPropertyAccess.readwrite),
          prop('Metadata', 'a{sv}'),
          prop('Volume', 'd', DBusPropertyAccess.readwrite),
          prop('Position', 'x'),
          prop('MinimumRate', 'd'),
          prop('MaximumRate', 'd'),
          prop('CanGoNext', 'b'),
          prop('CanGoPrevious', 'b'),
          prop('CanPlay', 'b'),
          prop('CanPause', 'b'),
          prop('CanSeek', 'b'),
          prop('CanControl', 'b'),
        ],
      ),
    ];
  }
}
