import 'dart:math' as math;

import 'package:book_reel/data/app_assets.dart';
import 'package:book_reel/services/music.dart';
import 'package:book_reel/ui/backdrops.dart';
import 'package:flutter/foundation.dart';

/// Records what would be played (tests have no audio plugin).
class SilentPlayer implements TrackPlayer {
  SilentPlayer(this.log, [this.all]) {
    all?.add(this);
  }

  final List<String> log;
  final List<SilentPlayer>? all;
  String? asset;
  bool loop = false;
  double volume = 1;
  bool playing = false;
  bool disposed = false;
  VoidCallback? complete;
  VoidCallback? error;

  @override
  set onComplete(VoidCallback? callback) => complete = callback;

  @override
  set onError(VoidCallback? callback) => error = callback;

  /// Something outside the app paused it (as a call or another app can).
  void pausedOutside() => playing = false;

  /// The track stopped on an error.
  void fail() {
    playing = false;
    log.add('error');
    error?.call();
  }

  @override
  Future<void> load(String asset, {required bool loop}) async {
    this.asset = asset;
    this.loop = loop;
    log.add('load $asset${loop ? ' (loop)' : ''}');
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  /// Like the real player: play while playing does nothing.
  @override
  Future<void> play() async {
    if (playing) return;
    playing = true;
    log.add('play');
  }

  @override
  Future<void> pause() async {
    if (playing) log.add('pause');
    playing = false;
  }

  @override
  Future<void> dispose() async {
    playing = false;
    disposed = true;
    log.add('dispose');
  }
}

/// Always the first choice: the first picture and the first track.
class FirstPick implements math.Random {
  @override
  int nextInt(int max) => 0;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// Two tracks and no pictures, whatever the app's own folders hold: tests
/// don't change when music or pictures are added.
const testAssets = ['assets/sounds/Artist - First.mp3', 'assets/sounds/Artist - Second.mp3'];

/// Silent music, and books that open on the first picture (a painted scene)
/// and the first track.
void quietReader([List<String>? log]) {
  MusicPlayer.playerFactory = () => SilentPlayer(log ?? []);
  MusicPlayer.fade = Duration.zero;
  MusicPlayer.random = FirstPick();
  backdropRandom = FirstPick();
  AppAssets.list = () async => testAssets;
}
