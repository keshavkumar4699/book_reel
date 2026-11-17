import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/settings.dart';
import '../data/settings_provider.dart';

/// Your own music goes here (MP3, M4A, AAC, OGG, Opus, WAV or FLAC). The
/// folder is listed in pubspec.yaml; until it has tracks, the calm ambient
/// loops play instead.
const musicDir = 'assets/sounds/music/';

final _musicFile = RegExp(r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac)$', caseSensitive: false);

/// Something the player plays: one of your tracks (played through, then the
/// next one), or an ambient loop (repeats until you skip it).
@immutable
class Track {
  const Track(this.asset, this.title, {this.loop = false});

  final String asset;
  final String title;
  final bool loop;

  @override
  bool operator ==(Object other) => other is Track && other.asset == asset;

  @override
  int get hashCode => asset.hashCode;

  @override
  String toString() => 'Track($asset)';
}

/// The ambient loops (assets/sounds; sources and licences in CREDITS.md).
const ambientTracks = [
  Track('assets/sounds/rain.ogg', 'Rain on the window', loop: true),
  Track('assets/sounds/cafe.ogg', 'Café murmur', loop: true),
  Track('assets/sounds/waves.ogg', 'Surf on the shore', loop: true),
  Track('assets/sounds/birds.ogg', 'Morning birdsong', loop: true),
  Track('assets/sounds/wind.ogg', 'Wind in the pines', loop: true),
  Track('assets/sounds/fireplace.ogg', 'A fire in the cabin', loop: true),
  Track('assets/sounds/crickets.ogg', 'Crickets at night', loop: true),
  Track('assets/sounds/city.ogg', 'Distant city', loop: true),
  Track('assets/sounds/brown-noise.ogg', 'Soft focus noise', loop: true),
];

/// A track's file name as words ("01 - Clair_de_lune.mp3" → "Clair de lune").
String trackTitle(String asset) {
  var name = asset.split('/').last.replaceFirst(_musicFile, '');
  name = name.replaceFirst(RegExp(r'^\d+\s*[-.)_]\s*'), '').replaceAll(RegExp(r'[_]+'), ' ').trim();
  return name.isEmpty ? 'Track' : name[0].toUpperCase() + name.substring(1);
}

/// Your tracks in name order, or until there are any the ambient loops.
List<Track> tracksFrom(Iterable<String> assets) {
  final mine = [for (final a in assets) if (a.startsWith(musicDir) && _musicFile.hasMatch(a)) a]..sort();
  return mine.isNotEmpty ? [for (final a in mine) Track(a, trackTitle(a))] : ambientTracks;
}

final tracksProvider = FutureProvider<List<Track>>((ref) async {
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  return tracksFrom(manifest.listAssets());
});

/// One audio player, behind an interface so the logic is testable.
abstract class TrackPlayer {
  /// Loads [asset]; with [loop] it repeats until something else is loaded.
  Future<void> load(String asset, {required bool loop});
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();

  /// Called when a track that doesn't loop reaches its end.
  set onComplete(VoidCallback? callback);
}

class JustAudioTrackPlayer implements TrackPlayer {
  JustAudioTrackPlayer() {
    _states = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onComplete?.call();
    });
  }

  // No audio-session activation: the music mixes with read-aloud and other
  // apps instead of pausing them, and nothing else can silence it for good.
  final AudioPlayer _player = AudioPlayer(handleAudioSessionActivation: false);
  late final StreamSubscription<ProcessingState> _states;
  VoidCallback? _onComplete;

  @override
  set onComplete(VoidCallback? callback) => _onComplete = callback;

  @override
  Future<void> load(String asset, {required bool loop}) async {
    await _player.setLoopMode(loop ? LoopMode.one : LoopMode.off);
    await _player.setAsset(asset);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  // play() only completes when playback stops; don't wait for it.
  @override
  Future<void> play() async => unawaited(_player.play());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() async {
    await _states.cancel();
    await _player.dispose();
  }
}

@immutable
class MusicState {
  const MusicState({this.tracks = const [], this.index = 0, this.playing = false});

  final List<Track> tracks;
  final int index;

  /// Playing, as the play/pause button shows it (a reader hidden behind
  /// another tab or the app in the background is silent but still "playing").
  final bool playing;

  Track? get track => tracks.isEmpty ? null : tracks[index.clamp(0, tracks.length - 1)];

  MusicState copyWith({int? index, bool? playing}) =>
      MusicState(tracks: tracks, index: index ?? this.index, playing: playing ?? this.playing);
}

