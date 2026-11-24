import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/app_assets.dart';
import '../data/settings.dart';
import '../data/settings_provider.dart';

/// Music is every track (MP3, M4A, AAC, OGG, Opus, WAV or FLAC) in these
/// folders, both listed in pubspec.yaml: a track added to either is in the
/// next build.
const musicDirs = ['assets/sounds/', 'assets/sounds/music/'];

final _musicFile = RegExp(r'\.(mp3|m4a|aac|ogg|oga|opus|wav|flac)$', caseSensitive: false);

/// One of your tracks: played through, then the next one.
@immutable
class Track {
  const Track(this.asset, this.title, {this.artist, this.loop = false});

  final String asset;
  final String title;
  final String? artist;

  /// Repeats until skipped (none of the bundled music does).
  final bool loop;

  /// "Jay · Lukrembo", or just the title.
  String get label => artist == null ? title : '$title · $artist';

  @override
  bool operator ==(Object other) => other is Track && other.asset == asset;

  @override
  int get hashCode => asset.hashCode;

  @override
  String toString() => 'Track($asset)';
}

/// A track from its file name: "Lukrembo - Jay (freetouse.com).mp3" is
/// "Jay" by Lukrembo; "01 - Clair_de_lune.mp3" is "Clair de lune". A
/// trailing note in brackets (where it came from) is left out.
Track trackFromAsset(String asset) {
  var name = asset.split('/').last.replaceFirst(_musicFile, '');
  name = name.replaceAll('_', ' ').replaceFirst(RegExp(r'\s*[\(\[][^\)\]]*[\)\]]\s*$'), '');
  name = name.replaceFirst(RegExp(r'^\d+\s*(?:[-.)]\s*|\s+)'), '').replaceAll(RegExp(r'\s+'), ' ').trim();
  String cap(String x) => x.isEmpty ? x : x[0].toUpperCase() + x.substring(1);
  final dash = name.indexOf(' - ');
  if (dash > 0 && dash < name.length - 3) {
    return Track(asset, cap(name.substring(dash + 3).trim()), artist: name.substring(0, dash).trim());
  }
  return Track(asset, name.isEmpty ? 'Track' : cap(name));
}

/// Your tracks, by file name (none: no music).
List<Track> tracksFrom(Iterable<String> assets) {
  final mine = [
    for (final a in assets)
      if (_musicFile.hasMatch(a) && musicDirs.contains(a.substring(0, a.lastIndexOf('/') + 1))) a,
  ]..sort((a, b) => a.split('/').last.toLowerCase().compareTo(b.split('/').last.toLowerCase()));
  return [for (final a in mine) trackFromAsset(a)];
}

final tracksProvider = FutureProvider<List<Track>>((ref) async => tracksFrom(await AppAssets.list()));

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

  /// Called when the track stops on an error (the player can't go on with it).
  set onError(VoidCallback? callback);
}

class JustAudioTrackPlayer implements TrackPlayer {
  JustAudioTrackPlayer() {
    _states = _player.processingStateStream.listen((s) {
      if (s == ProcessingState.completed) _onComplete?.call();
    });
    _errors = _player.errorStream.listen((e) {
      debugPrint('Music stopped: $e');
      _onError?.call();
    });
  }

  // No audio-session activation: the music mixes with read-aloud and other
  // apps instead of pausing them, and nothing else can silence it for good.
  final AudioPlayer _player = AudioPlayer(handleAudioSessionActivation: false);
  late final StreamSubscription<ProcessingState> _states;
  late final StreamSubscription<PlayerException> _errors;
  VoidCallback? _onComplete;
  VoidCallback? _onError;

  @override
  set onComplete(VoidCallback? callback) => _onComplete = callback;

  @override
  set onError(VoidCallback? callback) => _onError = callback;

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
    await _errors.cancel();
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

