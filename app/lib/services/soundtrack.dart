import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../core/models/reel_card.dart' show MusicCue;
import '../core/music/mood_music.dart';
import '../data/api_client.dart';
import '../data/settings.dart';
import '../data/settings_provider.dart';

/// Plays tracks with crossfades. Behind an interface so logic is testable.
abstract class AudioEngine {
  Future<void> crossfadeTo(String url, double volume);
  Future<void> setVolume(double volume);
  Future<void> stop();
}

class JustAudioEngine implements AudioEngine {
  AudioPlayer? _current;
  Timer? _fade;
  double _volume = 0.35;

  @override
  Future<void> crossfadeTo(String url, double volume) async {
    _volume = volume;
    final next = AudioPlayer();
    await next.setLoopMode(LoopMode.one);
    await next.setUrl(url);
    await next.setVolume(0);
    unawaited(next.play());
    final previous = _current;
    _current = next;
    _fade?.cancel();
    const steps = 20; // 2 s
    var i = 0;
    _fade = Timer.periodic(const Duration(milliseconds: 100), (t) {
      i++;
      final p = i / steps;
      next.setVolume(_volume * p);
      previous?.setVolume(_volume * (1 - p));
      if (i >= steps) {
        t.cancel();
        previous?.dispose();
      }
    });
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _current?.setVolume(volume);
  }

  @override
  Future<void> stop() async {
    _fade?.cancel();
    final p = _current;
    _current = null;
    await p?.stop();
    await p?.dispose();
  }
}

class SoundtrackState {
  const SoundtrackState({this.tracks = const [], this.playing, this.mood, this.message, this.loaded = false});

  final List<Track> tracks;
  final Track? playing;
  final String? mood;

  /// Why music isn't playing (shown on request), e.g. no tracks configured.
  final String? message;
  final bool loaded;

  SoundtrackState copyWith({List<Track>? tracks, Track? playing, String? mood, String? message, bool? loaded, bool clearPlaying = false}) =>
      SoundtrackState(
        tracks: tracks ?? this.tracks,
        playing: clearPlaying ? null : playing ?? this.playing,
        mood: clearPlaying ? null : mood ?? this.mood,
        message: message ?? this.message,
        loaded: loaded ?? this.loaded,
      );
}

bool isPaidTier(Tier t) => t != Tier.free;

/// The AI soundtrack: follows each card's mood (set by Claude during
/// segmentation) and plays a matching licensed track. Paid tiers only.
class SoundtrackNotifier extends Notifier<SoundtrackState> {
  /// Overridable in tests.
  static AudioEngine Function() engineFactory = JustAudioEngine.new;

  AudioEngine? _engine;
  final MoodFollower _follower = MoodFollower();
  final List<String> _recent = [];
  bool _ducked = false;
  int? _lastEnergy;

  /// AI soundtrack plans per chapter: (first card, track) per music cue.
  final Map<String, List<(int, Track)>> _plans = {};
  final Set<String> _planning = {};
  DateTime? _lastSwitch;

  @override
  SoundtrackState build() {
    ref.onDispose(() => _engine?.stop());
    return const SoundtrackState();
  }

  AppSettings get _settings => ref.read(settingsProvider);

  bool get _active => _settings.soundtrack && isPaidTier(_settings.tier) && state.tracks.isNotEmpty;

  Future<void> loadCatalog() async {
    if (state.loaded || !isPaidTier(_settings.tier)) return;
    final api = ref.read(apiProvider);
    if (!api.enabled) {
      state = state.copyWith(loaded: true, message: 'The soundtrack needs the BookReel server.');
      return;
    }
    try {
      final tracks = (await api.musicTracks(_settings.tier.name)).map(Track.fromJson).toList();
      state = state.copyWith(
        tracks: tracks,
        loaded: true,
        message: tracks.isEmpty ? 'No licensed tracks have been added to the soundtrack yet.' : null,
      );
    } catch (e) {
      debugPrint('Soundtrack catalog unavailable: $e');
      state = state.copyWith(message: 'Couldn’t load the soundtrack right now.');
    }
  }

