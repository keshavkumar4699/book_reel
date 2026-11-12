import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/settings_provider.dart';

/// On-device AI for the Free plan (DESIGN.md §4.3, IMPLEMENTATION_PLAN.md
/// Phase 8): a small open-weight language model, downloaded once, that writes
/// recaps, quick checks, chapter teasers and word meanings on the phone. The
/// book never leaves the device and nothing is billed.
///
/// This file knows no engine: [LocalModelRuntime] is the seam, and
/// `litert_runtime.dart` (LiteRT-LM through flutter_edge_ai) fills it in
/// `main.dart`. Tests use fakes.

/// A model the reader can download.
@immutable
class LocalModelOption {
  const LocalModelOption({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.minRamBytes,
    required this.licence,
    required this.blurb,
  });

  final String id;
  final String name;
  final int sizeBytes;

  /// Total phone memory the model needs to run comfortably.
  final int minRamBytes;
  final String licence;
  final String blurb;

  String get sizeLabel => formatBytes(sizeBytes);
}

/// "345 MB", "2.0 GB".
String formatBytes(int bytes) =>
    bytes >= 1000 * 1000 * 1000 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).round()} MB';

/// The models on offer, smallest first. Both are Apache-2.0 open weights from
/// Google's LiteRT community builds, pinned by commit and SHA-256 in the
/// engine's catalog. Phones advertised as "4 GB" report about 3.6 GB.
const localModels = [
  LocalModelOption(
    id: 'qwen3-0.6b',
    name: 'Qwen3 0.6B',
    sizeBytes: 344671744,
    minRamBytes: 3500 * 1024 * 1024,
    licence: 'Apache 2.0',
    blurb: 'Small and quick. Good for recaps and word meanings.',
  ),
  LocalModelOption(
    id: 'gemma-4-e2b',
    name: 'Gemma 4 E2B',
    sizeBytes: 2008432640,
    minRamBytes: 7500 * 1024 * 1024,
    licence: 'Apache 2.0',
    blurb: 'Writes more clearly and asks better questions. A big download.',
  ),
];

LocalModelOption? localModelById(String? id) => localModels.where((m) => m.id == id).firstOrNull;

/// What the phone can run.
@immutable
class DeviceProfile {
  const DeviceProfile({required this.supported, this.reason, this.totalRamBytes = 0, this.freeBytes = 0});

  final bool supported;

  /// Why not, in words for the reader.
  final String? reason;
  final int totalRamBytes;

  /// Free storage for app files (0 when unknown).
  final int freeBytes;
}

/// Reads the phone's Android version, ABI, memory and free space.
abstract class DeviceProbe {
  Future<DeviceProfile> read();
}

/// Asks MainActivity over `app.bookreel/device`.
class PlatformDeviceProbe implements DeviceProbe {
  static const _channel = MethodChannel('app.bookreel/device');

