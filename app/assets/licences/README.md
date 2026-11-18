# Licences of the on-device voice

The natural voice on the phone (Settings → Read aloud) runs on these. The app
shows each licence on its licences page (Settings → About → Licences).

| Component | What it is | Licence | Source |
|---|---|---|---|
| sherpa-onnx 1.13.8 | the speech engine (in the app, from pub.dev) | Apache-2.0 (its own LICENSE, listed automatically) | https://github.com/k2-fsa/sherpa-onnx |
| ONNX Runtime | runs the model (inside sherpa-onnx's library) | MIT | https://github.com/microsoft/onnxruntime |
| espeak-ng | turns English text into sounds (built into sherpa-onnx 1.x's library) | GPL-3.0-or-later | https://github.com/espeak-ng/espeak-ng |
| Kokoro-82M (int8, v0.19) | the voice model, downloaded when the reader asks for it | Apache-2.0 | https://huggingface.co/hexgrad/Kokoro-82M |

**Before a public release:** espeak-ng is GPL-3.0. sherpa-onnx 1.x links it
into the library the app ships, so check with a lawyer whether that requires
the app's own code to be GPL-3.0 too. The alternative is sherpa-onnx 2.x,
which has no espeak-ng: Kokoro then reads from a word list
(`lexicon-en-us.txt`) and silently skips words it doesn't have, such as many
names. The engine version is set in `app/pubspec.yaml`; the model setup is in
`app/lib/services/local_voice.dart`.
