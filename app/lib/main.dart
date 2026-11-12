import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/json_store.dart';
import 'data/store_provider.dart';
import 'services/litert_runtime.dart';
import 'services/notifications.dart';
import 'services/on_device_ai.dart';
import 'ui/typography.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  final dir = await getApplicationSupportDirectory();
  final store = await JsonStore.open(dir);
  await ReminderService.instance.init();
  // The Free plan's on-device model runs on LiteRT-LM (loaded only when used).
  OnDeviceAiController.runtimeFactory = LiteRtRuntime.new;
  runApp(ProviderScope(
    overrides: [storeProvider.overrideWithValue(store)],
    child: const BookReelApp(),
  ));
}
