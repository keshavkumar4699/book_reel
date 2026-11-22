import 'package:flutter/services.dart';

/// The files bundled with the app (from the build's asset manifest), where
/// the reader's pictures and music are found. Tests replace [list].
class AppAssets {
  const AppAssets._();

  static Future<Iterable<String>> Function() list = _manifest;

  static Future<Iterable<String>> _manifest() async => (await AssetManifest.loadFromAssetBundle(rootBundle)).listAssets();
}
