import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:nivio/screens/player/playback_startup.dart';
import 'package:nivio/widgets/opening_overlay.dart';

const _video = PlayerState(
  playing: true,
  tracks: Tracks(video: [VideoTrack('1', null, null)]),
);

void main() {
  test('startup follows opening and buffering before revealing video', () {
    final startup = PlaybackStartup();
    expect(startup.stage.message, 'Building player…');

    startup.startOpening();
    startup.update(_video);
    expect(startup.stage.message, 'Starting stream…');

    startup.openReturned();
    startup.update(const PlayerState(playing: true));
    expect(startup.stage.message, 'Starting stream…');

    startup.update(_video.copyWith(buffering: true));
    expect(startup.stage.message, 'Buffering…');
    expect(startup.waitingForPlayback, isTrue);

    // The first position may be the saved resume point. A stalled clock at
    // that timestamp should keep the loading screen visible.
    final resumed = _video.copyWith(position: const Duration(minutes: 12));
    startup.update(resumed);
    startup.update(resumed);
    expect(startup.waitingForPlayback, isTrue);

    startup.update(resumed.copyWith(buffering: true));
    startup.update(
      resumed.copyWith(
        position: const Duration(minutes: 12, milliseconds: 100),
      ),
    );
    expect(startup.waitingForPlayback, isTrue);
    startup.update(
      resumed.copyWith(
        position: const Duration(minutes: 12, milliseconds: 200),
      ),
    );
    expect(startup.stage, PlaybackStartupStage.started);

    startup.update(resumed.copyWith(buffering: true));
    startup.update(const PlayerState());
    expect(startup.stage, PlaybackStartupStage.started);
  });

  test('a fresh attempt ignores media state before its own open returns', () {
    final startup = PlaybackStartup()..startOpening();
    startup.openReturned();
    startup.update(_video.copyWith(position: const Duration(seconds: 1)));

    startup.startOpening();
    startup.update(_video.copyWith(position: const Duration(seconds: 2)));
    expect(startup.stage, PlaybackStartupStage.opening);

    startup.openReturned();
    startup.update(_video.copyWith(position: const Duration(seconds: 3)));
    expect(startup.stage, PlaybackStartupStage.buffering);
  });

  test('a paused watch party can reveal decoded video', () {
    final startup = PlaybackStartup()
      ..startOpening()
      ..openReturned();
    startup.update(_video.copyWith(playing: false));
    expect(startup.waitingForPlayback, isTrue);

    startup.update(
      _video.copyWith(
        playing: false,
        videoParams: const VideoParams(w: 1920, h: 1080),
      ),
    );
    expect(startup.stage, PlaybackStartupStage.started);
  });

  testWidgets('the loading message has room for stats in landscape', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(568, 320));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: OpeningOverlay(
            media: null,
            onClose: () {},
            message: 'Buffering…',
            details: const Text('2.0 MB/s · 6 peers · 10%'),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final message = find.text('Buffering…');
    final stats = find.text('2.0 MB/s · 6 peers · 10%');
    expect(message, findsOneWidget);
    expect(stats, findsOneWidget);
    expect(
      tester.getTopLeft(stats).dy,
      greaterThan(tester.getBottomLeft(message).dy),
    );
    expect(tester.getBottomLeft(stats).dy, lessThan(320));
    expect(tester.takeException(), isNull);
  });
}
