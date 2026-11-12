import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';

import 'on_device_ai.dart';

/// The on-device engine: Google's LiteRT-LM through flutter_edge_ai. Models
/// come from that package's catalog, which pins each file to a Hugging Face
/// commit and its SHA-256. Only `main.dart` imports this file, so tests and
/// the rest of the app depend on [LocalModelRuntime] alone.
///
/// Android: LiteRT-LM needs Android 11+ on 64-bit ARM; [PlatformDeviceProbe]
/// checks both before anything here is called.
class LiteRtRuntime implements LocalModelRuntime {
  static Future<void>? _ready;

  Future<void> _init() => _ready ??= FlutterEdgeAi.initialize(inferenceEngines: const [LiteRtLmEngine()]);

  /// The catalog build for each option in `localModels`.
  static LiteRtLmVariant _variant(LocalModelOption model) => switch (model.id) {
        'gemma-4-e2b' => LiteRtLmModels.gemma4E2bIt.gpu,
        _ => LiteRtLmModels.qwen3_0_6b.dynamicInt4,
      };

  /// Installed models are known by their file name.
  static String _file(LocalModelOption model) => _variant(model).file.installFilename;

  @override
  Future<bool> isInstalled(LocalModelOption model) async {
    await _init();
    final file = _file(model);
    final stem = file.replaceFirst(RegExp(r'\.litertlm$'), '');
    final installed = await FlutterEdgeAi.listInstalledModels();
    return installed.contains(file) || installed.contains(stem);
  }

  @override
  Future<void> install(LocalModelOption model, {required void Function(int percent) onProgress, required LocalCancel cancel}) async {
    await _init();
    final token = CancelToken();
    cancel.onCancel = () => token.cancel('Cancelled by the reader');
    await FlutterEdgeAi.installModelFromCatalog(_variant(model)).withProgress(onProgress).withCancelToken(token).install();
  }

  @override
  Future<void> uninstall(LocalModelOption model) async {
    await _init();
    await FlutterEdgeAi.uninstallModel(_file(model));
  }

  @override
  Future<LocalLlm> open(LocalModelOption model) async {
    await _init();
    final variant = _variant(model);
    // Makes it the active model; the file is already there, so nothing downloads.
    await FlutterEdgeAi.installModelFromCatalog(variant).install();
    // 2048 tokens of context: the longest prompt (a recap) is about 1,300.
    final llm = await FlutterEdgeAi.getActiveModel(defaults: variant.runtimeDefaults, maxTokens: 2048);
    return _LiteRtLlm(llm, qwen3: variant.modelType == ModelType.qwen3);
  }
}

class _LiteRtLlm implements LocalLlm {
  _LiteRtLlm(this._model, {required this.qwen3});

  final InferenceModel _model;

  /// Qwen3 thinks before answering unless told not to on each turn.
  final bool qwen3;

  @override
  Future<String> generate(String prompt, {String? system, int maxOutputTokens = 160, double temperature = 0.3}) async {
    final session = await _model.openSession(
      temperature: temperature,
      topK: 40,
      systemInstruction: system,
      maxOutputTokens: maxOutputTokens,
    );
    try {
      await session.addQueryChunk(Message.text(text: qwen3 ? '$prompt /no_think' : prompt, isUser: true));
      return await session.getResponse();
    } finally {
      await session.close();
    }
  }

  @override
  Future<void> close() => _model.close();
}
