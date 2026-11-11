import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../data/settings.dart';
import '../data/settings_provider.dart';

/// Is this tier paid (AI direction, Auto scenes, AI fonts)?
bool isPaidTier(Tier t) => t != Tier.free;

/// One looping recording in a scene's mix.
class SoundLayer {
  const SoundLayer(this.name, this.volume);

  /// File in assets/sounds/ (without extension).
  final String name;

  /// Level in the mix, 0–1 (all recordings are levelled to the same loudness).
  final double volume;

  String get asset => 'assets/sounds/$name.ogg';
}

/// What each scene sounds like. Recordings are public domain, CC0 or CC BY
/// (assets/sounds/CREDITS.md). Layers loop independently, so their different
/// lengths keep the mix from audibly repeating.
const sceneSounds = <Vibe, List<SoundLayer>>{
  Vibe.forest: [SoundLayer('wind', 0.5), SoundLayer('birds', 0.3), SoundLayer('crickets', 0.22)],
  Vibe.cafe: [SoundLayer('cafe', 0.75), SoundLayer('rain', 0.28)],
  Vibe.rain: [SoundLayer('rain', 0.85), SoundLayer('city', 0.14)],
  Vibe.ocean: [SoundLayer('waves', 0.85), SoundLayer('wind', 0.18)],
  Vibe.night: [SoundLayer('crickets', 0.6), SoundLayer('wind', 0.28)],
  Vibe.meadow: [SoundLayer('birds', 0.7), SoundLayer('wind', 0.22)],
  Vibe.snow: [SoundLayer('fireplace', 0.7), SoundLayer('wind', 0.4)],
  Vibe.city: [SoundLayer('city', 0.8)],
  Vibe.paper: [SoundLayer('brown-noise', 0.55)],
};

/// What the reader hears, in a few words.
const sceneSoundLabels = <Vibe, String>{
  Vibe.forest: 'Wind in the pines, birds and crickets',
  Vibe.cafe: 'Café murmur, rain outside',
  Vibe.rain: 'Rain on the window',
  Vibe.ocean: 'Waves and sea wind',
  Vibe.night: 'Crickets and night wind',
  Vibe.meadow: 'Birdsong and a breeze',
  Vibe.snow: 'Crackling fire, wind outside',
  Vibe.city: 'Distant city traffic',
  Vibe.paper: 'Soft focus noise',
};

/// One looping player. Behind an interface so the logic is testable.
abstract class LoopPlayer {
  Future<void> load(String asset);
  Future<void> setVolume(double volume);
  Future<void> play();
  Future<void> pause();
  Future<void> dispose();
}

class JustAudioLoop implements LoopPlayer {
  // No audio-session activation: the scene sound mixes with other apps
  // instead of pausing the reader's own music, and a music app starting
  // never silences it. Readers mute it with one tap.
  final AudioPlayer _player = AudioPlayer(handleAudioSessionActivation: false);

  @override
  Future<void> load(String asset) async {
    await _player.setLoopMode(LoopMode.one);
    await _player.setAsset(asset);
  }

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> play() async => unawaited(_player.play());

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> dispose() => _player.dispose();
}

class SceneSoundState {
  const SceneSoundState({this.scene, this.playing = false});

  /// The scene whose sound is playing (or would be, if not muted).
  final Vibe? scene;
  final bool playing;
}

/// Plays the ambient sound of the scene behind the reader: crossfades when the
/// scene changes (including the AI's Auto scenes), pauses in the background,
/// ducks under read-aloud, and follows the reader's on/off and volume.
class SceneSoundController extends Notifier<SceneSoundState> {
  static LoopPlayer Function() playerFactory = JustAudioLoop.new;

  /// Crossfade length; zero in tests.
  static Duration fade = const Duration(milliseconds: 1500);

  List<(SoundLayer, LoopPlayer)> _layers = const [];
  final List<List<(SoundLayer, LoopPlayer)>> _fadingOut = [];
  Timer? _timer;
  bool _ducked = false;
  bool _paused = false;
  int _generation = 0;

