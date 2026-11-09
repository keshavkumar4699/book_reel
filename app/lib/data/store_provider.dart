import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'json_store.dart';

/// Overridden in `main()` (and tests) with an opened [JsonStore].
final storeProvider = Provider<JsonStore>((ref) => throw UnimplementedError('storeProvider must be overridden'));
