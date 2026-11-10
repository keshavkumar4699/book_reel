import 'dart:math' as math;

/// Moods the AI assigns to cards (server/src/config.ts MOODS).
const moods = ['calm', 'reflective', 'hopeful', 'joyful', 'playful', 'romantic', 'mysterious', 'tense', 'sad', 'epic'];

/// Neighbouring moods: a near match when no track has the exact mood.
const _related = <String, List<String>>{
  'calm': ['reflective', 'hopeful'],
  'reflective': ['calm', 'sad'],
  'hopeful': ['joyful', 'calm'],
  'joyful': ['playful', 'hopeful'],
  'playful': ['joyful'],
  'romantic': ['hopeful', 'calm'],
  'mysterious': ['tense', 'reflective'],
  'tense': ['mysterious', 'epic'],
  'sad': ['reflective', 'calm'],
  'epic': ['tense', 'hopeful'],
};

class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    required this.moods,
    required this.energy,
    required this.attribution,
  });

  final String id;
  final String title;
  final String artist;
  final String url;
  final List<String> moods;
  final int energy;

  /// Credit line the license requires us to show.
  final String attribution;

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String,
        artist: j['artist'] as String,
        url: j['url'] as String,
        moods: (j['moods'] as List).cast<String>(),
        energy: (j['energy'] as num).toInt(),
        attribution: j['attribution'] as String,
      );
}

double scoreTrack(Track t, String mood, int energy) {
  final moodScore = t.moods.contains(mood)
      ? 3.0
      : (_related[mood] ?? const []).any(t.moods.contains)
          ? 1.5
          : 0.0;
  return moodScore - 0.6 * (t.energy - energy).abs();
}

/// Best track for [mood]/[energy], avoiding the last few played. Ties are
/// broken randomly so the same scene doesn't always get the same song.
Track? pickTrack(List<Track> tracks, String mood, int energy, {List<String> recent = const [], math.Random? random}) {
  if (tracks.isEmpty) return null;
  final r = random ?? math.Random();
  final scored = [
    for (final t in tracks) (t, scoreTrack(t, mood, energy) - (recent.contains(t.id) ? 2.0 : 0.0)),
  ]..sort((a, b) => b.$2.compareTo(a.$2));
  final best = scored.first.$2;
  final top = scored.where((s) => s.$2 >= best - 0.01).toList();
  return top[r.nextInt(top.length)].$1;
}

/// Decides when the soundtrack should change, so music follows the story
/// without jumping on every short card: a new mood must hold for two cards
/// in a row (or start a chapter), and switches are at least [minGap] apart.
class MoodFollower {
  MoodFollower({this.minGap = const Duration(seconds: 30)});

  final Duration minGap;
  String? current;
  String? _pending;
  int _pendingCount = 0;
  DateTime? _lastSwitch;

  /// Returns the mood to switch to, or null to keep the current music.
  String? onCard(String? mood, DateTime now, {bool chapterStart = false}) {
    if (mood == null) return null;
    if (current == null) return _switch(mood, now);
    if (mood == current) {
      _pending = null;
      _pendingCount = 0;
      return null;
    }
    if (_pending == mood) {
      _pendingCount++;
    } else {
      _pending = mood;
      _pendingCount = 1;
    }
    final settled = _pendingCount >= 2 || chapterStart;
    final gapOk = _lastSwitch == null || now.difference(_lastSwitch!) >= minGap;
    return settled && gapOk ? _switch(mood, now) : null;
  }

  String _switch(String mood, DateTime now) {
    current = mood;
    _pending = null;
    _pendingCount = 0;
    _lastSwitch = now;
    return mood;
  }
}