  /// Called for each card shown. When the chapter has AI music cues, the
  /// music follows that plan (tracks picked by the AI music supervisor);
  /// otherwise it follows each card's mood.
  Future<void> onPosition({
    required String chapterKey,
    required List<MusicCue> cues,
    required int cardIndex,
    String? mood,
    int? energy,
    bool chapterStart = false,
    String? teaser,
    String? bookTitle,
    DateTime? now,
  }) async {
    if (!_active) return;
    if (cues.isEmpty) return onCard(mood, energy, chapterStart: chapterStart, now: now);
    var plan = _plans[chapterKey];
    if (plan == null) {
      if (!_planning.add(chapterKey)) return; // already being planned
      try {
        plan = await _plan(cues, teaser: teaser, bookTitle: bookTitle);
        _plans[chapterKey] = plan;
      } finally {
        _planning.remove(chapterKey);
      }
    }
    if (plan.isEmpty) return;
    var active = plan.first;
    for (final p in plan) {
      if (p.$1 <= cardIndex) active = p;
    }
    final cue = cues.lastWhere((c) => c.atCard <= cardIndex, orElse: () => cues.first);
    final t = now ?? DateTime.now();
    // Swiping back and forth over a cue boundary shouldn't flip the music.
    if (!chapterStart && _lastSwitch != null && t.difference(_lastSwitch!) < const Duration(seconds: 12)) return;
    await _play(active.$2, cue.mood, t);
  }

  Future<List<(int, Track)>> _plan(List<MusicCue> cues, {String? teaser, String? bookTitle}) async {
    final byId = {for (final t in state.tracks) t.id: t};
    try {
      final picks = await ref.read(apiProvider).musicPlan(_settings.tier.name, cues, teaser: teaser, bookTitle: bookTitle);
      final plan = [
        for (final p in picks)
          if (byId[p['track_id']] != null) ((p['at_card'] as num).toInt(), byId[p['track_id']]!),
      ];
      if (plan.isNotEmpty) return plan;
    } catch (e) {
      debugPrint('Music plan unavailable, matching locally: $e');
    }
    final local = <(int, Track)>[];
    for (final c in cues) {
      final track = pickTrack(state.tracks, c.mood, c.energy, recent: [if (local.isNotEmpty) local.last.$2.id]);
      if (track != null) local.add((c.atCard, track));
    }
    return local;
  }

  /// Card-by-card mood following (chapters without AI music cues).
  Future<void> onCard(String? mood, int? energy, {bool chapterStart = false, DateTime? now}) async {
    if (!_active) return;
    if (energy != null) _lastEnergy = energy;
    final t = now ?? DateTime.now();
    final target = _follower.onCard(mood, t, chapterStart: chapterStart);
    if (target == null) return;
    final track = pickTrack(state.tracks, target, _lastEnergy ?? 2, recent: _recent);
    if (track != null) await _play(track, target, t);
  }

  Future<void> _play(Track track, String mood, DateTime at) async {
    if (track.id == state.playing?.id) return;
    _recent
      ..remove(track.id)
      ..insert(0, track.id);
    if (_recent.length > 3) _recent.removeLast();
    _lastSwitch = at;
    state = state.copyWith(playing: track, mood: mood);
    try {
      await (_engine ??= engineFactory()).crossfadeTo(track.url, _volume);
    } catch (e) {
      debugPrint('Soundtrack playback failed: $e');
    }
  }

  double get _volume => _settings.musicVolume * (_ducked ? 0.3 : 1);

  /// Lowers the music while read-aloud is speaking.
  Future<void> duck(bool on) async {
    _ducked = on;
    await _engine?.setVolume(_volume);
  }

  Future<void> applyVolume() async => _engine?.setVolume(_volume);

  Future<void> stop() async {
    _follower.current = null;
    _lastSwitch = null;
    state = state.copyWith(clearPlaying: true);
    await _engine?.stop();
  }
}

final soundtrackProvider = NotifierProvider<SoundtrackNotifier, SoundtrackState>(SoundtrackNotifier.new);
