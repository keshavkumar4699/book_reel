import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/services/read_aloud.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the bar is most of the way along at the expected time, and never quite full', () {
    const expected = Duration(seconds: 5);
    expect(SpeechProgress.progressAt(Duration.zero, expected), 0);
    expect(SpeechProgress.progressAt(expected, expected), closeTo(0.845, 0.01));
    final late = SpeechProgress.progressAt(const Duration(minutes: 1), expected);
    expect(late, lessThan(0.95));
    expect(late, greaterThan(0.94));
    // Always moving on.
    expect(SpeechProgress.progressAt(const Duration(seconds: 8), expected),
        greaterThan(SpeechProgress.progressAt(const Duration(seconds: 6), expected)));
  });

  testWidgets('while a reel is converted to audio, a bar slides along in place of the goal line', (tester) async {
    final waiting = ValueNotifier<SpeechWait?>(null);
    addTearDown(waiting.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(Kit.appLight),
      home: Scaffold(
        body: SpeechProgress(
          waiting: waiting,
          color: Colors.blue,
          track: Colors.black12,
          ink: Colors.black,
          child: const Text('goal line'),
        ),
      ),
    ));
    expect(find.text('goal line'), findsOneWidget);
    expect(find.text('Converting text to audio…'), findsNothing);

    waiting.value = const SpeechWait(chars: 200, expected: Duration(seconds: 4));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Converting text to audio…'), findsOneWidget);
    double bar() => tester.widget<KitProgress>(find.byType(KitProgress)).value;
    final early = bar();
    await tester.pump(const Duration(seconds: 2));
    expect(bar(), greaterThan(early), reason: 'it slides along');
    expect(bar(), lessThan(0.95));
    expect(find.bySemanticsLabel('Converting text to audio'), findsOneWidget);

    // The audio starts: back to the goal line.
    waiting.value = null;
    await tester.pumpAndSettle();
    expect(find.text('Converting text to audio…'), findsNothing);
    expect(find.text('goal line'), findsOneWidget);
  });
}
