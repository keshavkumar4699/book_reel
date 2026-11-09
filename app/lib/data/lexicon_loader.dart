import 'dart:convert';
import 'dart:io' show gzip;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/text/lexicon.dart';

Lexicon _build((Uint8List, Uint8List) data) => Lexicon.fromAssets(
      zipfTsv: utf8.decode(gzip.decode(data.$1)),
      dictionaryJson: jsonDecode(utf8.decode(gzip.decode(data.$2))) as Map<String, dynamic>,
    );

/// Loads the bundled frequency list and WordNet subset off the UI thread.
final lexiconProvider = FutureProvider<Lexicon>((ref) async {
  final zipf = await rootBundle.load('assets/lexicon/zipf.tsv.gz');
  final dict = await rootBundle.load('assets/lexicon/wordnet.json.gz');
  return compute(_build, (zipf.buffer.asUint8List(), dict.buffer.asUint8List()));
});
