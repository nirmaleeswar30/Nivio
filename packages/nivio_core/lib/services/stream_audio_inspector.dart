import 'dart:async';

import 'package:media_kit/media_kit.dart';
import 'package:nivio/core/mpv_android_setup.dart';
import 'package:nivio/services/playback/stream_selection.dart';

/// Reads tracks with a separate, paused player. It owns no video surface
/// and does not take over the active player's audio or media session.
Future<List<String>> inspectStreamAudioTracks(
  String url,
  Map<String, String> headers,
  Future<void> cancelled,
) async {
  final player = Player(
    configuration: const PlayerConfiguration(
      vo: 'null',
      muted: true,
      bufferSize: 1024 * 1024,
      protocolWhitelist: ['tcp', 'tls', 'http', 'https', 'crypto', 'data'],
    ),
  );
  final tracks = Completer<List<String>>();
  Timer? settle;
  List<String> latest = const [];
  final subscription = player.stream.tracks.listen((value) {
    final audio = [
      for (final track in value.audio)
        if (track.id != 'auto' && track.id != 'no')
          StreamSelection.audioTrackLanguage(track.language, track.title),
    ];
    if (audio.isEmpty || tracks.isCompleted) return;
    latest = audio;
    settle?.cancel();
    settle = Timer(const Duration(milliseconds: 150), () {
      if (!tracks.isCompleted) tracks.complete(latest);
    });
  });
  var finished = false;

  Future<List<String>> read() async {
    final native = player.platform;
    if (native is! NativePlayer) return const [];
    final caBundle = mpvCaBundlePath;
    final options = {
      'ao': 'null',
      'ytdl': 'no',
      'cache-secs': '0.5',
      'demuxer-readahead-secs': '0.5',
      'network-timeout': '4',
      if (caBundle != null) 'tls-ca-file': caBundle,
      if (caBundle != null) 'tls-verify': 'yes',
    };
    for (final option in options.entries) {
      if (finished) return const [];
      await native.setProperty(option.key, option.value);
    }
    if (finished) return const [];
    await player.open(Media(url, httpHeaders: headers), play: false);
    return tracks.future;
  }

  try {
    return await Future.any([
      read(),
      cancelled.then<List<String>>((_) => const []),
    ]).timeout(const Duration(seconds: 6), onTimeout: () => latest);
  } finally {
    finished = true;
    settle?.cancel();
    if (!tracks.isCompleted) tracks.complete(const []);
    await subscription.cancel();
    await player.dispose();
  }
}