  /// Readers whose music a newer one took over, oldest first: a look at a
  /// saved reel opens over the book you're reading, which gets its track
  /// back when the look closes (see [stop]).
  final List<({Object owner, List<Track> tracks, int index, bool playing, bool held})> _under = [];
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
    // "Play music while reading" switched (in Settings or the reader's
    // options): the open book's music follows.
    ref.listen<bool>(settingsProvider.select((s) => s.music), (before, on) {
      if (before != on && _owner != null && state.track != null && on != state.playing) unawaited(toggle());
    });
    return const MusicState();
  }

  AppSettings get _settings => ref.read(settingsProvider);
  double get _level => _settings.musicVolume * (_ducked ? 0.3 : 1);

  /// A book opened: a random track, playing if music is on (else ready to
  /// play). [visible]: its reader is on screen (a book can open behind
  /// another tab or page; it plays once [release]d).
  Future<void> start(Object owner, {bool visible = true}) async {
    final before = _owner;
    if (before != null && !identical(before, owner)) {
      _under.add((owner: before, tracks: state.tracks, index: state.index, playing: state.playing, held: _held));
    }
    _owner = owner;
    // Nothing carries over from the last book: not being out of sight, not
    // being quieter under its voice, not its track.
    _held = !visible;
    _ducked = false;
    _failures = 0;
    _generation++;
    _fadeTimer?.cancel();
    _loaded = null;
    unawaited(_player?.pause());
    final tracks = await ref.read(tracksProvider.future);
    if (!ref.mounted || !identical(_owner, owner) || tracks.isEmpty) return;
    state = MusicState(tracks: tracks, index: random.nextInt(tracks.length));
    await _load(play: _settings.music);
  }

  /// The book closed (only its own reader stops the music). The reader under
  /// it, if any, gets its own track back, as it was: playing or paused, and
  /// silent while it's out of sight.
  Future<void> stop(Object owner) async {
    // (Once the app's providers are gone, so is the player.)
    if (!ref.mounted) return;
    if (!identical(_owner, owner)) {
      // A reader under another closed (the book before, once a new book
      // opened in its place): nothing to give back to it.
      _under.removeWhere((u) => identical(u.owner, owner));
      return;
    }
    if (_under.isNotEmpty) {
      final back = _under.removeLast();
      _owner = back.owner;
      _held = back.held;
      _ducked = false;
      _failures = 0;
      _fadeTimer?.cancel();
      state = MusicState(tracks: back.tracks, index: back.index, playing: back.playing);
      await _load(play: back.playing);
      return;
    }
    _owner = null;
    _held = false;
    _ducked = false;
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
    _failures = 0;
    state = state.copyWith(index: ((state.index + by) % n + n) % n);
    await _load(play: true);
  }

  /// The play/pause button.
  Future<void> toggle() async {
    if (_owner == null || state.track == null) return;
    _failures = 0;
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
    if (!ref.mounted) return;
    _held = true;
    _fadeTimer?.cancel();
    await _player?.pause();
  }

  Future<void> release() async {
    // Not held (nothing went out of sight): it plays on, without fading in again.
    if (!ref.mounted || !_held) return;
    _held = false;
    final player = _player;
    if (player != null && _shouldSound) await _begin(player, _generation);
  }

  /// The track should be heard: playing, loaded, in sight.
  bool get _shouldSound => state.playing && _owner != null && !_held && _loaded != null && _loaded == state.track?.asset;

  /// Quieter while the book is read aloud. Back to full volume afterwards,
  /// and playing (whatever paused it meanwhile).
  Future<void> duck(bool on) async {
    if (!ref.mounted) return;
    _ducked = on;
    await applyVolume();
    final player = _player;
    if (!on && player != null && _shouldSound) await player.play();
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
    final player = _player ??= playerFactory()
      ..onComplete = _completed
      ..onError = _failed;
    state = state.copyWith(playing: play);
    try {
      await player.pause();
      await player.setVolume(0);
      await player.load(track.asset, loop: track.loop);
      if (!ref.mounted || generation != _generation || !identical(player, _player)) return;
      _loaded = track.asset;
      if (play && !_held) await _begin(player, generation);
    } catch (e) {
      debugPrint('Music unavailable: $e');
      if (ref.mounted && generation == _generation) state = state.copyWith(playing: false);
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
    if (!ref.mounted) return;
    _failures = 0;
    if (_owner != null && state.playing && !(state.track?.loop ?? true)) unawaited(next());
  }

  /// Tracks that stopped on an error in a row.
  int _failures = 0;

  /// The track stopped on an error (the sound device changed, say): it's
  /// loaded again where it plays from the start, or the next one is tried;
  /// after a few, the music shows paused.
  void _failed() {
    if (!ref.mounted || _owner == null || !state.playing) return;
    _failures++;
    if (_failures > 3) {
      _generation++;
      _fadeTimer?.cancel();
      state = state.copyWith(playing: false);
      return;
    }
    _loaded = null;
    if (_failures > 1 && state.tracks.length > 1) {
      state = state.copyWith(index: (state.index + 1) % state.tracks.length);
    }
    unawaited(_load(play: true));
  }
}

final musicProvider = NotifierProvider<MusicPlayer, MusicState>(MusicPlayer.new);
