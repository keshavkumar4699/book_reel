import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/ai_client.dart' show newDeviceId;
import '../data/api_client.dart';
import '../data/segments.dart' show deviceIdProvider;
import '../data/settings_provider.dart';
import '../data/store_provider.dart';
import '../data/sync_service.dart';

/// Your data (Production plan A3): download a copy of it, or delete the
/// account. Google Play requires account deletion inside the app.
class AccountActions {
  AccountActions(this.ref);
  final Ref ref;

  /// What this phone keeps about you (not its identity or sync bookkeeping).
  static const phoneDocs = ['settings', 'library', 'notebook', 'habit', 'sessions', 'mood'];

  /// Everything about you as one JSON document: what's on this phone and,
  /// with online features on, what the server keeps.
  Future<String> exportJson({DateTime? now}) async {
    final store = ref.read(storeProvider);
    final api = ref.read(apiProvider);
    Map<String, dynamic>? server;
    String? note;
    if (api.enabled) {
      try {
        // Upload what's pending first, so the server's copy is complete.
        await ref.read(syncServiceProvider).syncNow();
        server = await api.exportData();
      } catch (_) {
        note = 'Cloro’s server couldn’t be reached, so only this phone’s data is included.';
      }
    }
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'Cloro',
      'format': 1,
      'exported_at': (now ?? DateTime.now()).toUtc().toIso8601String(),
      'phone': {for (final d in phoneDocs) d: store.doc(d)},
      'server': server,
      'note': ?note,
    });
  }

  /// The export as a file to share: cloro-data-YYYY-MM-DD.json.
  Future<File> exportFile({Directory? dir}) async {
    final now = DateTime.now();
    final folder = dir ?? await getTemporaryDirectory();
    final day = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final file = File('${folder.path}/cloro-data-$day.json');
    await file.writeAsString(await exportJson(now: now));
    return file;
  }

  /// Erases the account on the server. Then this phone gets a new identity
  /// and online features turn off, so nothing is uploaded again until you
  /// turn them back on (which starts a new, empty account). Books and notes
  /// on the phone stay. Throws, changing nothing, if the server can't be
  /// reached.
  Future<void> deleteAccount() async {
    await ref.read(apiProvider).deleteAccount();
    final store = ref.read(storeProvider);
    await store.saveDoc('sync', <String, dynamic>{});
    await store.saveDoc('outbox', {'events': <Object>[]});
    await store.saveDoc('device', {'id': newDeviceId()});
    ref.invalidate(deviceIdProvider);
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(online: false));
  }
}

final accountProvider = Provider<AccountActions>(AccountActions.new);
