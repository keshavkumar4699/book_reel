import 'dart:async';
import 'dart:io';

import 'package:book_reel/data/json_store.dart';
import 'package:book_reel/data/settings.dart';
import 'package:book_reel/data/settings_provider.dart';
import 'package:book_reel/data/store_provider.dart';
import 'package:book_reel/services/on_device_ai.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const gb = 1024 * 1024 * 1024;

class FakeProbe implements DeviceProbe {
  FakeProbe(this.profile);
  DeviceProfile profile;
  @override
  Future<DeviceProfile> read() async => profile;
}

/// Answers each prompt with [reply]; records what it was asked.
class ScriptedLlm implements LocalLlm {
  ScriptedLlm(this.reply);
  final FutureOr<String> Function(String prompt) reply;
  final prompts = <String>[];
  bool closed = false;

  @override
  Future<String> generate(String prompt, {String? system, int maxOutputTokens = 160, double temperature = 0.3}) async {
    prompts.add(prompt);
    return reply(prompt);
  }

  @override
  Future<void> close() async => closed = true;
}

class FakeRuntime implements LocalModelRuntime {
  final installed = <String>{};
  final uninstalled = <String>[];
  Completer<void>? gate;
  bool failOpen = false;
  int opens = 0;
  ScriptedLlm llm = ScriptedLlm((p) => p);

  @override
  Future<bool> isInstalled(LocalModelOption model) async => installed.contains(model.id);

  @override
  Future<void> install(LocalModelOption model, {required void Function(int percent) onProgress, required LocalCancel cancel}) async {
    onProgress(10);
    if (gate != null) await gate!.future;
    if (cancel.cancelled) throw StateError('cancelled');
    onProgress(100);
    installed.add(model.id);
  }

  @override
  Future<void> uninstall(LocalModelOption model) async {
    installed.remove(model.id);
    uninstalled.add(model.id);
  }

