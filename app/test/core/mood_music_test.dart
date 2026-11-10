import 'dart:math' as math;

import 'package:book_reel/core/music/mood_music.dart';
import 'package:flutter_test/flutter_test.dart';

Track t(String id, List<String> moods, int energy) =>
    Track(id: id, title: id, artist: 'A', url: 'https://x/$id.mp3', moods: moods, energy: energy, attribution: 'A – $id');

void main() {
  final tracks = [
    t('calm1', ['calm'], 1),
    t('calm2', ['calm', 'reflective'], 2),
    t('tense1', ['tense'], 4),
    t('epic1', ['epic'], 5),
    t('hope1', ['hopeful'], 3),
  ];

  test('prefers exact mood, then related moods, then closest energy', () {
    expect(pickTrack(tracks, 'tense', 4)!.id, 'tense1');
    expect(pickTrack(tracks, 'mysterious', 4)!.id, 'tense1'); // related to tense
    expect(pickTrack(tracks, 'calm', 2)!.id, 'calm2');
    expect(pickTrack(tracks, 'calm', 1)!.id, 'calm1');
    expect(pickTrack(const [], 'calm', 1), isNull);
  });

  test('avoids repeating recently played tracks', () {
    expect(pickTrack(tracks, 'calm', 1, recent: ['calm1'], random: math.Random(1))!.id, 'calm2');
  });

  test('music changes only when a new mood holds, at most every 30 s', () {
    final f = MoodFollower();
    final t0 = DateTime(2026, 1, 1, 10);
    expect(f.onCard('calm', t0), 'calm'); // first card starts music
    expect(f.onCard('calm', t0.add(const Duration(seconds: 10))), isNull);
    expect(f.onCard('tense', t0.add(const Duration(seconds: 40))), isNull, reason: 'one tense card is not enough');
    expect(f.onCard('tense', t0.add(const Duration(seconds: 50))), 'tense');
    expect(f.onCard('calm', t0.add(const Duration(seconds: 55))), isNull);
    expect(f.onCard('calm', t0.add(const Duration(seconds: 60))), isNull, reason: 'too soon after the last switch');
    expect(f.onCard('calm', t0.add(const Duration(seconds: 90))), 'calm');
    // A new chapter can switch on its first card (still respecting the gap).
    expect(f.onCard('epic', t0.add(const Duration(seconds: 130)), chapterStart: true), 'epic');
    expect(f.onCard(null, t0.add(const Duration(seconds: 200))), isNull, reason: 'rule cards have no mood');
  });
}