/// What plays while you read. Each book opens on a random track; previous,
/// play/pause and next are in the reader's controls. Your own tracks play
/// through and move on to the next; ambient loops repeat until skipped. It's
/// quieter under read-aloud and silent when the reader is out of sight.
class MusicPlayer extends Notifier<MusicState> {
  static TrackPlayer Function() playerFactory = JustAudioTrackPlayer.new;

  /// The fade in when a track starts; zero in tests.
  static Duration fade = const Duration(milliseconds: 600);

  /// Picks each book's first track.
  static math.Random random = math.Random();

  TrackPlayer? _player;
  String? _loaded;

  /// The reader that started the music (a new book's reader starts before
  /// the old one is gone, so only the owner can stop it).
  Object? _owner;
  bool _held = false;
  bool _ducked = false;
  Timer? _fadeTimer;
  int _generation = 0;

  @override
  MusicState build() {
    ref.onDispose(() {
      _fadeTimer?.cancel();
      unawaited(_player?.dispose());
    });
    return const MusicState();
  }

  AppSettings get _settings => ref.read(settingsProvider);
  double get _level => _settings.musicVolume * (_ducked ? 0.3 : 1);

  /// A book opened: a random track, playing if music is on (else ready to play).
  Future<void> start(Object owner) async {
    _owner = owner;
    final tracks = await ref.read(tracksProvider.future);
    if (!identical(_owner, owner) || tracks.isEmpty) return;
    state = MusicState(tracks: tracks, index: random.nextInt(tracks.length));
    await _load(play: _settings.music);
  }

  /// The book closed (only its own reader stops the music).
  Future<void> stop(Object owner) async {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _generation++;
    _fadeTimer?.cancel();
    final player = _player;
    _player = null;
    _loaded = null;
    state = state.copyWith(playing: false);
    if (player != null) {
      await player.pause();
      await player.dispose();
    }
  }

  Future<void> next() => _skip(1);
  Future<void> previous() => _skip(-1);

  /// Skipping plays the new track, even if the music was paused.
  Future<void> _skip(int by) async {
    final n = state.tracks.length;
    if (n == 0 || _owner == null) return;
    state = state.copyWith(index: ((state.index + by) % n + n) % n);
    await _load(play: true);
  }

  /// The play/pause button.
  Future<void> toggle() async {
    if (_owner == null || state.track == null) return;
    if (state.playing) {
      _generation++;
      _fadeTimer?.cancel();
      state = state.copyWith(playing: false);
      await _player?.pause();
    } else if (_loaded == state.track!.asset && _player != null) {
      state = state.copyWith(playing: true);
      if (!_held) await _begin(_player!, _generation);
    } else {
      await _load(play: true);
    }
  }

  /// The reader went out of sight (another tab, the app in the background):
  /// silent until [release], which carries on where it was.
  Future<void> hold() async {
    _held = true;
    _fadeTimer?.cancel();
    await _player?.pause();
  }

  Future<void> release() async {
    _held = false;
    final player = _player;
    if (player != null && state.playing && _owner != null) await _begin(player, _generation);
  }

  /// Quieter while the book is read aloud.
  Future<void> duck(bool on) async {
    _ducked = on;
    await applyVolume();
  }

  /// The volume setting changed.
  Future<void> applyVolume() async {
    _fadeTimer?.cancel();
    await _player?.setVolume(_level);
  }

  Future<void> _load({required bool play}) async {
    final track = state.track;
    if (track == null) return;
    final generation = ++_generation;
    _fadeTimer?.cancel();
    final player = _player ??= playerFactory()..onComplete = _completed;
    state = state.copyWith(playing: play);
    try {
      await player.pause();
      await player.setVolume(0);
      await player.load(track.asset, loop: track.loop);
      if (generation != _generation || !identical(player, _player)) return;
      _loaded = track.asset;
      if (play && !_held) await _begin(player, generation);
    } catch (e) {
      debugPrint('Music unavailable: $e');
      if (generation == _generation) state = state.copyWith(playing: false);
    }
  }

  /// Plays from silence up to the reader's volume.
  Future<void> _begin(TrackPlayer player, int generation) async {
    await player.setVolume(fade == Duration.zero ? _level : 0);
    await player.play();
    if (fade == Duration.zero) return;
    const steps = 12;
    var i = 0;
    _fadeTimer?.cancel();
    _fadeTimer = Timer.periodic(fade ~/ steps, (t) {
      i++;
      if (generation != _generation || !identical(player, _player)) {
        t.cancel();
        return;
      }
      unawaited(player.setVolume(_level * (i / steps)));
      if (i >= steps) t.cancel();
    });
  }

  void _completed() {
    if (_owner != null && state.playing && !(state.track?.loop ?? true)) unawaited(next());
  }
}

final musicProvider = NotifierProvider<MusicPlayer, MusicState>(MusicPlayer.new);