  @override
  Future<DeviceProfile> read() async {
    if (kIsWeb || !Platform.isAndroid) {
      return const DeviceProfile(supported: false, reason: 'On-device AI runs on Android phones.');
    }
    // The engine ships for 64-bit ARM only; a 32-bit build of the app has none.
    if (Abi.current() != Abi.androidArm64) {
      return const DeviceProfile(
          supported: false, reason: 'On-device AI needs a 64-bit phone and the 64-bit (arm64) version of the app.');
    }
    final m = await _channel.invokeMapMethod<String, Object?>('capability') ?? const {};
    final sdk = (m['sdk'] as num?)?.toInt() ?? 0;
    if (sdk < 30) {
      return const DeviceProfile(supported: false, reason: 'On-device AI needs Android 11 or newer.');
    }
    return DeviceProfile(
      supported: true,
      totalRamBytes: (m['totalRam'] as num?)?.toInt() ?? 0,
      freeBytes: (m['freeBytes'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A loaded model.
abstract class LocalLlm {
  /// One reply to [prompt], in a fresh conversation.
  Future<String> generate(String prompt, {String? system, int maxOutputTokens = 160, double temperature = 0.3});

  Future<void> close();
}

/// Cancels a download.
class LocalCancel {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get cancelled => _cancelled;

  /// Called on [cancel] (the engine's own token).
  set onCancel(void Function()? f) {
    _onCancel = f;
    if (_cancelled) f?.call();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Installs, removes and loads models (the engine seam).
abstract class LocalModelRuntime {
  Future<bool> isInstalled(LocalModelOption model);

  /// Downloads [model]; [onProgress] gets 0–100.
  Future<void> install(LocalModelOption model, {required void Function(int percent) onProgress, required LocalCancel cancel});

  Future<void> uninstall(LocalModelOption model);

  Future<LocalLlm> open(LocalModelOption model);
}

enum LocalAiPhase {
  checking,

  /// This phone (or build) cannot run a model; see [OnDeviceAiState.message].
  unsupported,

  /// Can run one; none downloaded.
  absent,
  downloading,
  ready,

  /// The download or the model's first load failed; see the message.
  failed,
}

@immutable
class OnDeviceAiState {
  const OnDeviceAiState({this.phase = LocalAiPhase.checking, this.profile, this.model, this.progress = 0, this.message});

  final LocalAiPhase phase;
  final DeviceProfile? profile;

  /// The model downloaded, downloading or that failed.
  final LocalModelOption? model;

  /// Download percent.
  final int progress;
  final String? message;

  /// Whether [option] runs on this phone.
  bool fits(LocalModelOption option) =>
      profile != null && profile!.supported && (profile!.totalRamBytes == 0 || profile!.totalRamBytes >= option.minRamBytes);

  OnDeviceAiState copyWith({int? progress}) =>
      OnDeviceAiState(phase: phase, profile: profile, model: model, progress: progress ?? this.progress, message: message);
}

class _Job<T> {
  _Job(this.task);
  final Future<T> Function(LocalLlm llm) task;
  final done = Completer<T?>();

  Future<void> run(LocalLlm llm) async {
    try {
      done.complete(await task(llm));
    } catch (e) {
      debugPrint('On-device AI: $e');
      done.complete(null);
    }
  }

  void skip() => done.complete(null);
}

/// Downloads and runs the on-device model, one request at a time.
class OnDeviceAiController extends Notifier<OnDeviceAiState> {
  /// The engine; `main.dart` sets LiteRT-LM. Null: this build has none.
  static LocalModelRuntime? Function() runtimeFactory = () => null;
  static DeviceProbe Function() probeFactory = PlatformDeviceProbe.new;

  /// A loaded model is released after this long without requests (it holds
  /// hundreds of MB to a few GB of memory).
  static Duration idleClose = const Duration(minutes: 2);

  LocalModelRuntime? _runtime;
  LocalCancel? _download;
  LocalLlm? _llm;
  Timer? _idle;
  final _queue = <_Job<dynamic>>[];
  bool _busy = false;

  @override
  OnDeviceAiState build() {
    ref.onDispose(() {
      _idle?.cancel();
      _download?.cancel();
      _llm?.close();
      for (final j in _queue) {
        j.skip();
      }
      _queue.clear();
    });
    scheduleMicrotask(_check);
    return const OnDeviceAiState();
  }

  Future<void> _check() async {
    final runtime = _runtime ??= runtimeFactory();
    if (runtime == null) {
      state = const OnDeviceAiState(
          phase: LocalAiPhase.unsupported, message: 'This build of the app has no on-device AI engine.');
      return;
    }
    DeviceProfile profile;
    try {
      profile = await probeFactory().read();
    } catch (e) {
      profile = DeviceProfile(supported: false, reason: 'Couldn’t check this phone: $e');
    }
    if (!profile.supported) {
      state = OnDeviceAiState(phase: LocalAiPhase.unsupported, profile: profile, message: profile.reason);
      return;
    }
    final model = localModelById(ref.read(settingsProvider).localModel);
    if (model != null) {
      var installed = false;
      try {
        installed = await runtime.isInstalled(model);
      } catch (e) {
        debugPrint('On-device AI: $e');
      }
      if (installed) {
        state = OnDeviceAiState(phase: LocalAiPhase.ready, profile: profile, model: model);
        return;
      }
      // The file is gone (cleared storage): forget it.
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(clearLocalModel: true));
    }
    state = OnDeviceAiState(phase: LocalAiPhase.absent, profile: profile);
  }

  /// Downloads [model] (replacing another one), then switches it on.
  Future<void> download(LocalModelOption model) async {
    final runtime = _runtime;
    final profile = state.profile;
    if (runtime == null || profile == null || !state.fits(model) || state.phase == LocalAiPhase.downloading) return;
    const headroom = 200 * 1000 * 1000;
    if (profile.freeBytes > 0 && profile.freeBytes < model.sizeBytes + headroom) {
      state = OnDeviceAiState(
        phase: LocalAiPhase.failed,
        profile: profile,
        model: model,
        message: 'Not enough free space: ${model.name} needs ${formatBytes(model.sizeBytes + headroom)} and the phone has '
            '${formatBytes(profile.freeBytes)} free.',
      );
      return;
    }
    final cancel = _download = LocalCancel();
    state = OnDeviceAiState(phase: LocalAiPhase.downloading, profile: profile, model: model);
    try {
      final old = localModelById(ref.read(settingsProvider).localModel);
      if (old != null && old.id != model.id) {
        // One model at a time: they are large.
        await _closeLlm();
        try {
          await runtime.uninstall(old);
        } catch (e) {
          debugPrint('On-device AI: $e');
        }
        ref.read(settingsProvider.notifier).update((s) => s.copyWith(clearLocalModel: true));
      }
      await runtime.install(model, cancel: cancel, onProgress: (p) {
        if (!cancel.cancelled && state.phase == LocalAiPhase.downloading) state = state.copyWith(progress: p.clamp(0, 100));
      });
      if (cancel.cancelled) {
        state = OnDeviceAiState(phase: LocalAiPhase.absent, profile: profile);
        return;
      }
      ref.read(settingsProvider.notifier).update((s) => s.copyWith(localModel: model.id, onDeviceAi: true));
      state = OnDeviceAiState(phase: LocalAiPhase.ready, profile: profile, model: model);
    } catch (e) {
      state = cancel.cancelled
          ? OnDeviceAiState(phase: LocalAiPhase.absent, profile: profile)
          : OnDeviceAiState(
              phase: LocalAiPhase.failed,
              profile: profile,
              model: model,
              message: 'The download stopped (${_short(e)}). Try again, ideally on Wi-Fi.',
            );
    } finally {
      if (identical(_download, cancel)) _download = null;
    }
  }

  void cancelDownload() => _download?.cancel();

  /// Deletes the downloaded model.
  Future<void> remove() async {
    final model = state.model ?? localModelById(ref.read(settingsProvider).localModel);
    await _closeLlm();
    if (model != null) {
      try {
        await _runtime?.uninstall(model);
      } catch (e) {
        debugPrint('On-device AI: $e');
      }
    }
    ref.read(settingsProvider.notifier).update((s) => s.copyWith(clearLocalModel: true));
    state = OnDeviceAiState(phase: LocalAiPhase.absent, profile: state.profile);
  }

  /// After a failed load: try the downloaded model again.
  void retry() {
    final model = localModelById(ref.read(settingsProvider).localModel);
    if (model == null) {
      state = OnDeviceAiState(phase: LocalAiPhase.absent, profile: state.profile);
    } else {
      state = OnDeviceAiState(phase: LocalAiPhase.ready, profile: state.profile, model: model);
    }
  }

  /// Reading uses the model now: downloaded, switched on, Free plan (paid
  /// plans get the same cards from Claude).
  bool get usable {
    final s = ref.read(settingsProvider);
    return state.phase == LocalAiPhase.ready && s.onDeviceAi && !s.tier.paid;
  }

  /// Runs [task] on the model, one request at a time. [urgent] requests (a
  /// word the reader just tapped) go before background ones. Null when the
  /// model is not usable or the task failed.
  Future<T?> run<T>(Future<T> Function(LocalLlm llm) task, {bool urgent = false}) {
    final job = _Job<T>(task);
    if (!usable) {
      job.skip();
      return job.done.future;
    }
    urgent ? _queue.insert(0, job) : _queue.add(job);
    _pump();
    return job.done.future;
  }

  Future<void> _pump() async {
    if (_busy) return;
    _busy = true;
    _idle?.cancel();
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        if (!usable) {
          job.skip();
          continue;
        }
        LocalLlm llm;
        try {
          llm = _llm ??= await _runtime!.open(state.model!);
        } catch (e) {
          // The phone could not load it (memory, GPU driver…): stop asking.
          state = OnDeviceAiState(
            phase: LocalAiPhase.failed,
            profile: state.profile,
            model: state.model,
            message: 'This phone couldn’t load the model (${_short(e)}). Free cards still work without it.',
          );
          job.skip();
          continue;
        }
        await job.run(llm);
      }
    } finally {
      _busy = false;
      _idle = Timer(idleClose, _closeLlm);
    }
  }

  Future<void> _closeLlm() async {
    _idle?.cancel();
    final llm = _llm;
    _llm = null;
    try {
      await llm?.close();
    } catch (e) {
      debugPrint('On-device AI: $e');
    }
  }

  static String _short(Object e) {
    final s = e.toString().replaceFirst(RegExp(r'^(Exception|StateError|Bad state): '), '');
    return s.length > 120 ? '${s.substring(0, 117)}…' : s;
  }
}

final onDeviceAiProvider = NotifierProvider<OnDeviceAiController, OnDeviceAiState>(OnDeviceAiController.new);
