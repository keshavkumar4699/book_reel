import 'dart:math' as math;

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

  @override
  set onComplete(VoidCallback? callback) => complete = callback;

  @override
  Future<void> load(String asset, {required bool loop}) async {
    this.asset = asset;
    this.loop = loop;
    log.add('load $asset${loop ? ' (loop)' : ''}');
  }

  @override
  Future<void> setVolume(double volume) async => this.volume = volume;

  @override
  Future<void> play() async {
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

/// Silent music, and books that open on the first picture and track.
void quietReader([List<String>? log]) {
  MusicPlayer.playerFactory = () => SilentPlayer(log ?? []);
  MusicPlayer.fade = Duration.zero;
  MusicPlayer.random = FirstPick();
  backdropRandom = FirstPick();
}
