import 'dart:convert';
import 'dart:io';

import 'package:book_reel/core/text/lexicon.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lexicon = Lexicon.fromAssets(
    zipfTsv: utf8.decode(gzip.decode(File('assets/lexicon/zipf.tsv.gz').readAsBytesSync())),
    dictionaryJson: jsonDecode(utf8.decode(gzip.decode(File('assets/lexicon/wordnet.json.gz').readAsBytesSync())))
        as Map<String, dynamic>,
  );

  test('loads bundled assets', () {
    expect(lexicon.zipf('the'), greaterThan(7));
    expect(lexicon.lookup('ephemeral')!.senses.first.definition, isNotEmpty);
  });

  test('finds base forms of inflected words', () {
    expect(lexicon.lookup('ruminated')?.lemma, 'ruminate');
    expect(lexicon.lookup('quandaries')?.lemma, 'quandary');
    expect(Lexicon.lemmaCandidates('running'), containsAll(['running', 'run']));
  });

  test('flags rare words by reading level and skips proper nouns', () {
    const s = 'Alice felt a sanguine, almost ebullient mood while Bartholomew walked to the house.';
    final beginner = lexicon.hardWords(s, ReadingLevel.beginner);
    final advanced = lexicon.hardWords(s, ReadingLevel.advanced);
    expect(beginner, containsAll(['sanguine', 'ebullient']));
    expect(beginner, isNot(contains('house')));
    expect(beginner, isNot(contains('Bartholomew')));
    expect(beginner, isNot(contains('Alice')));
    expect(advanced.length, lessThanOrEqualTo(beginner.length));
  });
}
