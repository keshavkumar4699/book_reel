// Screenshots of the app for the website (website/), rendered from the real
// widgets with sample reading. Not part of the normal test run: it renders
// only when CLORO_SCREENSHOTS names an output folder. From app/:
//
//   CLORO_SCREENSHOTS=/tmp/cloro-shots flutter test test/marketing/screenshots_test.dart
//
// then, from website/: `npm run screens -- /tmp/cloro-shots` turns the PNGs
// into the site's images and the hero's moving scene (website/README.md).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:book_reel/app.dart';
import 'package:book_reel/core/habit/habit_engine.dart';
import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/segmentation/rule_segmenter.dart';
import 'package:book_reel/data/habit.dart';
import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/library.dart';
import 'package:book_reel/data/notebook.dart';
import 'package:book_reel/data/sessions.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/reader/cards/text_card.dart';
import 'package:book_reel/features/reader/reader_screen.dart';
import 'package:book_reel/ui/backdrops.dart';
import 'package:book_reel/ui/scenes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../silent_music.dart';

final _out = Platform.environment['CLORO_SCREENSHOTS'];

/// A common Android phone: 393 × 852 dp, drawn at 3×, with room for the
/// status bar (the website draws its own) and the gesture bar.
const _logical = Size(393, 852);
const _dpr = 3.0;
const _statusBar = 28.0;
const _gestureBar = 16.0;

