import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nivio/services/parental_guide_service.dart';
import 'package:nivio/widgets/parental_guide_overlay.dart';

const _warnings = [
  ParentalWarning('Violence', 'Severe'),
  ParentalWarning('Profanity', 'Mild'),
];
const _accent = ValueKey('parental-guide-accent');

void main() {
  test(
    'the guide selects dominant warnings and orders them by severity',
    () async {
      var requests = 0;
      final client = MockClient((request) async {
        requests++;
        expect(request.url.path, '/titles/tt1375666/parentsGuide');
        return http.Response(
          jsonEncode({
            'parentsGuide': [
              _category('SEXUAL_CONTENT', {'none': 20, 'mild': 20}),
              _category('ALCOHOL_DRUGS', {'severe': 18, 'none': 2}),
              _category('VIOLENCE', {'mild': 3, 'moderate': 20, 'none': 1}),
              _category('PROFANITY', {'mild': 20, 'none': 1}),
              _category('FRIGHTENING_INTENSE_SCENES', {'severe': 30}),
              _category('UNKNOWN', {'severe': 90}),
            ],
          }),
          200,
        );
      });
      addTearDown(client.close);
      final guide = ParentalGuideService(client);
      expect(await guide.fetch('bad ID'), isEmpty);
      final warnings = await guide.fetch('tt1375666');
      expect(warnings.map((warning) => (warning.label, warning.severity)), [
        ('Alcohol/Drugs', 'Severe'),
        ('Frightening', 'Severe'),
        ('Violence', 'Moderate'),
        ('Profanity', 'Mild'),
      ]);
      expect(await guide.fetch('tt1375666'), same(warnings));
      expect(requests, 1);
    },
  );

  testWidgets('warning rows appear in sequence and disappear in reverse', (
    tester,
  ) async {
    await tester.pumpWidget(_player(playing: false));
    expect(find.byKey(_accent), findsNothing);
    await tester.pumpWidget(_player(playing: true));
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.getSize(find.byKey(_accent)).height, closeTo(38, .001));
    expect(_opacity(tester, 'Violence · Severe'), closeTo(0, .001));
    expect(_opacity(tester, 'Profanity · Mild'), closeTo(0, .001));

    await tester.pump(const Duration(milliseconds: 280));
    expect(_opacity(tester, 'Violence · Severe'), closeTo(1, .001));
    expect(_opacity(tester, 'Profanity · Mild'), closeTo(0, .001));

    await tester.pump(const Duration(milliseconds: 280));
    expect(_opacity(tester, 'Profanity · Mild'), closeTo(1, .001));

    await tester.pump(const Duration(milliseconds: 5210));
    expect(_opacity(tester, 'Violence · Severe'), 1);
    expect(_opacity(tester, 'Profanity · Mild'), closeTo(0, .001));
    await tester.pump(const Duration(milliseconds: 1011));
    expect(find.byKey(_accent), findsNothing);

    await tester.pumpWidget(_player(playing: false));
    await tester.pumpWidget(_player(playing: true));
    expect(find.byKey(_accent), findsNothing);
    await tester.pumpWidget(_player(playing: true, episode: 2));
    expect(find.byKey(_accent), findsOneWidget);
  });

  testWidgets('the warning respects reduced motion and stays out of PiP', (
    tester,
  ) async {
    await tester.pumpWidget(_player(playing: true, canShow: false));
    expect(find.byKey(_accent), findsNothing);
    await tester.pumpWidget(_player(playing: true, animate: false));
    await tester.pump();
    expect(_opacity(tester, 'Violence · Severe'), 1);
    expect(_opacity(tester, 'Profanity · Mild'), 1);
    await tester.pumpWidget(
      _player(playing: true, canShow: false, animate: false),
    );
    await tester.pumpWidget(_player(playing: true, animate: false));
    expect(find.byKey(_accent), findsNothing);
  });
}

Map<String, Object> _category(String name, Map<String, int> votes) => {
  'category': name,
  'severityBreakdowns': [
    for (final entry in votes.entries)
      {'severityLevel': entry.key, 'voteCount': entry.value},
  ],
};

Widget _player({
  required bool playing,
  bool canShow = true,
  bool animate = true,
  int episode = 1,
}) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: ParentalGuideOverlay(
        key: ValueKey(episode),
        warnings: _warnings,
        playing: playing,
        canShow: canShow,
        animate: animate,
      ),
    ),
  ),
);

double _opacity(WidgetTester tester, String text) => tester
    .widget<Opacity>(
      find.ancestor(of: find.text(text), matching: find.byType(Opacity)).first,
    )
    .opacity;
