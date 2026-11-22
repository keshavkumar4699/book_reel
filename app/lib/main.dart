import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/json_store.dart';
import 'data/settings_provider.dart';
import 'data/store_provider.dart';
import 'l10n/l10n.dart';
import 'services/error_reporter.dart';
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
  final container = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
  // The app's language, ready before the first screen.
  Strings.current = await Strings.load(resolveLanguage(container.read(settingsProvider).language, PlatformDispatcher.instance.locales));
  // Crash reports (Settings → Send crash reports), from here on.
  ErrorReporter(container).install();
  runApp(UncontrolledProviderScope(container: container, child: const BookReelApp()));
}