/// The first scene (by index into the backdrop list) a book opens on.
class _Pick implements math.Random {
  _Pick(this.i);
  final int i;
  @override
  int nextInt(int max) => i % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

void main() {
  final skip = _out == null ? 'Set CLORO_SCREENSHOTS to an output folder to render the website screenshots.' : null;

  setUpAll(() async {
    if (_out != null) Directory(_out!).createSync(recursive: true);
  });

  /// Every font family in pubspec.yaml, the Material icons from the Flutter
  /// SDK and, where the system has it, colour emoji.
  Future<void> loadFonts() async {
    final families = <String, List<String>>{};
    String? family;
    var inFonts = false;
    for (final line in File('pubspec.yaml').readAsLinesSync()) {
      if (line.startsWith('  fonts:')) {
        inFonts = true;
        continue;
      }
      if (!inFonts) continue;
      if (line.isNotEmpty && !line.startsWith(' ')) break;
      final f = RegExp(r'^\s*- family:\s*(\S+)').firstMatch(line);
      if (f != null) {
        family = f.group(1);
        families[family!] = [];
        continue;
      }
      final a = RegExp(r'^\s*- asset:\s*(\S+)').firstMatch(line);
      if (a != null && family != null) families[family]!.add(a.group(1)!);
    }
    Future<void> load(String name, Iterable<String> paths) async {
      final loader = FontLoader(name);
      for (final p in paths) {
        loader.addFont(Future.value(ByteData.sublistView(File(p).readAsBytesSync())));
      }
      await loader.load();
    }

    for (final e in families.entries) {
      await load(e.key, e.value);
    }
    // flutter_tester lives in <flutter>/bin/cache/artifacts/engine/<platform>/.
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent.path;
    await load('MaterialIcons', ['$artifacts/material_fonts/MaterialIcons-Regular.otf']);
  }

  /// Sample reading: a few weeks of it, books, notes and sessions.
  Future<(ProviderContainer, JsonStore, String)> seed(WidgetTester tester, {int backdrop = 0}) async {
    quietReader();
    backdropRandom = _Pick(backdrop);
    tester.view.physicalSize = _logical * _dpr;
    tester.view.devicePixelRatio = _dpr;
    tester.view.padding = const FakeViewPadding(top: _statusBar * _dpr, bottom: _gestureBar * _dpr);
    tester.view.viewPadding = const FakeViewPadding(top: _statusBar * _dpr, bottom: _gestureBar * _dpr);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    final dir = Directory.systemTemp.createTempSync('cloro_shots');
    addTearDown(() => dir.deleteSync(recursive: true));
    late ProviderContainer c;
    late JsonStore store;
    late String bookId;
    await tester.runAsync(() async {
      await loadFonts();
      store = await JsonStore.open(dir);
      final now = DateTime.now();
      DateTime ago(int d, [int hour = 21]) => DateTime(now.year, now.month, now.day - d, hour, 10);
      // Most days of the last six weeks, today's goal met: 12 days in a row.
      final minutes = [19.0, 31, 18, 27, 22, 35, 16, 26, 20, 29, 24, 33, 0, 0, 21, 17, 28, 12, 0, 25, 19, 30, 22, 0, 26, 14, 21, 0, 18, 23, 27, 0, 0, 15, 22, 20, 17, 26, 0, 21, 19, 24];
      store.saveDoc(
        'habit',
        HabitState(
          stats: {
            for (var d = 0; d < minutes.length; d++)
              if (minutes[d] > 0)
                dateKey(ago(d)): DailyStat(
                    verifiedCards: d == 0 ? 16 : (minutes[d] * 0.85).round(), minutes: minutes[d].toDouble(), words: (minutes[d] * 205).round()),
          },
          streak: StreakState(current: 12, best: 30, lastGoalDate: dateKey(ago(1))),
        ).toJson(),
      );
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
      c.read(settingsProvider.notifier).update((s) => s.copyWith(
            onboardingDone: true,
            goalSetupDone: true,
            gestureTutorialSeen: true,
            animatedBackground: false,
            cardLength: CardLength.standard,
            lastBackdrop: 'paper',
            displayName: 'Asha',
            username: 'asha.reads',
            pronouns: 'she/her',
            bio: 'Classics on the commute. One reel at a time.',
            interests: ['Classics', 'Fantasy', 'History'],
            goalUnit: GoalUnit.cards,
            dailyGoal: 20,
          ));
      bookId = (await c.read(libraryProvider.notifier).ensureStarterBook())!.id;
      // Classics beside the starter book (typographic covers, as for any book without one).
      final library = store.doc('library')!;
      BookMeta book(String id, String title, String author, double progress, int daysAgo, {bool finished = false}) => BookMeta(
            id: id,
            title: title,
            author: author,
            format: BookFormat.epub,
            addedAt: ago(daysAgo + 20),
            wordCount: 120000,
            chapterCount: 30,
            isPublicDomain: true,
            lastReadAt: ago(daysAgo),
            progress: progress,
            finishedAt: finished ? ago(daysAgo) : null,
            wordsRead: (progress * 120000).round(),
          );
      final books = [
        book('pride', 'Pride and Prejudice', 'Jane Austen', 0.62, 1),
        book('meditations', 'Meditations', 'Marcus Aurelius', 0.35, 3),
        book('holmes', 'The Adventures of Sherlock Holmes', 'Arthur Conan Doyle', 0.48, 6),
        book('odyssey', 'The Odyssey', 'Homer', 0.12, 9),
        book('frankenstein', 'Frankenstein', 'Mary Shelley', 1, 14, finished: true),
        book('walden', 'Walden', 'Henry David Thoreau', 0.04, 20),
      ];
      await store.saveDoc('library', {
        ...library,
        'books': [
          for (final b in library['books'] as List) {...(b as Map<String, dynamic>), 'lastReadAt': now.toIso8601String(), 'progress': 0.18},
          for (final b in books) b.toJson(),
        ],
      });
      c.invalidate(libraryProvider);
      // Sessions for the Journal: the newest last.
      final log = c.read(sessionLogProvider.notifier);
      for (final (d, id, title, author, mins, progress, quote) in [
        (6, 'holmes', 'The Adventures of Sherlock Holmes', 'Arthur Conan Doyle', 18, 0.46, 'You see, but you do not observe.'),
        (3, 'meditations', 'Meditations', 'Marcus Aurelius', 14, 0.35, 'The happiness of your life depends upon the quality of your thoughts.'),
        (1, 'pride', 'Pride and Prejudice', 'Jane Austen', 26, 0.62, 'I declare after all there is no enjoyment like reading!'),
      ]) {
        log.clock = () => ago(d);
        log.record(bookId: id, title: title, author: author, dwellMs: mins * 60000, progress: progress);
        log.quote(id, quote);
      }
      log.clock = () => DateTime(now.year, now.month, now.day, now.hour, now.minute);
      final notes = c.read(notebookProvider.notifier);
      notes.addHighlight(bookId: 'pride', bookTitle: 'Pride and Prejudice', sid: 'c3.b2.s1', text: 'I declare after all there is no enjoyment like reading!', color: 1);
      notes.addWord(
          word: 'sanguine', meaning: 'confidently optimistic and cheerful', sentence: 'He was sanguine about the journey ahead.', bookTitle: 'The Odyssey');
      notes.toggleSaved(SavedCard(
        id: 'saved1',
        bookId: 'meditations',
        bookTitle: 'Meditations',
        author: 'Marcus Aurelius',
        chapterTitle: 'Book IV',
        startSid: 'c4.b1.s0',
        text: 'Very little is needed to make a happy life; it is all within yourself, in your way of thinking.',
        createdAt: ago(2),
      ));
      notes.addReflection(
          bookTitle: 'The Adventures of Sherlock Holmes',
          chapterTitle: 'A Scandal in Bohemia',
          text: 'Noticing is a habit. Try it on the walk home tonight.',
          quote: 'You see, but you do not observe.');
      notes.addHighlight(
          bookId: bookId, bookTitle: 'Alice’s Adventures in Wonderland', sid: 'c2.b0.s0', text: '‘Curiouser and curiouser!’ cried Alice.', color: 2);
      for (final (i, title, author, chapter, text) in [
        (0, 'Alice’s Adventures in Wonderland', 'Lewis Carroll', 'Down the Rabbit-Hole', 'And what is the use of a book, thought Alice, without pictures or conversations?'),
        (1, 'Pride and Prejudice', 'Jane Austen', 'Chapter 11', 'I declare after all there is no enjoyment like reading!'),
        (2, 'Meditations', 'Marcus Aurelius', 'Book IV', 'The happiness of your life depends upon the quality of your thoughts.'),
        (3, 'Walden', 'Henry David Thoreau', 'Where I Lived', 'I went to the woods because I wished to live deliberately.'),
        (4, 'Frankenstein', 'Mary Shelley', 'Letter 1', 'Nothing is so painful to the human mind as a great and sudden change.'),
        (5, 'The Adventures of Sherlock Holmes', 'Arthur Conan Doyle', 'A Scandal in Bohemia', 'You see, but you do not observe.'),
      ]) {
        final id = i == 0 ? bookId : 'b$i';
        notes.like(id, 'c1.b$i.s0',
            quote: LikedQuote(bookId: id, sid: 'c1.b$i.s0', bookTitle: title, author: author, chapterTitle: chapter, text: text, likedAt: ago(i)));
      }
    });
    addTearDown(c.dispose);
    return (c, store, bookId);
  }

  final shotKey = GlobalKey();

  Future<void> app(WidgetTester tester, ProviderContainer c, String location) async {
    await tester.pumpWidget(RepaintBoundary(
      key: shotKey,
      child: UncontrolledProviderScope(container: c, child: const BookReelApp()),
    ));
    await tester.pump();
    c.read(routerProvider).go(location);
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Emoji the test renderer can't draw (it never falls back to the
  /// system's fonts, as a phone does): where each one is and the room it
  /// has, so the website's image step can draw it (website/tools/screens.py).
  List<Map<String, num>> emoji(RenderObject root) {
    final found = <Map<String, num>>[];
    final pattern = RegExp(r'[\u{2300}-\u{23FF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{1F000}-\u{1FAFF}]\u{FE0F}?', unicode: true);
    void visit(RenderObject o) {
      if (o is RenderParagraph && o.attached && o.hasSize) {
        final text = o.text.toPlainText();
        for (final m in pattern.allMatches(text)) {
          final boxes = o.getBoxesForSelection(TextSelection(baseOffset: m.start, extentOffset: m.end));
          if (boxes.isEmpty) continue;
          final r = boxes.first.toRect();
          // Up to the next word: the room a phone's wider emoji fills.
          var next = m.end;
          while (next < text.length && text[next] == ' ') {
            next++;
          }
          final after = next < text.length ? o.getBoxesForSelection(TextSelection(baseOffset: next, extentOffset: next + 1)) : const <TextBox>[];
          final room = after.isEmpty ? r.width * 2 : after.first.left - r.left;
          final at = o.localToGlobal(r.topLeft);
          found.add({'codepoint': m.group(0)!.runes.first, 'x': at.dx * _dpr, 'y': at.dy * _dpr, 'w': r.width * _dpr, 'h': r.height * _dpr, 'room': room * _dpr});
        }
      }
      o.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pump(const Duration(milliseconds: 600));
    await tester.runAsync(() async {
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _dpr);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
      image.dispose();
      final marks = File('$_out/$name.emoji.json');
      final found = emoji(boundary);
      found.isEmpty ? (marks.existsSync() ? marks.deleteSync() : null) : marks.writeAsStringSync(jsonEncode(found));
    });
  }

  Future<void> reader(WidgetTester tester, ProviderContainer c, String bookId) async {
    await app(tester, c, '/read/$bookId');
    for (var i = 0; i < 25 && find.byType(PageView).evaluate().isEmpty; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 7)); // the controls shown on opening hide
  }

  Future<void> nextReel(WidgetTester tester) async {
    await tester.fling(find.byType(PageView), const Offset(0, -500), 1500);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> showControls(WidgetTester tester, ProviderContainer c) async {
    for (var i = 0; i < 4 && !c.read(readerChromeProvider); i++) {
      await tester.tapAt(Offset(_logical.width - 30, 60.0 + i * 30));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
    }
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Where [word] is on screen in the reel's text.
  Offset? wordAt(WidgetTester tester, String word) {
    for (final e in find.descendant(of: find.byType(ReelText), matching: find.byType(RichText)).evaluate()) {
      final rp = e.renderObject! as RenderParagraph;
      final text = rp.text.toPlainText();
      final i = text.indexOf(word);
      if (i < 0) continue;
      final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + word.length));
      if (boxes.isEmpty) continue;
      return rp.localToGlobal(boxes.first.toRect().center);
    }
    return null;
  }

  group('website screenshots', skip: skip, () {
    testWidgets('the reader on each study scene', (tester) async {
      for (final (i, name) in [(0, 'reader-night'), (1, 'reader-cafe'), (2, 'reader-sun')]) {
        final (c, _, bookId) = await seed(tester, backdrop: i);
        await reader(tester, c, bookId);
        if (i == 0) await shot(tester, 'reader-chapter');
        await nextReel(tester);
        if (i == 1) await nextReel(tester);
        if (i == 2) {
          await nextReel(tester);
          await nextReel(tester);
        }
        await shot(tester, name);
        if (i == 0) {
          await showControls(tester, c);
          await shot(tester, 'reader-controls');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 8));
      }
    });

    testWidgets('a word’s meaning, a highlight and the share sheet', (tester) async {
      final (c, _, bookId) = await seed(tester, backdrop: 0);
      await reader(tester, c, bookId);
      await nextReel(tester);
      final peeped = wordAt(tester, 'peeped') ?? wordAt(tester, 'sister')!;
      await tester.tapAt(peeped);
      await tester.pump(const Duration(milliseconds: 400));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await shot(tester, 'reader-meaning');
      await tester.tapAt(const Offset(30, 120));
      await tester.pump(const Duration(seconds: 1));

      await tester.longPressAt(wordAt(tester, 'tired')!);
      await tester.pump(const Duration(milliseconds: 600));
      final end = find.bySemanticsLabel('End of highlight');
      if (end.evaluate().isNotEmpty) {
        final to = wordAt(tester, 'bank')!;
        final gesture = await tester.startGesture(tester.getCenter(end));
        for (var k = 1; k <= 10; k++) {
          await gesture.moveTo(Offset.lerp(tester.getCenter(end), to + const Offset(8, 0), k / 10)!);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await gesture.up();
      }
      await tester.pump(const Duration(milliseconds: 800));
      await shot(tester, 'reader-highlight');
      if (find.bySemanticsLabel('Done').evaluate().isNotEmpty) await tester.tap(find.bySemanticsLabel('Done'));
      await tester.pump(const Duration(seconds: 1));

      await tester.drag(find.byType(PostCard), const Offset(330, 0));
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 300));
      }
      await shot(tester, 'share');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('the tabs', (tester) async {
      for (final (location, name) in [('/library', 'library'), ('/notebook', 'notebook'), ('/journal', 'journal'), ('/profile', 'profile')]) {
        final (c, _, _) = await seed(tester);
        await app(tester, c, location);
        await shot(tester, name);
        if (name == 'profile') {
          await tester.scrollUntilVisible(find.text('Liked quotes'), 400, scrollable: find.byType(Scrollable).first);
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -520));
          await tester.pump(const Duration(seconds: 1));
          await shot(tester, 'profile-quotes');
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 8));
      }
    });

    testWidgets('scenes without text, and frames of the night desk moving', (tester) async {
      Future<void> paint(String name, void Function(Canvas) draw, double scale) async {
        final size = _logical * scale;
        final rec = ui.PictureRecorder();
        final canvas = Canvas(rec)..scale(scale);
        draw(canvas);
        await tester.runAsync(() async {
          final image = await rec.endRecording().toImage(size.width.round(), size.height.round());
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
          image.dispose();
        });
      }

      for (final vibe in [Vibe.studyNight, Vibe.studyCafe, Vibe.studySun, Vibe.rain, Vibe.meadow, Vibe.night]) {
        await paint('scene-${vibe.name}', (c) => ScenePainter(vibe, () => 12.0).paint(c, _logical), _dpr);
      }
      // Seven seconds at 24 frames a second: six to loop, and one more to
      // cross-fade the end into the start (website/tools/screens.mjs).
      final frames = Directory('$_out/frames-studyNight')..createSync(recursive: true);
      const fps = 24, seconds = 7;
      for (var f = 0; f < fps * seconds; f++) {
        final t = 4.0 + f / fps;
        await paint('${frames.path.split('/').last}/${f.toString().padLeft(4, '0')}', (c) => ScenePainter(Vibe.studyNight, () => t).paint(c, _logical), 1.5);
      }
    });
  });
}
