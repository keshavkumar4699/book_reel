import '../models/book.dart';
import '../text/sentence_splitter.dart';

/// A paragraph-level unit before sentence splitting.
class RawBlock {
  const RawBlock(this.type, this.text, {this.sceneBreak = false});

  final BlockType type;
  final String text;

  /// Visual separators such as `* * *`. They are dropped from the text but
  /// mark a strong cut point for the segmenter.
  final bool sceneBreak;
}

final RegExp _sceneBreakRe = RegExp(r'^[\s*#~•·◆◇❖⁂—–\-_=]{1,}$');
final RegExp _dialogueStart = RegExp(r'''^\s*["“‘'«—]''');

bool isSceneBreakText(String text) {
  final t = text.trim();
  return t.isNotEmpty && t.length <= 20 && _sceneBreakRe.hasMatch(t);
}

/// Classifies a plain paragraph as dialogue when it opens with a quote mark
/// or an em dash (common dialogue conventions).
BlockType classifyParagraph(String text) =>
    _dialogueStart.hasMatch(text) ? BlockType.dialogue : BlockType.paragraph;

/// Marker sentence text used to keep scene breaks in the block list so the
/// segmenter can see them. Rendered as an ornament and never counted as words.
const sceneBreakMarker = '⁂';

/// Builds [Block]s with stable sentence IDs for chapter [chapterIndex].
List<Block> buildBlocks(int chapterIndex, Iterable<RawBlock> raw) {
  final blocks = <Block>[];
  for (final r in raw) {
    final text = r.text.trim();
    if (text.isEmpty && !r.sceneBreak) continue;
    final bi = blocks.length;
    if (r.sceneBreak || isSceneBreakText(text)) {
      // Collapse consecutive breaks.
      if (blocks.isNotEmpty && blocks.last.sentences.first.text == sceneBreakMarker) continue;
      blocks.add(Block(
        index: bi,
        type: BlockType.preformatted,
        sentences: [Sentence(id: makeSid(chapterIndex, bi, 0), text: sceneBreakMarker)],
      ));
      continue;
    }
    final List<String> parts;
    if (r.type == BlockType.heading || r.type == BlockType.preformatted) {
      parts = [text.replaceAll(RegExp(r'\s+'), ' ')];
    } else if (r.type == BlockType.quote && text.contains('\n')) {
      // Verse: one line per "sentence" so line breaks survive rendering.
      parts = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    } else {
      parts = splitSentences(text);
    }
    if (parts.isEmpty) continue;
    blocks.add(Block(
      index: bi,
      type: r.type,
      sentences: [
        for (var si = 0; si < parts.length; si++) Sentence(id: makeSid(chapterIndex, bi, si), text: parts[si]),
      ],
    ));
  }
  // Drop leading/trailing scene breaks.
  while (blocks.isNotEmpty && blocks.first.sentences.first.text == sceneBreakMarker) {
    blocks.removeAt(0);
  }
  while (blocks.isNotEmpty && blocks.last.sentences.first.text == sceneBreakMarker) {
    blocks.removeLast();
  }
  return _reindex(chapterIndex, blocks);
}

List<Block> _reindex(int chapterIndex, List<Block> blocks) => [
      for (var bi = 0; bi < blocks.length; bi++)
        Block(
          index: bi,
          type: blocks[bi].type,
          sentences: [
            for (var si = 0; si < blocks[bi].sentences.length; si++)
              Sentence(id: makeSid(chapterIndex, bi, si), text: blocks[bi].sentences[si].text),
          ],
        ),
    ];

bool isSceneBreakBlock(Block b) => b.sentences.length == 1 && b.sentences.first.text == sceneBreakMarker;
