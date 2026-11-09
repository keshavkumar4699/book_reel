import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings.dart';
import 'store_provider.dart';

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    final json = ref.read(storeProvider).doc('settings');
    return json == null ? const AppSettings() : AppSettings.fromJson(json);
  }

  void update(AppSettings Function(AppSettings s) change) {
    state = change(state);
    ref.read(storeProvider).saveDoc('settings', state.toJson());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
