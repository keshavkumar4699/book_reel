import 'dart:io';

import 'package:book_reel/core/models/book.dart';
import 'package:book_reel/core/parsing/epub_parser.dart';
import 'package:book_reel/core/text/voice_classifier.dart';
import 'package:book_reel/ui/typography.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BookVoice voice({String title = 'Untitled', List<String> subjects = const [], String sample = ''}) =>
      classifyVoice(title: title, subjects: subjects, sample: sample).voice;

  test('publisher subject tags decide the voice', () {
    expect(voice(subjects: ['Detective and mystery stories']), BookVoice.suspense);
    expect(voice(subjects: ['Science fiction', 'Space colonies']), BookVoice.scifi);
    expect(voice(subjects: ['Fantasy fiction']), BookVoice.fantasy);
    expect(voice(subjects: ['Love stories', 'England -- Fiction']), BookVoice.romance);
    expect(voice(subjects: ['Self-help techniques', 'Success']), BookVoice.modern);
    // A children's fantasy reads as a children's book first.
    expect(voice(subjects: ['Fantasy fiction', 'Juvenile fiction']), BookVoice.playful);
    // Generic tags alone stay with the literary default.
    expect(voice(subjects: ['Fiction']), BookVoice.classic);
  });

  test('titles are a hint when there are no tags', () {
    expect(voice(title: 'The Dragon and the Sword of Kings'), BookVoice.fantasy);
    expect(voice(title: 'Murder at the Silent Manor'), BookVoice.suspense);
    expect(voice(title: 'How to Build Better Habits'), BookVoice.modern);
  });

  test('the opening pages decide when nothing else does', () {
    final scifi = List.filled(
      30,
      'The starship dropped out of hyperspace above the planet, and the android checked the reactor while the colony waited in orbit.',
    ).join(' ');
    expect(voice(sample: scifi), BookVoice.scifi);
    final crime = List.filled(
      30,
      'The inspector knelt beside the corpse. There was blood on the knife, and the detective already had a suspect and a clue.',
    ).join(' ');
    expect(voice(sample: crime), BookVoice.suspense);
    final advice = List.filled(
      30,
      'If you want to change your habits, start small. Research shows that your brain rewards results, and studies of success agree.',
    ).join(' ');
    expect(voice(sample: advice), BookVoice.modern);
    // Weak or no evidence: the calm literary default.
    expect(voice(sample: 'It was a day like any other, and nothing in particular happened to anyone.'), BookVoice.classic);
    expect(voice(), BookVoice.classic);
  });

  test('the starter book gets a sensible voice and a sample that skips front matter', () {
    final parsed = const EpubParser().parse(File('assets/books/alice.epub').readAsBytesSync());
    final book = parsed.content;
    final sample = voiceSample(book, words: 400);
    expect(countWords(sample), inInclusiveRange(400, 480));
    final guess = classifyVoice(title: book.title, author: book.author, subjects: parsed.subjects, sample: voiceSample(book));
    expect(guess.voice, anyOf(BookVoice.playful, BookVoice.classic));
    // With the tag a store edition carries, it is a children's book.
    expect(classifyVoice(title: book.title, subjects: ['Fantasy fiction', "Children's stories"], sample: voiceSample(book)).voice,
        BookVoice.playful);
  });

  test('every voice names fonts the app bundles, with their licences', () {
    // Ignore the commented-out examples in the template part of the file.
    final pubspec = File('pubspec.yaml').readAsLinesSync().where((l) => !l.trimLeft().startsWith('#')).join('\n');
    final declared = RegExp(r'- family: (\w+)').allMatches(pubspec).map((m) => m.group(1)!).toSet();
    for (final entry in voiceStyles.entries) {
      for (final family in [entry.value.body, entry.value.display]) {
        expect(declared, contains(family), reason: '${entry.key.name} uses $family');
      }
    }
    for (final m in RegExp(r'asset: (assets/fonts/[\w\-]+\.ttf)').allMatches(pubspec)) {
      expect(File(m.group(1)!).existsSync(), isTrue, reason: m.group(1));
    }
    // Every bundled family ships its OFL text and lists it as an asset.
    for (final family in declared) {
      final licence = 'assets/fonts/OFL-$family.txt';
      expect(File(licence).existsSync(), isTrue, reason: licence);
      expect(pubspec, contains('- $licence'), reason: '$licence must be bundled');
    }
    expect(voiceByName('nonsense'), BookVoice.classic);
    expect(voiceByName('scifi'), BookVoice.scifi);
  });
}
