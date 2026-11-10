import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/cards/text_card.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/features/share/share_sheet.dart';
import 'package:book_reel/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reader opens the starter book and swipes from the chapter card to text', (tester) async {
    final dir = Directory.systemTemp.createTempSync('bookreel_widget');
    late ProviderContainer container;
    late String bookId;
    await tester.runAsync(() async {
      final store = await JsonStore.open(dir);
      container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(onboardingDone: true, goalSetupDone: true, animatedBackground: false, cardLength: CardLength.standard));
      bookId = (await container.read(libraryProvider.notifier).ensureStarterBook())!.id;
    });

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildAppTheme(brightness: Brightness.light), home: ReaderScreen(bookId: bookId)),
    ));
    // Book content and segments load in isolates: let real async work finish.
    for (var i = 0; i < 20 && find.text('Swipe up to begin').evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    expect(find.text('CHAPTER 1'), findsOneWidget);
    expect(find.text('Down the Rabbit-Hole'), findsOneWidget);
    expect(find.text('Swipe up to begin'), findsOneWidget);

    // First run shows the gesture guide once.
    expect(find.text('Read like you scroll'), findsOneWidget);
    await tester.tap(find.text('Got it'));
    await tester.pump();
    expect(find.text('Read like you scroll'), findsNothing);
    expect(container.read(settingsProvider).gestureTutorialSeen, isTrue);

    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    await tester.pumpAndSettle(const Duration(milliseconds: 100), EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
    expect(find.textContaining('Alice was beginning to get very tired', findRichText: true), findsOneWidget);
    expect(find.byTooltip('Save'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);

    // Double-tap anywhere on the post likes it.
    final post = find.byType(PostCard);
    await tester.tap(post);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(post);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    final card = tester.widget<PostCard>(post);
    expect(container.read(notebookProvider).liked, contains('$bookId|${card.card.startSid}'));

    // Swipe left saves.
    await tester.drag(post, const Offset(-200, 0));
    await tester.pump();
    expect(find.text('Saved to your Notebook 🔖'), findsOneWidget);
    expect(container.read(notebookProvider).isSaved(bookId, card.card.startSid), isTrue);
    await tester.pump(const Duration(seconds: 3)); // let the snackbar timer finish

    await tester.runAsync(() async => dir.deleteSync(recursive: true));
  });

  testWidgets('share card art limits copyrighted quotes and renders progress', (tester) async {
    final sentences = List.generate(20, (i) => 'This is sentence number $i of the card.');
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: ShareCardArt(
          content: QuoteShare(sentences: sentences, bookTitle: 'Book', author: 'Author', publicDomain: false),
          template: ShareTemplate.paper,
          aspect: ShareAspect.story,
        ),
      ),
    ));
    expect(find.textContaining('sentence number 0'), findsOneWidget);
    expect(find.textContaining('sentence number 19'), findsNothing);
    expect(find.text('— Author'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Center(
        child: ShareCardArt(
          content: ProgressShare(headline: '7-day streak', lines: ['70 cards']),
          template: ShareTemplate.ember,
          aspect: ShareAspect.square,
        ),
      ),
    ));
    expect(find.text('7-day streak'), findsOneWidget);
  });
}
