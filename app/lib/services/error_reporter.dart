import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/settings_provider.dart';

/// Crash reports (Production plan A7): errors the app didn't handle go to the
/// Cloro server, which logs them for Google Cloud Error Reporting (grouped by
/// stack trace, with alerts). Native crashes and freezes are covered by Google
/// Play's Android vitals.
///
/// Only the error, where it happened, the app version and the platform are
/// sent, and only with online features and "Send crash reports" on. Each
/// distinct error is sent once, at most [maxPerRun] per run.
class ErrorReporter {
  ErrorReporter(this._container);

  final ProviderContainer _container;

  static const version = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');
  static const maxPerRun = 10;

  final Set<int> _seen = {};
  int _sent = 0;

  /// Catches framework and uncaught asynchronous errors (keeping any
  /// handler already there, so they're still printed while debugging).
  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(report(details.exception, details.stack));
    };
    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(report(error, stack));
      return previousPlatform?.call(error, stack) ?? false;
    };
  }

  /// Sends one error; false when it wasn't sent (off, offline, repeated, too many).
  Future<bool> report(Object error, StackTrace? stack) async {
    final settings = _container.read(settingsProvider);
    if (!settings.crashReports) return false;
    final api = _container.read(apiProvider);
    if (!api.enabled) return false;
    final message = _cut(error.toString(), 500);
    final trace = _cut(stack?.toString() ?? '', 8000);
    // The same error from the same place counts once.
    final key = Object.hash(error.runtimeType, message, trace.split('\n').take(4).join('\n'));
    if (!_seen.add(key) || _sent >= maxPerRun) return false;
    _sent++;
    try {
      await api.reportError(message: message, stack: trace, version: version);
      return true;
    } catch (_) {
      return false; // offline: not worth retrying a crash report
    }
  }

  static String _cut(String s, int max) => s.length <= max ? s : s.substring(0, max);
}