  @override
  SceneSoundState build() {
    ref.onDispose(() {
      _timer?.cancel();
      for (final l in [..._layers, ..._fadingOut.expand((x) => x)]) {
        l.$2.dispose();
      }
    });
    return const SceneSoundState();
  }

  AppSettings get _settings => ref.read(settingsProvider);

  double _level(SoundLayer layer) => layer.volume * _settings.sceneSoundVolume * (_ducked ? 0.3 : 1);

  /// Starts (or crossfades to) [scene]'s sound, if scene sound is on.
  Future<void> play(Vibe scene) async {
    if (!_settings.sceneSound) {
      await stop();
      state = SceneSoundState(scene: scene);
      return;
    }
    if (state.scene == scene && state.playing) return;
    final generation = ++_generation;
    final previous = _layers;
    final next = <(SoundLayer, LoopPlayer)>[];
    try {
      for (final layer in sceneSounds[scene] ?? const <SoundLayer>[]) {
        final player = playerFactory();
        next.add((layer, player));
        await player.load(layer.asset);
        await player.setVolume(0);
        if (!_paused) await player.play();
      }
    } catch (e) {
      debugPrint('Scene sound unavailable: $e');
      for (final l in next) {
        unawaited(l.$2.dispose());
      }
      return;
    }
    if (generation != _generation) {
      // A newer scene was requested while this one loaded.
      for (final l in next) {
        unawaited(l.$2.dispose());
      }
      return;
    }
    _layers = next;
    if (previous.isNotEmpty) _fadingOut.add(previous);
    state = SceneSoundState(scene: scene, playing: true);
    await _crossfade(next, previous);
  }

  Completer<void>? _fading;

  Future<void> _crossfade(List<(SoundLayer, LoopPlayer)> into, List<(SoundLayer, LoopPlayer)> from) {
    // A crossfade still running is cut short: whatever it was fading out
    // stops now, so no player is left behind.
    _timer?.cancel();
    if (_fading != null && !_fading!.isCompleted) _fading!.complete();
    for (final old in [..._fadingOut]) {
      if (identical(old, from)) continue;
      _release(old);
    }
    final done = _fading = Completer<void>();
    final steps = fade == Duration.zero ? 1 : 20;
    var i = 0;
    void step() {
      i++;
      final p = i / steps;
      for (final (layer, player) in into) {
        player.setVolume(_level(layer) * p);
      }
      for (final (layer, player) in from) {
        player.setVolume(_level(layer) * (1 - p));
      }
      if (i >= steps) {
        _timer?.cancel();
        _release(from);
        if (!done.isCompleted) done.complete();
      }
    }

    if (steps == 1) {
      step();
    } else {
      _timer = Timer.periodic(fade ~/ steps, (_) => step());
    }
    return done.future;
  }

  void _release(List<(SoundLayer, LoopPlayer)> layers) {
    _fadingOut.removeWhere((x) => identical(x, layers));
    for (final (_, player) in layers) {
      unawaited(player.pause().then((_) => player.dispose()));
    }
  }

  /// Fades out and releases the players (leaving the reader, or muted).
  Future<void> stop() async {
    _generation++;
    final current = _layers;
    _layers = const [];
    state = SceneSoundState(scene: state.scene);
    if (current.isEmpty) return;
    _fadingOut.add(current);
    await _crossfade(const [], current);
  }

  /// The app went to the background: silence without forgetting the scene.
  Future<void> pause() async {
    _paused = true;
    for (final (_, player) in _layers) {
      await player.pause();
    }
  }

  Future<void> resume() async {
    _paused = false;
    if (!_settings.sceneSound) return;
    for (final (_, player) in _layers) {
      await player.play();
    }
  }

  /// Quieter while the book is read aloud.
  Future<void> duck(bool on) async {
    _ducked = on;
    await applyVolume();
  }

  /// Re-applies the reader's volume setting.
  Future<void> applyVolume() async {
    for (final (layer, player) in _layers) {
      await player.setVolume(_level(layer));
    }
  }
}

final sceneSoundProvider = NotifierProvider<SceneSoundController, SceneSoundState>(SceneSoundController.new);