  @override
  Future<LocalLlm> open(LocalModelOption model) async {
    opens++;
    if (failOpen) throw StateError('GPU said no');
    return llm;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late JsonStore store;
  late FakeRuntime runtime;
  late FakeProbe probe;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ondevice');
    store = await JsonStore.open(dir);
    runtime = FakeRuntime();
    probe = FakeProbe(const DeviceProfile(supported: true, totalRamBytes: 6 * gb, freeBytes: 20 * gb));
    OnDeviceAiController.runtimeFactory = () => runtime;
    OnDeviceAiController.probeFactory = () => probe;
  });

  tearDown(() async {
    OnDeviceAiController.runtimeFactory = () => null;
    OnDeviceAiController.probeFactory = PlatformDeviceProbe.new;
    await store.flush();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [storeProvider.overrideWithValue(store)]);
    addTearDown(c.dispose);
    return c;
  }

  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  test('no engine in the build, or a phone that cannot run it: unsupported, with the reason', () async {
    OnDeviceAiController.runtimeFactory = () => null;
    var c = container();
    c.read(onDeviceAiProvider);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.unsupported);
    expect(c.read(onDeviceAiProvider).message, contains('no on-device AI engine'));

    OnDeviceAiController.runtimeFactory = () => runtime;
    probe.profile = const DeviceProfile(supported: false, reason: 'On-device AI needs Android 11 or newer.');
    c = container();
    c.read(onDeviceAiProvider);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.unsupported);
    expect(c.read(onDeviceAiProvider).message, contains('Android 11'));
    expect(c.read(onDeviceAiProvider.notifier).usable, isFalse);
  });

  test('download with progress, then the model writes for Free readers only', () async {
    final c = container();
    c.read(onDeviceAiProvider);
    await settle();
    final ai = c.read(onDeviceAiProvider.notifier);
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.absent);
    // 6 GB of memory: the small model fits, the big one does not.
    expect(c.read(onDeviceAiProvider).fits(localModels[0]), isTrue);
    expect(c.read(onDeviceAiProvider).fits(localModels[1]), isFalse);

    runtime.gate = Completer<void>();
    final done = ai.download(localModels[0]);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.downloading);
    expect(c.read(onDeviceAiProvider).progress, 10);
    runtime.gate!.complete();
    await done;
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.ready);
    expect(c.read(settingsProvider).localModel, 'qwen3-0.6b');
    expect(ai.usable, isTrue);
    expect(await ai.run((llm) => llm.generate('hello')), 'hello');
    expect(runtime.opens, 1);

    // Paid plans get the same help from Claude: the model stays idle.
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.plus));
    expect(ai.usable, isFalse);
    expect(await ai.run((llm) => llm.generate('again')), isNull);
    // Switched off by the reader: also idle.
    c.read(settingsProvider.notifier).update((s) => s.copyWith(tier: Tier.free, onDeviceAi: false));
    expect(ai.usable, isFalse);
  });

  test('a word tapped now goes before background recaps', () async {
    runtime.installed.add('qwen3-0.6b');
    final first = Completer<String>();
    runtime.llm = ScriptedLlm((p) => p == 'recap 1' ? first.future : p);
    final c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: 'qwen3-0.6b'));
    c.read(onDeviceAiProvider);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.ready);
    final ai = c.read(onDeviceAiProvider.notifier);
    final a = ai.run((llm) => llm.generate('recap 1'));
    await settle();
    final b = ai.run((llm) => llm.generate('recap 2'));
    final word = ai.run((llm) => llm.generate('word'), urgent: true);
    first.complete('done');
    expect(await Future.wait([a, b, word]), ['done', 'recap 2', 'word']);
    expect(runtime.llm.prompts, ['recap 1', 'word', 'recap 2']);
  });

  test('cancel a download, remove a model, and recover from a model that will not load', () async {
    final c = container();
    c.read(onDeviceAiProvider);
    await settle();
    final ai = c.read(onDeviceAiProvider.notifier);

    runtime.gate = Completer<void>();
    final done = ai.download(localModels[0]);
    await settle();
    ai.cancelDownload();
    runtime.gate!.complete();
    await done;
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.absent);
    expect(c.read(settingsProvider).localModel, isNull);

    runtime.gate = null;
    await ai.download(localModels[0]);
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.ready);

    runtime.failOpen = true;
    expect(await ai.run((llm) => llm.generate('x')), isNull);
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.failed);
    expect(c.read(onDeviceAiProvider).message, contains('couldn’t load'));
    runtime.failOpen = false;
    ai.retry();
    expect(await ai.run((llm) => llm.generate('y')), 'y');

    await ai.remove();
    expect(runtime.uninstalled, ['qwen3-0.6b']);
    expect(runtime.llm.closed, isTrue);
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.absent);
    expect(c.read(settingsProvider).localModel, isNull);
  });

  test('at start: a downloaded model is ready; one whose file is gone is forgotten', () async {
    var c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: 'qwen3-0.6b'));
    c.read(onDeviceAiProvider);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.absent);
    expect(c.read(settingsProvider).localModel, isNull);

    runtime.installed.add('qwen3-0.6b');
    c = container();
    c.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: 'qwen3-0.6b'));
    c.read(onDeviceAiProvider);
    await settle();
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.ready);
    expect(c.read(onDeviceAiProvider).model?.name, 'Qwen3 0.6B');
  });

  test('not enough free space: says how much is needed', () async {
    probe.profile = DeviceProfile(supported: true, totalRamBytes: 6 * gb, freeBytes: 300 * 1000 * 1000);
    final c = container();
    c.read(onDeviceAiProvider);
    await settle();
    await c.read(onDeviceAiProvider.notifier).download(localModels[0]);
    expect(c.read(onDeviceAiProvider).phase, LocalAiPhase.failed);
    expect(c.read(onDeviceAiProvider).message, contains('Not enough free space'));
    expect(runtime.installed, isEmpty);
  });
}
