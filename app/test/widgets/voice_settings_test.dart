import 'dart:async';
import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/features/settings/settings_screen.dart';
import 'package:book_reel/services/local_voice.dart';
import 'package:book_reel/ui/kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../services/local_voice_test.dart' show FakeEngine, FakeInstaller;

void main() {
  testWidgets('Read aloud: download the natural voice, see it come down, use it, remove it', (tester) async {
    final dir = Directory.systemTemp.createTempSync('voice_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final installer = FakeInstaller()..gate = Completer<void>();
    LocalVoiceController.installer = installer;
    LocalVoiceController.root = () async => dir;
    LocalSpeech.factory = (_) => FakeEngine();
    late ProviderContainer c;
    await tester.runAsync(() async {
      c = ProviderContainer(overrides: [storeProvider.overrideWithValue(await JsonStore.open(Directory('${dir.path}/store')))]);
    });
    addTearDown(c.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(theme: buildAppTheme(Kit.appLight), home: const Scaffold(body: SingleChildScrollView(child: VoiceSettings()))),
    ));
    await tester.pump();
    await tester.pump();
    expect(c.read(settingsProvider).naturalVoice, isTrue, reason: 'the natural voice is the default');
    expect(find.textContaining('Until then, your phone\'s own voice reads'), findsOneWidget, reason: 'no server in this build');
    final download = find.text('Download the natural voice ($localVoiceDownloadSize)');
    expect(download, findsOneWidget);

    await tester.tap(download);
    await tester.pump();
    expect(find.text('Downloading the voice · 10%'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    installer.gate!.complete();
    await tester.pump();
    await tester.pump();
    expect(c.read(localVoiceProvider).ready, isTrue);
    expect(find.textContaining('running on your phone: free, unlimited and offline'), findsOneWidget);
    expect(find.textContaining('On this phone'), findsOneWidget);

    await tester.tap(find.text('Remove'));
    // Deleting the files is real disk work: let it finish.
    for (var i = 0; i < 5 && c.read(localVoiceProvider).phase != LocalVoicePhase.absent; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
    }
    expect(c.read(localVoiceProvider).phase, LocalVoicePhase.absent);
    await tester.pump();
    expect(download, findsOneWidget);
  });
}
